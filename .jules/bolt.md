## 2024-05-13 - Inline Earned Calculation in updateReward
**Learning:** Synthetix-style staking contracts (`PurDexStakingRewards.sol`) often recalculate `rewardPerToken()` within the `updateReward` modifier's `earned()` call, even after caching it in `rewardPerTokenStored`. This results in redundant external/public calls and higher gas costs.
**Action:** When working with staking reward contracts, always inline the `earned` calculation inside the `updateReward` modifier to leverage the newly cached `rewardPerTokenStored` value, saving gas on state reads/logic execution.
