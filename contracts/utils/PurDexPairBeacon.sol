// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/// @notice Beacon used by all PurDexPair BeaconProxy instances.
/// @dev Thin wrapper so Hardhat always produces an artifact for UpgradeableBeacon.
contract PurDexPairBeacon is UpgradeableBeacon {
    constructor(address implementation_) UpgradeableBeacon(implementation_) {}
}
