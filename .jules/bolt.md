## 2024-05-17 - Redundant Calculation in updateReward Modifier
**Learning:** In the `updateReward` modifier of StakingRewards contracts, calling `earned(account)` redundantly invokes `rewardPerToken()` which performs multiple unnecessary SLOADs, even though `rewardPerTokenStored` was just cached in the same modifier.
**Action:** Replace the `earned(account)` call inside the `updateReward` modifier with an inline calculation using the already cached `rewardPerTokenStored` to significantly save gas on SLOADs.
