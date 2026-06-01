## 2026-06-01 - Prevent Redundant rewardPerToken Recalculation in StakingRewards
**Learning:** In StakingRewards contracts, calling `earned()` inside the `updateReward` modifier redundantly recalculates `rewardPerToken()` after it was just cached in `rewardPerTokenStored`. This wastes gas via duplicate math operations and state reads.
**Action:** Always replace the `earned()` call in `updateReward` with an inline calculation using the newly cached `rewardPerTokenStored` variable.
