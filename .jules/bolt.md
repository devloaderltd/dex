## 2024-11-20 - Avoid redundant view function recalculations in modifiers
**Learning:** In StakingRewards contracts, calling `earned()` within the `updateReward` modifier redundantly recalculates `rewardPerToken()`, which performs extra SLOADs and arithmetic. The `rewardPerTokenStored` is already cached in the line prior within the same modifier.
**Action:** Replace the `earned()` call inside `updateReward` with an inline calculation using the already cached `rewardPerTokenStored` variable to save gas.
