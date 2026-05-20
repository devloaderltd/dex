// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../IIdentityRegistry.sol";

import "./interfaces/IPurDexFactory.sol";
import "./interfaces/IPurDexPair.sol";
import "./interfaces/IWETH.sol";
import "./libraries/PurDexLibrary.sol";
import "./libraries/TransferHelper.sol";

/// @notice Router for the PurDex AMM.
/// @dev Adds a KYC gate for paths involving PUR (ERC3643-like token with IdentityRegistry).
contract PurDexRouter is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    using TransferHelper for address;

    error Router__Expired();
    error Router__InvalidPath();
    error Router__KycRequired();
    error Router__InsufficientA();
    error Router__InsufficientB();
    error Router__InsufficientOutput();

    address public factory;
    address public WETH;
    address public PUR;
    IIdentityRegistry public identityRegistry;

    /// @dev Prevent the implementation contract from being initialized directly.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier ensure(uint256 deadline) {
        if (deadline < block.timestamp) revert Router__Expired();
        _;
    }

    function initialize(address _factory, address _weth, address _pur, address _identityRegistry) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
        __UUPSUpgradeable_init();

        require(_factory != address(0) && _weth != address(0) && _pur != address(0) && _identityRegistry != address(0), "ZERO");
        factory = _factory;
        WETH = _weth;
        PUR = _pur;
        identityRegistry = IIdentityRegistry(_identityRegistry);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    receive() external payable {
        require(msg.sender == WETH, "ONLY_WETH");
    }
    function version() external pure returns (string memory) { return "v2"; }
    // --- KYC helpers ---
    function _pathTouchesPUR(address[] memory path) internal view returns (bool) {
        address pur = PUR;
        for (uint256 i = 0; i < path.length; i++) {
            if (path[i] == pur) return true;
        }
        return false;
    }

    function _requireVerified(address who) internal view {
        if (!identityRegistry.isVerified(who)) revert Router__KycRequired();
    }

    function _requireKycIfNeeded(address[] memory path, address to) internal view {
        if (_pathTouchesPUR(path)) {
            _requireVerified(msg.sender);
            _requireVerified(to);
        }
    }

    // --- liquidity ---
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal returns (uint256 amountA, uint256 amountB) {
        // create pair if needed
        if (IPurDexFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IPurDexFactory(factory).createPair(tokenA, tokenB);
        }

        (uint256 reserveA, uint256 reserveB) = PurDexLibrary.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = PurDexLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal < amountBMin) revert Router__InsufficientB();
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = PurDexLibrary.quote(amountBDesired, reserveB, reserveA);
                if (amountAOptimal < amountAMin) revert Router__InsufficientA();
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        address[] memory path = new address[](2);
        path[0] = tokenA;
        path[1] = tokenB;
        _requireKycIfNeeded(path, to);

        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = IPurDexFactory(factory).getPair(tokenA, tokenB);

        tokenA.safeTransferFrom(msg.sender, pair, amountA);
        tokenB.safeTransferFrom(msg.sender, pair, amountB);
        liquidity = IPurDexPair(pair).mint(to);
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable nonReentrant ensure(deadline) returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = WETH;
        _requireKycIfNeeded(path, to);

        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );

        address pair = IPurDexFactory(factory).getPair(token, WETH);
        token.safeTransferFrom(msg.sender, pair, amountToken);

        IWETH(WETH).deposit{value: amountETH}();
        WETH.safeTransfer(pair, amountETH);
        liquidity = IPurDexPair(pair).mint(to);

        // refund dust ETH
        if (msg.value > amountETH) {
            TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
        }
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public nonReentrant ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address[] memory path = new address[](2);
        path[0] = tokenA;
        path[1] = tokenB;
        _requireKycIfNeeded(path, to);

        address pair = IPurDexFactory(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "PAIR_NOT_FOUND");

        pair.safeTransferFrom(msg.sender, pair, liquidity);
        (uint256 amount0, uint256 amount1) = IPurDexPair(pair).burn(to);
        (address token0, ) = PurDexLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        if (amountA < amountAMin) revert Router__InsufficientA();
        if (amountB < amountBMin) revert Router__InsufficientB();
    }

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256 amountToken, uint256 amountETH) {
        (amountToken, amountETH) = removeLiquidity(token, WETH, liquidity, amountTokenMin, amountETHMin, address(this), deadline);

        token.safeTransfer(to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    // --- swaps ---
    function _swap(uint256[] memory amounts, address[] memory path, address _to, address _currentPair) internal {
        // Optimization: Use a sliding window to cache the pair address, eliminating a redundant
        // external factory call to `getPair` in each iteration.
        address currentPair = _currentPair;
        for (uint256 i = 0; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = PurDexLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));

            address to = i < path.length - 2
                ? IPurDexFactory(factory).getPair(output, path[i + 2])
                : _to;

            IPurDexPair(currentPair).swap(amount0Out, amount1Out, to, new bytes(0));
            currentPair = to;
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256[] memory amounts) {
        if (path.length < 2) revert Router__InvalidPath();
        address[] memory mpath = path;
        _requireKycIfNeeded(mpath, to);

        amounts = PurDexLibrary.getAmountsOut(factory, amountIn, mpath);
        if (amounts[amounts.length - 1] < amountOutMin) revert Router__InsufficientOutput();

        address pair = IPurDexFactory(factory).getPair(mpath[0], mpath[1]);
        mpath[0].safeTransferFrom(msg.sender, pair, amounts[0]);
        _swap(amounts, mpath, to, pair);
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable nonReentrant ensure(deadline) returns (uint256[] memory amounts) {
        if (path.length < 2) revert Router__InvalidPath();
        require(path[0] == WETH, "PATH_MUST_START_WETH");
        address[] memory mpath = path;
        _requireKycIfNeeded(mpath, to);

        amounts = PurDexLibrary.getAmountsOut(factory, msg.value, mpath);
        if (amounts[amounts.length - 1] < amountOutMin) revert Router__InsufficientOutput();

        IWETH(WETH).deposit{value: amounts[0]}();
        address pair = IPurDexFactory(factory).getPair(mpath[0], mpath[1]);
        WETH.safeTransfer(pair, amounts[0]);
        _swap(amounts, mpath, to, pair);
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256[] memory amounts) {
        if (path.length < 2) revert Router__InvalidPath();
        require(path[path.length - 1] == WETH, "PATH_MUST_END_WETH");
        address[] memory mpath = path;
        _requireKycIfNeeded(mpath, to);

        amounts = PurDexLibrary.getAmountsOut(factory, amountIn, mpath);
        if (amounts[amounts.length - 1] < amountOutMin) revert Router__InsufficientOutput();

        address pair = IPurDexFactory(factory).getPair(mpath[0], mpath[1]);
        mpath[0].safeTransferFrom(msg.sender, pair, amounts[0]);
        _swap(amounts, mpath, address(this), pair);
        uint256 amountOut = amounts[amounts.length - 1];
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    // --- convenience swaps for ETH <-> PUR ---
    /// @notice Swap native ETH directly to PUR (internally wraps to WETH).
    /// @dev Equivalent to swapExactETHForTokens with path [WETH, PUR].
    function swapExactETHForPUR(
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external payable nonReentrant ensure(deadline) returns (uint256[] memory amounts) {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = PUR;
        _requireKycIfNeeded(path, to);

        amounts = PurDexLibrary.getAmountsOut(factory, msg.value, path);
        if (amounts[amounts.length - 1] < amountOutMin) revert Router__InsufficientOutput();

        IWETH(WETH).deposit{value: amounts[0]}();
        address pair = IPurDexFactory(factory).getPair(path[0], path[1]);
        WETH.safeTransfer(pair, amounts[0]);
        _swap(amounts, path, to, pair);
    }

    /// @notice Swap PUR directly to native ETH (internally unwraps WETH).
    /// @dev Equivalent to swapExactTokensForETH with path [PUR, WETH].
    function swapExactPURForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256[] memory amounts) {
        address[] memory path = new address[](2);
        path[0] = PUR;
        path[1] = WETH;
        _requireKycIfNeeded(path, to);

        amounts = PurDexLibrary.getAmountsOut(factory, amountIn, path);
        if (amounts[amounts.length - 1] < amountOutMin) revert Router__InsufficientOutput();

        address pair = IPurDexFactory(factory).getPair(path[0], path[1]);
        path[0].safeTransferFrom(msg.sender, pair, amounts[0]);
        _swap(amounts, path, address(this), pair);
        uint256 amountOut = amounts[amounts.length - 1];
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    // --- pure/view helpers for frontends ---
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) external pure returns (uint256 amountB) {
        return PurDexLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) external pure returns (uint256 amountOut) {
        return PurDexLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) external pure returns (uint256 amountIn) {
        return PurDexLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts) {
        return PurDexLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts) {
        return PurDexLibrary.getAmountsIn(factory, amountOut, path);
    }
}
