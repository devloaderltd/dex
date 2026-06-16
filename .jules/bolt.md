## 2024-06-16 - Gas Optimization in Staking Rewards
**Learning:** In StakingRewards contracts, the `updateReward` modifier calls `earned()` which redundantly recalculates `rewardPerToken()`, even though it was just calculated and stored. Also, composite functions like `exit()` redundantly trigger modifiers when calling external functions.
**Action:** Inline `earned()` using the cached `rewardPerTokenStored`, and refactor to internal helpers to prevent double modifier execution in composite functions.
