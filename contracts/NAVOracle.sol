// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title NAVOracle
 * @notice NAV oracle with optional Chainlink feed and manual fallback.
 * @dev If chainlinkFeed is set, {latestNAV} returns feed data; otherwise it returns manual values.
 */



contract NAVOracle is Ownable {
    /// @notice Optional Chainlink AggregatorV3 feed. Set to address(0) to disable.
    AggregatorV3Interface public chainlinkFeed;

    /// @notice Manual NAV value used when no Chainlink feed is configured.
    uint256 public manualNav;

    /// @notice Decimals for the manual NAV value.
    uint8 public manualDecimals;
    
    /// @notice Timestamp when manual NAV was last updated.
    uint256 public manualUpdatedAt;

    /// @notice Emitted when NAV is updated (manual update always emits; Chainlink returns are indicated in latestNAV).
    event NAVUpdated(uint256 nav, uint8 decimals, bool fromChainlink);

    /**
     * @param feed Chainlink AggregatorV3 address (optional; can be address(0)).
     */
    constructor(address feed) {
        if (feed != address(0)) {
            chainlinkFeed = AggregatorV3Interface(feed);
        }
    }

    /**
     * @notice Update the Chainlink feed address.
     * @param feed AggregatorV3 address (use address(0) to disable).
     * @dev Only callable by the owner.
     */
    function setChainlinkFeed(address feed) external onlyOwner {
        chainlinkFeed = AggregatorV3Interface(feed);
    }

    /**
     * @notice Set NAV manually (fallback when Chainlink is disabled).
     * @param nav_ NAV value.
     * @param decimals_ NAV decimals.
     * @dev Only callable by the owner.
     */
    function setManualNAV(uint256 nav_, uint8 decimals_) external onlyOwner {
        manualNav = nav_;
        manualDecimals = decimals_;
        manualUpdatedAt = block.timestamp;
        emit NAVUpdated(nav_, decimals_, false);
    }

    /**
     * @notice Return the latest NAV data.
     * @return nav NAV value.
     * @return decimals_ NAV decimals.
     * @return updatedAt Timestamp for the NAV value.
     * @return chainlink True if Chainlink feed was used, false if manual fallback.
     */
    function latestNAV()
        external
        view
        returns (uint256 nav, uint8 decimals_, uint256 updatedAt, bool chainlink)
    {
        if (address(chainlinkFeed) != address(0)) {
            (, int256 answer,, uint256 updated,) = chainlinkFeed.latestRoundData();
            require(answer > 0, "Invalid feed");
            require(updated > 0, "Invalid timestamp");
            decimals_ = chainlinkFeed.decimals();
            return (uint256(answer), decimals_, updated, true);
        }

        return (manualNav, manualDecimals, manualUpdatedAt, false);
    }
}
