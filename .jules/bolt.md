## 2026-05-14 - Optimize Standard StakingRewards modifier
**Learning:** In standard Synthetix-style StakingRewards contracts, the `updateReward` modifier redundantly recalculates `rewardPerToken()` internally inside the `earned()` call after already calculating it once. Since state variables are written, avoiding this redundant call saves gas and SLODs.
**Action:** Always inline the `earned()` logic using `rewardPerTokenStored` inside the `updateReward` modifier rather than calling `earned(account)`.
