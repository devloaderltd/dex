// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PuriCoin
 * @notice ERC20 token.
 * @dev
 *  - Provides an agent role for operational controls: mint/burn/freeze/forceTransfer.
 */


contract PuriCoin is ERC20, Ownable {

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
     * @param decimals_ Token decimals (must be <= 18).
     */
    constructor(
        uint8 decimals_
    ) ERC20("Puri Coin", "PUR") {
        require(decimals_ <= 18, "Decimals > 18");

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
     * @notice Mint tokens to a wallet.
     * @param to Recipient wallet.
     * @param amount Amount to mint (smallest units).
     * @dev Callable by agent/owner.
     */
    function mint(address to, uint256 amount) external onlyAgent {
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens from an address (admin action).
     * @param from Address to burn from.
     * @param amount Amount to burn.
     * @dev Callable by agent/owner.
     */
    function burnFrom(address from, uint256 amount) external onlyAgent {
        _burn(from, amount);
    }

    /**
     * @notice Force transfer tokens between wallets (admin action).
     * @param from Sender wallet.
     * @param to Recipient wallet.
     * @param amount Amount to transfer.
     * @dev Callable by agent/owner.
     */
    function forceTransfer(
        address from,
        address to,
        uint256 amount
    ) external onlyAgent {
        _transfer(from, to, amount);
    }

    /**
     * @dev ERC20 hook executed before transfers/mints/burns.
     * Enforces:
     *  - Frozen address checks
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
    }
}
