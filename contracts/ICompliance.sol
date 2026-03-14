// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/**
 * @title ICompliance
 * @notice Interface for compliance modules used by PuriCoin.
 * @dev PuriCoin queries {canTransfer} before transfers and calls hooks after lifecycle actions.
 */
interface ICompliance {

    /// @notice Return true if a transfer from -> to of value is permitted.
    function canTransfer(address from, address to, uint256 value) external view returns (bool);

    /// @notice Called after a successful transfer.
    function transferred(address from, address to, uint256 value) external;

    /// @notice Called after tokens are minted/created.
    function created(address to, uint256 value) external;
    
    /// @notice Called after tokens are burned/destroyed.
    function destroyed(address from, uint256 value) external;
}
