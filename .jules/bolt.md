## 2026-06-17 - Inline earned calculation to avoid recalculating rewardPerToken
**Learning:** In StakingRewards contracts, calling `earned()` inside `updateReward` recalculates `rewardPerToken()` unnecessarily when the cached `rewardPerTokenStored` is already available in the local scope.
**Action:** Replace the `earned()` call with an inline calculation using the cached `rewardPerTokenStored` to save gas.
