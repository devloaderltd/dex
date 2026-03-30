// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "../IIdentityRegistry.sol";

/// @title PurDexKYCManager
/// @notice "Auto" KYC verification gateway for your ERC3643-style IdentityRegistry.
/// @dev
///  - You run KYC off-chain and sign an EIP-712 approval for the user.
///  - The user submits that signature on-chain.
///  - This contract (as a KYCAgent in IdentityRegistry) registers the user as verified.
///
/// Why this helps for a DEX:
///  - Your PUR token blocks transfers unless both sender & recipient are verified.
///  - AMM pair contracts and pool contracts must also be verified addresses.
///  - This manager can auto-register DEX contracts (pairs/pools) as verified.
contract PurDexKYCManager is Initializable, OwnableUpgradeable, UUPSUpgradeable, EIP712Upgradeable {
    using ECDSA for bytes32;

    error KYC__InvalidSigner();
    error KYC__Expired();
    error KYC__ZeroAddress();
    error KYC__NotAuthorized();
    error KYC__RegistrationFailed();

    IIdentityRegistry public identityRegistry;

    /// @notice Off-chain signer that attests KYC completion.
    address public kycSigner;

    /// @notice DEX factory allowed to register new pair contracts.
    address public factory;

    mapping(address => uint256) public nonces;

    /// @dev keccak256("KYCApproval(address user,uint16 country,uint256 deadline,uint256 nonce)")
    bytes32 public constant KYC_TYPEHASH =
        keccak256("KYCApproval(address user,uint16 country,uint256 deadline,uint256 nonce)");

    event KYCSignerUpdated(address indexed signer);
    event FactoryUpdated(address indexed factory);
    event InvestorVerified(address indexed user, uint16 country);
    event DexContractRegistered(address indexed contractAddr);

    /// @dev Prevent the implementation contract from being initialized directly.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _identityRegistry, address _kycSigner) external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __EIP712_init("PurDexKYCManager", "1");

        if (_identityRegistry == address(0)) revert KYC__ZeroAddress();
        if (_kycSigner == address(0)) revert KYC__ZeroAddress();
        identityRegistry = IIdentityRegistry(_identityRegistry);
        kycSigner = _kycSigner;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function setKycSigner(address _kycSigner) external onlyOwner {
        if (_kycSigner == address(0)) revert KYC__ZeroAddress();
        kycSigner = _kycSigner;
        emit KYCSignerUpdated(_kycSigner);
    }

    function setFactory(address _factory) external onlyOwner {
        factory = _factory;
        emit FactoryUpdated(_factory);
    }

    /// @notice Verify yourself using a backend-provided signature.
    function verifySelfWithSig(uint16 country, uint256 deadline, bytes calldata signature) external {
        verifyWithSig(msg.sender, country, deadline, signature);
    }

    /// @notice Verify any user using a backend-provided signature.
    /// @dev Anyone can submit the signature (meta-tx friendly), but the signature must be valid for `user`.
    function verifyWithSig(address user, uint16 country, uint256 deadline, bytes calldata signature) public {
        if (block.timestamp > deadline) revert KYC__Expired();
        if (user == address(0)) revert KYC__ZeroAddress();

        uint256 nonce = nonces[user]++;
        bytes32 structHash = keccak256(abi.encode(KYC_TYPEHASH, user, country, deadline, nonce));
        bytes32 digest = _hashTypedDataV4(structHash);
        address recovered = digest.recover(signature);
        if (recovered != kycSigner) revert KYC__InvalidSigner();

        // This call will only succeed if this contract is set as KYCAgent in IdentityRegistry.
        // IdentityRegistry in your repo uses `registerInvestor(address,uint16)`.
        // We use a low-level call to remain compatible even if you upgrade the registry later.
        (bool ok, ) = address(identityRegistry).call(
            abi.encodeWithSignature("registerInvestor(address,uint16)", user, country)
        );
        if (!ok) revert KYC__RegistrationFailed();

        emit InvestorVerified(user, country);
    }

    /// @notice Register a DEX contract (AMM pair, staking pool, lending pool) as a verified address.
    /// @dev Called by the Factory (for pairs) or by the owner (for other pools).
    function registerDexContract(address contractAddr) external {
        if (contractAddr == address(0)) revert KYC__ZeroAddress();
        if (msg.sender != owner() && msg.sender != factory) revert KYC__NotAuthorized();

        (bool ok, ) = address(identityRegistry).call(
            abi.encodeWithSignature("registerInvestor(address,uint16)", contractAddr, uint16(0))
        );
        if (!ok) revert KYC__RegistrationFailed();

        emit DexContractRegistered(contractAddr);
    }
}
