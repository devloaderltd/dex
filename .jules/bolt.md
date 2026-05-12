## 2024-05-12 - Prevent redundant reward calculations
**Learning:** In StakingRewards contracts, the `updateReward` modifier often calls `earned(account)`, which in turn recalculates `rewardPerToken()` even though `rewardPerTokenStored` was just updated on the previous line. This results in redundant calculation and extra gas overhead.
**Action:** Inline the calculation within the `updateReward` modifier utilizing the already cached `rewardPerTokenStored` value instead of calling `earned(account)`.
