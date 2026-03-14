// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface INAVOracle {
    function latestNAV()
        external
        view
        returns (uint256 nav, uint8 decimals_, uint256 updatedAt, bool chainlink);
}
