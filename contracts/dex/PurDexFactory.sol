// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import "./PurDexPair.sol";

/// @notice Factory that creates PurDexPair contracts.
/// @dev
///  - This factory is deployed behind a UUPS proxy.
///  - Pairs are deployed behind an OZ BeaconProxy, so you can upgrade all pairs later by upgrading the beacon.
///  - Optionally integrates with a KYC manager to auto-register newly created pairs.
contract PurDexFactory is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    error PurDexFactory__IdenticalAddresses();
    error PurDexFactory__ZeroAddress();
    error PurDexFactory__PairExists();

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);
    event KycManagerUpdated(address indexed kycManager);
    event PairBeaconUpdated(address indexed pairBeacon);
    event FeeToUpdated(address indexed feeTo);

    address public feeTo;
    address public feeToSetter;

    // Optional hook: called after creating a pair so the pair can be KYC-verified in your IdentityRegistry.
    address public kycManager;

    // Beacon used for all pairs.
    address public pairBeacon;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    /// @dev Prevent the implementation contract from being initialized directly.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev UUPS initializer
    function initialize(address _feeToSetter, address _kycManager, address _pairBeacon) external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();

        if (_feeToSetter == address(0)) revert PurDexFactory__ZeroAddress();
        feeToSetter = _feeToSetter;
        kycManager = _kycManager;
        pairBeacon = _pairBeacon;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, "FORBIDDEN");
        feeTo = _feeTo;
        emit FeeToUpdated(_feeTo);
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, "FORBIDDEN");
        feeToSetter = _feeToSetter;
    }

    function setKycManager(address _kycManager) external {
        require(msg.sender == feeToSetter, "FORBIDDEN");
        kycManager = _kycManager;
        emit KycManagerUpdated(_kycManager);
    }

    function setPairBeacon(address _pairBeacon) external {
        require(msg.sender == feeToSetter, "FORBIDDEN");
        pairBeacon = _pairBeacon;
        emit PairBeaconUpdated(_pairBeacon);
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        if (tokenA == tokenB) revert PurDexFactory__IdenticalAddresses();
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert PurDexFactory__ZeroAddress();
        if (getPair[token0][token1] != address(0)) revert PurDexFactory__PairExists();
        if (pairBeacon == address(0)) revert PurDexFactory__ZeroAddress();

        // Beacon proxy init: initialize(factory, token0, token1)
        bytes memory initData = abi.encodeWithSelector(PurDexPair.initialize.selector, address(this), token0, token1);
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        pair = address(new BeaconProxy{salt: salt}(pairBeacon, initData));

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);

        // Auto-register pair in IdentityRegistry via your KYC manager (optional)
        if (kycManager != address(0)) {
            // best-effort; if the manager reverts, pair still exists but must be registered manually.
            (bool ok, ) = kycManager.call(abi.encodeWithSignature("registerDexContract(address)", pair));
            ok; // ignore
        }
    }
}
