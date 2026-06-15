## 2024-06-15 - StakingRewards Modifier Optimization
**Learning:** In StakingRewards contracts, calling `earned()` inside the `updateReward` modifier redundantly recalculates `rewardPerToken()`, which wastes gas. The modifier already caches `rewardPerToken()` as `rewardPerTokenStored`.
**Action:** Replace the `earned()` call inside `updateReward` with an inline calculation using the already cached `rewardPerTokenStored` to save gas on every stake, withdraw, and getReward call.
