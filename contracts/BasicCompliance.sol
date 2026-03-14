// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./ICompliance.sol";

/**
 * @title BasicCompliance
 * @notice Minimal compliance module used by PuriCoin to approve/deny transfers.
 * @dev
 *  - Owner can pause transfers globally.
 *  - Owner can blacklist specific addresses.
 *  - This is a starter implementation intended to be extended for real compliance rules.
 */


contract BasicCompliance is ICompliance, Ownable {

    /// @notice Addresses blocked from sending/receiving tokens.
    mapping(address => bool) public blacklist;

    /// @notice Global pause flag; when true, all transfers are blocked.
    bool public paused;

    /// @notice Emitted when blacklist status changes for an address.
    event BlacklistUpdated(address indexed account, bool blacklisted);

    /// @notice Emitted when the global paused state changes.
    event Paused(bool paused);

    /**
     * @notice Pause or unpause transfers.
     * @param _paused True to pause, false to unpause.
     * @dev Only callable by the contract owner.
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit Paused(_paused);
    }

    /**
     * @notice Add/remove an address from the blacklist.
     * @param account The address to update.
     * @param blacklisted_ True to blacklist, false to unblacklist.
     * @dev Only callable by the contract owner.
     */
    function setBlacklist(address account, bool blacklisted_) external onlyOwner {
        blacklist[account] = blacklisted_;
        emit BlacklistUpdated(account, blacklisted_);
    }

    /**
     * @notice Check whether a transfer is allowed by compliance rules.
     * @param from Sender address.
     * @param to Recipient address.
     * @return True if allowed, otherwise false.
     * @dev This basic module blocks transfers when paused or when either address is blacklisted.
     */
    function canTransfer(
        address from,
        address to,
        uint256
    ) external view override returns (bool) {
        if (paused) return false;
        if (blacklist[from] || blacklist[to]) return false;
        return true;
    }

    /// @notice Post-transfer hook (no-op in this basic module).
    function transferred(address, address, uint256) external pure override {}

    /// @notice Post-mint hook (no-op in this basic module).
    function created(address, uint256) external pure override {}
    
    /// @notice Post-burn hook (no-op in this basic module).
    function destroyed(address, uint256) external pure override {}
}
