## 2026-07-07 - Inline earned calculation in updateReward
**Learning:** In StakingRewards contracts, calling `earned()` inside the `updateReward` modifier redundantly recalculates `rewardPerToken()`, which was already cached in the previous line.
**Action:** Use the cached `rewardPerTokenStored` value to inline the calculation and avoid redundant execution.
