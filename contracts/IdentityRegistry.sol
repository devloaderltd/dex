// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IIdentityRegistry.sol";

/**
 * @title IdentityRegistry
 * @notice Simple identity/KYC registry for permissioned token flows.
 * @dev
 *  - Stores (verified, country) per wallet.
 *  - Owner can approve KYC agents who can manage investor records.
 */


contract IdentityRegistry is IIdentityRegistry, Ownable {

    /// @notice Investor identity record stored per wallet.
    struct Investor {

        /// @notice True if KYC verification is approved.
        bool verified;

        /// @notice Numeric country code associated with the wallet.
        uint16 country;
    }

    /// @dev Investor storage (private).
    mapping(address => Investor) private _investors;

    /// @notice Addresses allowed to manage investor KYC records.
    mapping(address => bool) public kycAgents;

    /// @notice Emitted when a wallet is first registered.
    event InvestorRegistered(address indexed wallet, uint16 country);

    /// @notice Emitted when a wallet's verification/country is updated.
    event InvestorUpdated(address indexed wallet, bool verified, uint16 country);

    /// @notice Emitted when a wallet record is removed.
    event InvestorRemoved(address indexed wallet);
    
    /// @notice Emitted when a KYC agent is enabled/disabled.
    event KYCAgentSet(address indexed agent, bool allowed);

    /**
     * @dev Allows only a KYC agent or the owner to call.
     */
    modifier onlyKycAgent() {
        require(kycAgents[msg.sender] || msg.sender == owner(), "Not KYC agent");
        _;
    }

    /**
     * @notice Enable/disable a KYC agent.
     * @param agent Address to update.
     * @param allowed True to allow, false to revoke.
     * @dev Only callable by the owner.
     */
    function setKYCAgent(address agent, bool allowed) external onlyOwner {
        kycAgents[agent] = allowed;
        emit KYCAgentSet(agent, allowed);
    }

    /**
     * @notice Register an investor wallet and set it as verified.
     * @param wallet Investor wallet address.
     * @param country Numeric country code.
     * @dev Only callable by a KYC agent or the owner.
     */
    function registerInvestor(address wallet, uint16 country) external onlyKycAgent {
        require(wallet != address(0), "Zero addr");
        _investors[wallet] = Investor({verified: true, country: country});
        emit InvestorRegistered(wallet, country);
    }

    /**
     * @notice Update an investor wallet record.
     * @param wallet Investor wallet address.
     * @param verified New verification status.
     * @param country New numeric country code.
     * @dev Only callable by a KYC agent or the owner.
     */
    function updateInvestor(
        address wallet,
        bool verified,
        uint16 country
    ) external onlyKycAgent {
        require(wallet != address(0), "Zero addr");
        Investor storage inv = _investors[wallet];
        inv.verified = verified;
        inv.country = country;
        emit InvestorUpdated(wallet, verified, country);
    }

    /**
     * @notice Remove an investor wallet record.
     * @param wallet Investor wallet address.
     * @dev Only callable by a KYC agent or the owner.
     */
    function removeInvestor(address wallet) external onlyKycAgent {
        delete _investors[wallet];
        emit InvestorRemoved(wallet);
    }

    // Interface function name stays `isVerified`
    /**
     * @notice Returns true if the investor wallet is verified.
     * @param investor Wallet address to query.
     */
    function isVerified(address investor) external view override returns (bool) {
        return _investors[investor].verified;
    }

    /**
     * @notice Returns the stored country code for an investor wallet.
     * @param investor Wallet address to query.
     */
    function investorCountry(address investor) external view override returns (uint16) {
        return _investors[investor].country;
    }
}
