## 2026-07-08 - StakingRewards redundant reward calculation
**Learning:** The updateReward modifier redundantly calls earned() which recalculates rewardPerToken() even though it was just cached as rewardPerTokenStored. This is a common StakingRewards anti-pattern that burns unnecessary gas through redundant calculations and state reads.
**Action:** Always inline the earned calculation using the cached rewardPerTokenStored inside the updateReward modifier to avoid the redundant call.
