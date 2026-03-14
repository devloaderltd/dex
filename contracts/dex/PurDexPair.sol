// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

import "./libraries/Math.sol";
import "./libraries/TransferHelper.sol";
import "./interfaces/IPurDexFactory.sol";

/// @notice Constant-product AMM pair (similar shape to UniswapV2Pair).
/// @dev
///  - Deployed behind an OZ BeaconProxy (one proxy per pair).
///  - Upgrading the beacon upgrades the logic for all pairs.
///  - This contract MUST be initialized via initialize().
contract PurDexPair is Initializable, ERC20PermitUpgradeable {
    using TransferHelper for address;

    error PurDexPair__Forbidden();
    error PurDexPair__Locked();
    error PurDexPair__InsufficientLiquidityMinted();
    error PurDexPair__InsufficientLiquidityBurned();
    error PurDexPair__InsufficientOutputAmount();
    error PurDexPair__InsufficientInputAmount();
    error PurDexPair__InvalidTo();
    error PurDexPair__KInvariant();

    uint256 public constant MINIMUM_LIQUIDITY = 1_000;
    address private constant LOCK_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    address public factory;
    address public token0;
    address public token1;

    uint112 private reserve0; // uses single storage slot, accessible via getReserves
    uint112 private reserve1; // uses single storage slot, accessible via getReserves
    uint32 private blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    uint256 private unlocked;
    modifier lock() {
        if (unlocked != 1) revert PurDexPair__Locked();
        unlocked = 0;
        _;
        unlocked = 1;
    }

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    /// @dev Prevent the implementation contract from being initialized directly.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializer (called once by the factory).
    function initialize(address _factory, address _token0, address _token1) external initializer {
        if (_factory == address(0) || _token0 == address(0) || _token1 == address(0)) revert PurDexPair__Forbidden();
        factory = _factory;
        token0 = _token0;
        token1 = _token1;

        __ERC20_init("PurDex LP", "PURDEX-LP");
        __ERC20Permit_init("PurDex LP");

        unlocked = 1;
    }

    function getReserves()
        public
        view
        returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast)
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    // --- internal helpers ---
    function _safeBalance(address token) private view returns (uint256) {
        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSignature("balanceOf(address)", address(this))
        );
        require(ok && data.length >= 32, "BALANCEOF_FAILED");
        return abi.decode(data, (uint256));
    }

    function _update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "OVERFLOW");

        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;

        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // price accumulators (fixed point, Q112.112). We keep it for TWAP integrations.
            price0CumulativeLast += (uint256(_reserve1) << 112) / uint256(_reserve0) * timeElapsed;
            price1CumulativeLast += (uint256(_reserve0) << 112) / uint256(_reserve1) * timeElapsed;
        }

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = IPurDexFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint256 _kLast = kLast;

        if (feeOn) {
            if (_kLast != 0) {
                uint256 rootK = Math.sqrt(uint256(_reserve0) * uint256(_reserve1));
                uint256 rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    // 1/6th of growth in sqrt(k)
                    uint256 numerator = totalSupply() * (rootK - rootKLast);
                    uint256 denominator = (rootK * 5) + rootKLast;
                    uint256 liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    // --- external AMM actions ---
    function mint(address to) external lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        uint256 balance0 = _safeBalance(token0);
        uint256 balance1 = _safeBalance(token1);
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply();

        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            // OZ ERC20 forbids minting to address(0). We lock the minimum liquidity forever at a dead address.
            _mint(LOCK_ADDRESS, MINIMUM_LIQUIDITY);
        } else {
            liquidity = Math.min((amount0 * _totalSupply) / _reserve0, (amount1 * _totalSupply) / _reserve1);
        }

        if (liquidity == 0) revert PurDexPair__InsufficientLiquidityMinted();
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0) * uint256(reserve1);
        emit Mint(msg.sender, amount0, amount1);
    }

    function burn(address to) external lock returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();

        uint256 balance0 = _safeBalance(token0);
        uint256 balance1 = _safeBalance(token1);
        uint256 liquidity = balanceOf(address(this));

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply();

        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;
        if (amount0 == 0 || amount1 == 0) revert PurDexPair__InsufficientLiquidityBurned();

        _burn(address(this), liquidity);
        token0.safeTransfer(to, amount0);
        token1.safeTransfer(to, amount1);

        balance0 = _safeBalance(token0);
        balance1 = _safeBalance(token1);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0) * uint256(reserve1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata) external lock {
        if (amount0Out == 0 && amount1Out == 0) revert PurDexPair__InsufficientOutputAmount();
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "INSUFFICIENT_LIQUIDITY");
        if (to == token0 || to == token1) revert PurDexPair__InvalidTo();

        if (amount0Out > 0) token0.safeTransfer(to, amount0Out);
        if (amount1Out > 0) token1.safeTransfer(to, amount1Out);

        uint256 balance0 = _safeBalance(token0);
        uint256 balance1 = _safeBalance(token1);

        uint256 amount0In = balance0 > (_reserve0 - amount0Out) ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > (_reserve1 - amount1Out) ? balance1 - (_reserve1 - amount1Out) : 0;
        if (amount0In == 0 && amount1In == 0) revert PurDexPair__InsufficientInputAmount();

        // Adjusted balances (0.30% fee)
        uint256 balance0Adjusted = (balance0 * 1000) - (amount0In * 3);
        uint256 balance1Adjusted = (balance1 * 1000) - (amount1In * 3);
        if (balance0Adjusted * balance1Adjusted < uint256(_reserve0) * uint256(_reserve1) * 1_000_000) {
            revert PurDexPair__KInvariant();
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function skim(address to) external lock {
        token0.safeTransfer(to, _safeBalance(token0) - reserve0);
        token1.safeTransfer(to, _safeBalance(token1) - reserve1);
    }

    function sync() external lock {
        _update(_safeBalance(token0), _safeBalance(token1), reserve0, reserve1);
    }
}
