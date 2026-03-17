// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../IIdentityRegistry.sol";
import "../interfaces/IPuriCoin.sol";
import "../dex/interfaces/IWETH.sol";
import "../dex/libraries/TransferHelper.sol";
import "./PurDexOracleRouter.sol";

/// @title PurDexLendingPool
/// @notice A minimal money-market for PUR, inspired by Aave/Compound.
/// @dev
///  - Suppliers deposit PUR to earn interest.
///  - Borrowers lock ETH (WETH) as collateral and borrow PUR.
///  - Interest accrues to borrowers over time; suppliers earn from borrower interest.
///
/// Parameters (per your spec):
///  - Variable interest with base=2% and slope=20% (utilization based)
///  - LTV=50%, liquidation threshold=60%, liquidation bonus=5%
contract PurDexLendingPool is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using TransferHelper for address;

    // --- constants ---
    uint256 public constant WAD = 1e18;
    uint256 public constant BPS = 10_000;
    uint256 public constant SECONDS_PER_YEAR = 31_536_000;

    // --- external deps ---
    IPuriCoin public pur;
    IWETH public weth;
    IIdentityRegistry public identityRegistry;
    PurDexOracleRouter public oracle;

    // --- risk params ---
    uint256 public ltvBps; // 50%
    uint256 public liquidationThresholdBps; // 60%
    uint256 public liquidationBonusBps; // +5%

    // --- interest params ---
    uint256 public baseRatePerYear; // 2% APR (WAD)
    uint256 public slopePerYear; // +20% APR at 100% util (WAD)
    uint256 public reserveFactorBps; // % of borrower interest to protocol reserves

    // --- supply accounting (shares) ---
    uint256 public totalSupplyShares;
    mapping(address => uint256) public supplyShares;

    // --- borrow accounting (Compound-like index) ---
    struct BorrowSnapshot {
        uint256 principal;
        uint256 interestIndex;
    }
    mapping(address => BorrowSnapshot) public accountBorrows;

    uint256 public totalBorrows;
    uint256 public totalReserves;
    uint256 public borrowIndex;
    uint256 public lastAccrual;

    // --- collateral ---
    mapping(address => uint256) public collateralWeth;

    // --- events ---
    event OracleUpdated(address oracle);
    event RiskParamsUpdated(uint256 ltvBps, uint256 liquidationThresholdBps, uint256 liquidationBonusBps);
    event InterestParamsUpdated(uint256 baseRatePerYear, uint256 slopePerYear, uint256 reserveFactorBps);
    event Accrued(uint256 interestAccumulated, uint256 newBorrowIndex, uint256 newTotalBorrows, uint256 newTotalReserves);

    event Supplied(address indexed user, uint256 amount, uint256 shares);
    event Withdrawn(address indexed user, uint256 amount, uint256 shares);
    event CollateralDeposited(address indexed user, uint256 wethAmount);
    event CollateralWithdrawn(address indexed user, uint256 wethAmount);
    event Borrowed(address indexed user, uint256 amount, uint256 newDebt);
    event Repaid(address indexed payer, address indexed borrower, uint256 amount, uint256 remainingDebt);
    event Liquidated(address indexed liquidator, address indexed borrower, uint256 repaidPur, uint256 seizedWeth);

    error LP__KycRequired();
    error LP__ZeroAmount();
    error LP__InsufficientLiquidity();
    error LP__HealthFactorTooLow();
    error LP__NotLiquidatable();

    /// @dev Prevent the implementation contract from being initialized directly.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _pur, address _weth, address _identityRegistry, address _oracle) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        require(_pur != address(0) && _weth != address(0) && _identityRegistry != address(0) && _oracle != address(0), "ZERO");
        pur = IPuriCoin(_pur);
        weth = IWETH(_weth);
        identityRegistry = IIdentityRegistry(_identityRegistry);
        oracle = PurDexOracleRouter(_oracle);

        // defaults per your requested config
        ltvBps = 5_000;
        liquidationThresholdBps = 6_000;
        liquidationBonusBps = 500;
        baseRatePerYear = 2e16; // 2%
        slopePerYear = 2e17; // 20%
        reserveFactorBps = 1_000; // 10%

        borrowIndex = WAD;
        lastAccrual = block.timestamp;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    receive() external payable {
        // only allow receiving ETH from WETH withdraw
        require(msg.sender == address(weth), "ONLY_WETH");
    }

    // --- admin ---
    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "ZERO");
        oracle = PurDexOracleRouter(_oracle);
        emit OracleUpdated(_oracle);
    }

    function setRiskParams(uint256 _ltvBps, uint256 _liqThresholdBps, uint256 _liqBonusBps) external onlyOwner {
        require(_ltvBps <= _liqThresholdBps && _liqThresholdBps <= BPS, "BAD_PARAMS");
        ltvBps = _ltvBps;
        liquidationThresholdBps = _liqThresholdBps;
        liquidationBonusBps = _liqBonusBps;
        emit RiskParamsUpdated(_ltvBps, _liqThresholdBps, _liqBonusBps);
    }

    function setInterestParams(uint256 _baseRatePerYear, uint256 _slopePerYear, uint256 _reserveFactorBps) external onlyOwner {
        require(_reserveFactorBps <= BPS, "BAD_PARAMS");
        baseRatePerYear = _baseRatePerYear;
        slopePerYear = _slopePerYear;
        reserveFactorBps = _reserveFactorBps;
        emit InterestParamsUpdated(_baseRatePerYear, _slopePerYear, _reserveFactorBps);
    }

    /// @notice Withdraw protocol reserves (earned from reserveFactor).
    function withdrawReserves(address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "ZERO");
        accrueInterest();
        require(amount <= totalReserves, "TOO_MUCH");
        totalReserves -= amount;
        address(pur).safeTransfer(to, amount);
    }

    // --- KYC ---
    function _requireVerified(address who) internal view {
        if (!identityRegistry.isVerified(who)) revert LP__KycRequired();
    }

    // --- rates ---
    function utilization() public view returns (uint256 utilWad) {
        uint256 cash = IERC20(address(pur)).balanceOf(address(this));
        if (totalBorrows == 0) return 0;
        return (totalBorrows * WAD) / (cash + totalBorrows);
    }

    function borrowRatePerSecond() public view returns (uint256 ratePerSecondWad) {
        uint256 util = utilization();
        uint256 ratePerYear = baseRatePerYear + ((slopePerYear * util) / WAD);
        return ratePerYear / SECONDS_PER_YEAR;
    }

    // --- interest accrual ---
    function accrueInterest() public {
        uint256 ts = block.timestamp;
        uint256 dt = ts - lastAccrual;
        if (dt == 0) return;

        lastAccrual = ts;
        if (totalBorrows == 0) return;

        uint256 rate = borrowRatePerSecond();
        uint256 interestFactor = rate * dt; // WAD
        uint256 interestAccumulated = (totalBorrows * interestFactor) / WAD;
        if (interestAccumulated == 0) return;

        uint256 reservesAdded = (interestAccumulated * reserveFactorBps) / BPS;
        totalReserves += reservesAdded;
        totalBorrows += interestAccumulated;

        // update borrow index
        borrowIndex += (borrowIndex * interestFactor) / WAD;

        emit Accrued(interestAccumulated, borrowIndex, totalBorrows, totalReserves);
    }

    // --- views ---
    function totalAssets() public view returns (uint256 assets) {
        uint256 cash = IERC20(address(pur)).balanceOf(address(this));
        assets = cash + totalBorrows;
        if (assets >= totalReserves) assets -= totalReserves;
        else assets = 0;
    }

    function exchangeRate() public view returns (uint256) {
        if (totalSupplyShares == 0) return WAD;
        return (totalAssets() * WAD) / totalSupplyShares;
    }

    function supplyBalanceUnderlying(address user) external view returns (uint256) {
        if (totalSupplyShares == 0) return 0;
        return (supplyShares[user] * totalAssets()) / totalSupplyShares;
    }

    function borrowBalanceCurrent(address borrower) public view returns (uint256) {
        BorrowSnapshot memory bs = accountBorrows[borrower];
        if (bs.principal == 0) return 0;
        return (bs.principal * borrowIndex) / bs.interestIndex;
    }

    function accountLiquidity(address user)
        public
        view
        returns (uint256 collateralUsd, uint256 debtUsd, uint256 maxBorrowUsd, bool liquidatable)
    {
        (uint256 ethPrice, ) = oracle.ethUsdPrice();
        (uint256 purPrice, ) = oracle.purUsdPrice();
        return _accountLiquidity(user, ethPrice, purPrice);
    }

    function _accountLiquidity(address user, uint256 ethPrice, uint256 purPrice)
        internal
        view
        returns (uint256 collateralUsd, uint256 debtUsd, uint256 maxBorrowUsd, bool liquidatable)
    {
        collateralUsd = (collateralWeth[user] * ethPrice) / WAD;
        uint256 debtPur = borrowBalanceCurrent(user);
        debtUsd = (debtPur * purPrice) / WAD;
        maxBorrowUsd = (collateralUsd * ltvBps) / BPS;
        uint256 liqThresholdUsd = (collateralUsd * liquidationThresholdBps) / BPS;
        liquidatable = debtUsd > liqThresholdUsd;
    }

    // --- supply ---
    function supply(uint256 amount) external nonReentrant {
        _requireVerified(msg.sender);
        if (amount == 0) revert LP__ZeroAmount();

        accrueInterest();

        uint256 assets = totalAssets();
        uint256 shares;
        if (totalSupplyShares == 0) {
            shares = amount;
        } else {
            shares = (amount * totalSupplyShares) / assets;
        }

        require(shares > 0, "SHARES_ZERO");

        totalSupplyShares += shares;
        supplyShares[msg.sender] += shares;

        address(pur).safeTransferFrom(msg.sender, address(this), amount);
        emit Supplied(msg.sender, amount, shares);
    }

    function withdraw(uint256 shares) external nonReentrant {
        _requireVerified(msg.sender);
        if (shares == 0) revert LP__ZeroAmount();
        require(shares <= supplyShares[msg.sender], "NOT_ENOUGH_SHARES");

        accrueInterest();
        uint256 amount = (shares * totalAssets()) / totalSupplyShares;

        uint256 cash = IERC20(address(pur)).balanceOf(address(this));
        if (amount > cash) revert LP__InsufficientLiquidity();

        supplyShares[msg.sender] -= shares;
        totalSupplyShares -= shares;

        address(pur).safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount, shares);
    }

    // --- collateral ---
    function depositCollateralETH() external payable nonReentrant {
        _requireVerified(msg.sender);
        if (msg.value == 0) revert LP__ZeroAmount();
        weth.deposit{value: msg.value}();
        collateralWeth[msg.sender] += msg.value;
        emit CollateralDeposited(msg.sender, msg.value);
    }

    function withdrawCollateralETH(uint256 wethAmount) external nonReentrant {
        _requireVerified(msg.sender);
        if (wethAmount == 0) revert LP__ZeroAmount();
        require(wethAmount <= collateralWeth[msg.sender], "NOT_ENOUGH_COLLATERAL");

        accrueInterest();
        collateralWeth[msg.sender] -= wethAmount;
        if (!_isHealthy(msg.sender)) {
            collateralWeth[msg.sender] += wethAmount;
            revert LP__HealthFactorTooLow();
        }

        weth.withdraw(wethAmount);
        TransferHelper.safeTransferETH(msg.sender, wethAmount);
        emit CollateralWithdrawn(msg.sender, wethAmount);
    }

    // --- borrow/repay ---
    function borrow(uint256 amount) external nonReentrant {
        _requireVerified(msg.sender);
        if (amount == 0) revert LP__ZeroAmount();
        accrueInterest();

        uint256 cash = IERC20(address(pur)).balanceOf(address(this));
        if (amount > cash) revert LP__InsufficientLiquidity();

        if (!_canBorrow(msg.sender, amount)) revert LP__HealthFactorTooLow();

        uint256 currentDebt = borrowBalanceCurrent(msg.sender);
        uint256 newPrincipal = currentDebt + amount;
        accountBorrows[msg.sender] = BorrowSnapshot({principal: newPrincipal, interestIndex: borrowIndex});
        totalBorrows += amount;

        address(pur).safeTransfer(msg.sender, amount);
        emit Borrowed(msg.sender, amount, newPrincipal);
    }

    function repay(uint256 amount) external nonReentrant {
        accrueInterest();
        _repayFrom(msg.sender, msg.sender, amount);
    }

    function repayOnBehalf(address borrower, uint256 amount) external nonReentrant {
        accrueInterest();
        _repayFrom(msg.sender, borrower, amount);
    }

    function _repayFrom(address payer, address borrower, uint256 amount) internal {
        _requireVerified(payer);
        _requireVerified(borrower);
        if (amount == 0) revert LP__ZeroAmount();
        uint256 debt = borrowBalanceCurrent(borrower);
        uint256 repayAmount = amount > debt ? debt : amount;
        require(repayAmount > 0, "NO_DEBT");

        uint256 newPrincipal = debt - repayAmount;
        accountBorrows[borrower] = BorrowSnapshot({principal: newPrincipal, interestIndex: borrowIndex});
        totalBorrows -= repayAmount;

        address(pur).safeTransferFrom(payer, address(this), repayAmount);
        emit Repaid(payer, borrower, repayAmount, newPrincipal);
    }

    // --- liquidation ---
    function liquidate(address borrower, uint256 repayAmount) external nonReentrant {
        _requireVerified(msg.sender);
        _requireVerified(borrower);
        if (repayAmount == 0) revert LP__ZeroAmount();

        accrueInterest();

        // OPTIMIZATION: Fetch oracle prices once and reuse them for accountLiquidity and liquidation calculations.
        // This avoids 2 redundant external calls to the oracle router.
        (uint256 ethPrice, ) = oracle.ethUsdPrice();
        (uint256 purPrice, ) = oracle.purUsdPrice();

        (, , , bool liquidatable) = _accountLiquidity(borrower, ethPrice, purPrice);
        if (!liquidatable) revert LP__NotLiquidatable();

        uint256 debt = borrowBalanceCurrent(borrower);
        uint256 actualRepay = repayAmount > debt ? debt : repayAmount;
        require(actualRepay > 0, "NO_DEBT");

        uint256 repayUsd = (actualRepay * purPrice) / WAD;
        uint256 seizeUsd = (repayUsd * (BPS + liquidationBonusBps)) / BPS;
        uint256 seizeWethAmount = (seizeUsd * WAD) / ethPrice;

        uint256 borrowerColl = collateralWeth[borrower];
        if (seizeWethAmount > borrowerColl) {
            seizeWethAmount = borrowerColl;
            uint256 seizeUsdCapped = (seizeWethAmount * ethPrice) / WAD;
            uint256 repayUsdCapped = (seizeUsdCapped * BPS) / (BPS + liquidationBonusBps);
            actualRepay = (repayUsdCapped * WAD) / purPrice;
        }

        _repayFrom(msg.sender, borrower, actualRepay);

        collateralWeth[borrower] -= seizeWethAmount;
        require(weth.transfer(msg.sender, seizeWethAmount), "WETH_TRANSFER_FAIL");
        emit Liquidated(msg.sender, borrower, actualRepay, seizeWethAmount);
    }

    // --- internal health checks ---
    function _canBorrow(address borrower, uint256 additionalPur) internal view returns (bool) {
        // OPTIMIZATION: Fetch prices once to avoid redundant external call in accountLiquidity.
        (uint256 ethPrice, ) = oracle.ethUsdPrice();
        (uint256 purPrice, ) = oracle.purUsdPrice();

        (uint256 collateralUsd, uint256 debtUsd, uint256 maxBorrowUsd, ) = _accountLiquidity(borrower, ethPrice, purPrice);

        uint256 addUsd = (additionalPur * purPrice) / WAD;
        if (collateralUsd == 0) return false;
        return debtUsd + addUsd <= maxBorrowUsd;
    }

    function _isHealthy(address borrower) internal view returns (bool) {
        (uint256 collateralUsd, uint256 debtUsd, uint256 maxBorrowUsd, ) = accountLiquidity(borrower);
        if (debtUsd == 0) return true;
        if (collateralUsd == 0) return false;
        return debtUsd <= maxBorrowUsd;
    }
}
