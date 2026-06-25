## 2026-06-25 - Redundant calculation in updateReward modifier
**Learning:** In StakingRewards contracts, calling `earned()` inside the `updateReward` modifier redundantly recalculates `rewardPerToken()` even though it was just calculated and cached in `rewardPerTokenStored`.
**Action:** Replace the `earned()` call with an inline calculation using the cached `rewardPerTokenStored` to save gas.
