// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IIdentityRegistry.sol";
import "./ICompliance.sol";

/**
 * @title PuriCoin
 * @notice Permissioned ERC20 token with KYC gating and pluggable compliance.
 * @dev
 *  - Uses IdentityRegistry to enforce KYC on transfers and minting.
 *  - Uses a Compliance module to allow additional rules (pause/blacklist/etc.).
 *  - Provides an agent role for operational controls: mint/burn/freeze/forceTransfer.
 */


contract PuriCoin is ERC20, Ownable {

    /// @notice KYC/identity registry used to verify investor wallets.
    IIdentityRegistry public identityRegistry;

    /// @notice Compliance module used to approve transfers and receive lifecycle hooks.
    ICompliance public compliance;

    /// @dev Custom decimals configured at deployment (immutable).
    uint8 private immutable _customDecimals;

    /// @notice Operational agents allowed to perform privileged actions.
    mapping(address => bool) public isAgent;

    /// @notice Frozen addresses cannot send or receive tokens.
    mapping(address => bool) public frozen;

    /// @notice Emitted when an agent permission is changed.
    event AgentUpdated(address indexed agent, bool allowed);
    
    /// @notice Emitted when an address is frozen/unfrozen.
    event AddressFrozen(address indexed account, bool frozen);

    /**
     * @dev Allows only an agent or the owner to call.
     */
    modifier onlyAgent() {
        require(isAgent[msg.sender] || msg.sender == owner(), "Not agent");
        _;
    }

    /**
     * @param identityRegistry_ Address of the identity registry contract.
     * @param compliance_ Address of the compliance contract.
     * @param decimals_ Token decimals (must be <= 18).
     */
    constructor(
        address identityRegistry_,
        address compliance_,
        uint8 decimals_
    ) ERC20("Puri Coin", "PUR") {
        require(identityRegistry_ != address(0), "ID registry zero");
        require(compliance_ != address(0), "Compliance zero");
        require(decimals_ <= 18, "Decimals > 18");

        identityRegistry = IIdentityRegistry(identityRegistry_);
        compliance = ICompliance(compliance_);
        _customDecimals = decimals_;

        isAgent[msg.sender] = true;
    }

    /**
     * @notice Returns the token decimals configured at deployment.
     */
    function decimals() public view override returns (uint8) {
        return _customDecimals;
    }

    /**
     * @notice Add or remove an operational agent.
     * @param agent Address to update.
     * @param allowed True to grant agent role, false to revoke.
     * @dev Only owner can call.
     */
    function setAgent(address agent, bool allowed) external onlyOwner {
        isAgent[agent] = allowed;
        emit AgentUpdated(agent, allowed);
    }

    /**
     * @notice Freeze or unfreeze an address (blocks sending/receiving).
     * @param account Address to update.
     * @param _frozen True to freeze, false to unfreeze.
     * @dev Callable by agent/owner.
     */
    function freezeAddress(address account, bool _frozen) external onlyAgent {
        frozen[account] = _frozen;
        emit AddressFrozen(account, _frozen);
    }

    /**
     * @notice Update the identity registry contract address.
     * @param newRegistry New registry address.
     * @dev Only owner can call.
     */
    function setIdentityRegistry(address newRegistry) external onlyOwner {
        require(newRegistry != address(0), "Zero addr");
        identityRegistry = IIdentityRegistry(newRegistry);
    }

    /**
     * @notice Update the compliance contract address.
     * @param newCompliance New compliance address.
     * @dev Only owner can call.
     */
    function setCompliance(address newCompliance) external onlyOwner {
        require(newCompliance != address(0), "Zero addr");
        compliance = ICompliance(newCompliance);
    }

    /**
     * @notice Mint tokens to a verified wallet.
     * @param to Recipient wallet (must be verified).
     * @param amount Amount to mint (smallest units).
     * @dev Callable by agent/owner; calls compliance.created hook.
     */
    function mint(address to, uint256 amount) external onlyAgent {
        require(identityRegistry.isVerified(to), "KYC required");
        _mint(to, amount);
        compliance.created(to, amount);
    }

    /**
     * @notice Burn tokens from an address (admin action).
     * @param from Address to burn from.
     * @param amount Amount to burn.
     * @dev Callable by agent/owner; calls compliance.destroyed hook.
     */
    function burnFrom(address from, uint256 amount) external onlyAgent {
        _burn(from, amount);
        compliance.destroyed(from, amount);
    }

    /**
     * @notice Force transfer tokens between wallets (admin action).
     * @param from Sender wallet.
     * @param to Recipient wallet (must be verified).
     * @param amount Amount to transfer.
     * @dev Callable by agent/owner; calls compliance.transferred hook.
     */
    function forceTransfer(
        address from,
        address to,
        uint256 amount
    ) external onlyAgent {
        require(identityRegistry.isVerified(to), "KYC required (to)");
        _transfer(from, to, amount);
        compliance.transferred(from, to, amount);
    }

    /**
     * @dev ERC20 hook executed before transfers/mints/burns.
     * Enforces:
     *  - Frozen address checks
     *  - KYC verification on standard transfers
     *  - Compliance module approval on standard transfers
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._beforeTokenTransfer(from, to, amount);

        if (from != address(0)) {
            require(!frozen[from], "Sender frozen");
        }
        if (to != address(0)) {
            require(!frozen[to], "Recipient frozen");
        }

        if (from != address(0) && to != address(0)) {
            require(identityRegistry.isVerified(from), "KYC from");
            require(identityRegistry.isVerified(to), "KYC to");
            require(compliance.canTransfer(from, to, amount), "Compliance blocked");
        }
    }
}
