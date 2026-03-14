// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "./interfaces/INAVOracle.sol";

/// @title PurDexOracleRouter
/// @notice Normalizes oracle prices into a single 1e18 fixed-point format.
/// @dev
///  - ETH/USD comes from Chainlink AggregatorV3Interface.
///  - PUR/USD comes from your NAVOracle (manual or Chainlink-backed).
///  - Each price can fall back to a manual value if a feed is not set or if you prefer.
contract PurDexOracleRouter is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    error Oracle__BadAnswer();
    error Oracle__Stale();

    AggregatorV3Interface public ethUsdFeed; // optional
    INAVOracle public purUsdOracle; // optional

    uint256 public manualEthUsdPrice1e18;
    uint256 public manualPurUsdPrice1e18;
    bool public useManualEth;
    bool public useManualPur;

    /// @notice If > 0, oracle answers older than this are considered stale.
    uint256 public maxAge;

    event EthFeedUpdated(address feed);
    event PurOracleUpdated(address oracle);
    event ManualEthUpdated(uint256 price1e18, bool enabled);
    event ManualPurUpdated(uint256 price1e18, bool enabled);
    event MaxAgeUpdated(uint256 maxAge);

    /// @dev Prevent the implementation contract from being initialized directly.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _ethUsdFeed, address _purUsdOracle) external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();

        if (_ethUsdFeed != address(0)) {
            ethUsdFeed = AggregatorV3Interface(_ethUsdFeed);
        }
        if (_purUsdOracle != address(0)) {
            purUsdOracle = INAVOracle(_purUsdOracle);
        }
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function setMaxAge(uint256 _maxAge) external onlyOwner {
        maxAge = _maxAge;
        emit MaxAgeUpdated(_maxAge);
    }

    function setEthUsdFeed(address feed) external onlyOwner {
        ethUsdFeed = AggregatorV3Interface(feed);
        useManualEth = false;
        emit EthFeedUpdated(feed);
    }

    function setPurUsdOracle(address oracle) external onlyOwner {
        purUsdOracle = INAVOracle(oracle);
        useManualPur = false;
        emit PurOracleUpdated(oracle);
    }

    function setManualEthUsdPrice(uint256 price1e18, bool enabled) external onlyOwner {
        manualEthUsdPrice1e18 = price1e18;
        useManualEth = enabled;
        emit ManualEthUpdated(price1e18, enabled);
    }

    function setManualPurUsdPrice(uint256 price1e18, bool enabled) external onlyOwner {
        manualPurUsdPrice1e18 = price1e18;
        useManualPur = enabled;
        emit ManualPurUpdated(price1e18, enabled);
    }

    /// @notice ETH/USD price in 1e18.
    function ethUsdPrice() external view returns (uint256 price1e18, uint256 updatedAt) {
        return _ethUsdPrice();
    }

    /// @notice PUR/USD price in 1e18.
    function purUsdPrice() external view returns (uint256 price1e18, uint256 updatedAt) {
        return _purUsdPrice();
    }

    function _ethUsdPrice() internal view returns (uint256 price1e18, uint256 updatedAt) {
        if (useManualEth || address(ethUsdFeed) == address(0)) {
            return (manualEthUsdPrice1e18, block.timestamp);
        }
        (, int256 answer, , uint256 updated, ) = ethUsdFeed.latestRoundData();
        if (answer <= 0) revert Oracle__BadAnswer();
        updatedAt = updated;
        if (maxAge > 0 && updatedAt + maxAge < block.timestamp) revert Oracle__Stale();
        uint8 d = ethUsdFeed.decimals();
        price1e18 = _scaleTo1e18(uint256(answer), d);
    }

    function _purUsdPrice() internal view returns (uint256 price1e18, uint256 updatedAt) {
        if (useManualPur || address(purUsdOracle) == address(0)) {
            return (manualPurUsdPrice1e18, block.timestamp);
        }
        (uint256 nav, uint8 d, uint256 updated, ) = purUsdOracle.latestNAV();
        if (nav == 0) revert Oracle__BadAnswer();
        updatedAt = updated;
        if (maxAge > 0 && updatedAt + maxAge < block.timestamp) revert Oracle__Stale();
        price1e18 = _scaleTo1e18(nav, d);
    }

    function _scaleTo1e18(uint256 value, uint8 decimals_) internal pure returns (uint256) {
        if (decimals_ == 18) return value;
        if (decimals_ < 18) return value * (10 ** (18 - decimals_));
        return value / (10 ** (decimals_ - 18));
    }
}
