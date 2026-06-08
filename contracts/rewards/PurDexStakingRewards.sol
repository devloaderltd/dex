// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../IIdentityRegistry.sol";
import "../interfaces/IPuriCoin.sol";
import "../dex/libraries/TransferHelper.sol";

/// @title PurDexStakingRewards
/// @notice Stake an LP token (or any ERC20) and earn PUR rewards.
/// @dev
///  - Rewards can be pre-funded OR minted (if this contract is set as an agent on PuriCoin).
///  - Because PUR transfers are KYC-gated, this contract requires `IdentityRegistry.isVerified(user)`.
contract PurDexStakingRewards is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using TransferHelper for address;

    error SR__KycRequired();
    error SR__ZeroAmount();

    IERC20 public stakingToken;
    IPuriCoin public rewardsToken;
    IIdentityRegistry public identityRegistry;

    uint256 public duration;
    uint256 public periodFinish;
    uint256 public rewardRate; // rewards per second
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event DurationUpdated(uint256 newDuration);

    /// @dev Prevent the implementation contract from being initialized directly.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _stakingToken,
        address _rewardsToken,
        address _identityRegistry,
        uint256 _duration
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        require(_stakingToken != address(0) && _rewardsToken != address(0) && _identityRegistry != address(0), "ZERO");
        stakingToken = IERC20(_stakingToken);
        rewardsToken = IPuriCoin(_rewardsToken);
        identityRegistry = IIdentityRegistry(_identityRegistry);
        duration = _duration;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function _requireVerified(address who) internal view {
        if (!identityRegistry.isVerified(who)) revert SR__KycRequired();
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored +
            (((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / _totalSupply);
    }

    function earned(address account) public view returns (uint256) {
        return ((_balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) + rewards[account];
    }

    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        _requireVerified(msg.sender);
        if (amount == 0) revert SR__ZeroAmount();

        _totalSupply += amount;
        _balances[msg.sender] += amount;
        address(stakingToken).safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        _withdraw(amount);
    }

    function _withdraw(uint256 amount) internal {
        _requireVerified(msg.sender);
        if (amount == 0) revert SR__ZeroAmount();
        _totalSupply -= amount;
        _balances[msg.sender] -= amount;
        address(stakingToken).safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        _getReward();
    }

    function _getReward() internal {
        _requireVerified(msg.sender);
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            address(rewardsToken).safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external nonReentrant updateReward(msg.sender) {
        _withdraw(_balances[msg.sender]);
        _getReward();
    }

    /// @notice Start a new reward period. Can be funded by minting or by pre-funding this contract.
    /// @dev If you set this contract as an agent on PuriCoin, it can mint rewards into itself.
    function notifyRewardAmount(uint256 reward) external onlyOwner updateReward(address(0)) {
        if (reward == 0) revert SR__ZeroAmount();

        // Mint rewards to this contract if possible (requires agent role on PuriCoin).
        // If you don't want minting, comment this line out and instead transfer PUR to this contract first.
        try rewardsToken.mint(address(this), reward) {} catch {
            // ignore; assumes contract already has the reward balance
        }

        if (block.timestamp >= periodFinish) {
            rewardRate = reward / duration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / duration;
        }

        // Do not promise more rewards than the contract can pay.
        uint256 balance = IERC20(address(rewardsToken)).balanceOf(address(this));
        require(rewardRate <= balance / duration, "REWARD_TOO_HIGH");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + duration;
        emit RewardAdded(reward);
    }

    function setDuration(uint256 _duration) external onlyOwner {
        require(block.timestamp > periodFinish, "ONGOING_PERIOD");
        duration = _duration;
        emit DurationUpdated(_duration);
    }
}
