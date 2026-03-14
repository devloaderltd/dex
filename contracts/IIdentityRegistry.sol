// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/**
 * @title IIdentityRegistry
 * @notice Interface for the identity/KYC registry used by PuriCoin.
 * @dev PuriCoin checks verification status to enforce permissioned transfers.
 */
interface IIdentityRegistry {
    
    /// @notice Returns true if the investor wallet is verified (KYC-approved).
    function isVerified(address investor) external view returns (bool);

    /// @notice Returns the stored numeric country code for the investor wallet.
    function investorCountry(address investor) external view returns (uint16);
}
