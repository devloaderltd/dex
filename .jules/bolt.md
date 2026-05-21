## 2024-05-21 - Optimization of StakingRewards earned() calculation
**Learning:** Found an opportunity to cache rewardPerToken() calculation locally in the earned() function by leveraging the already stored value when the reward is updated.
**Action:** Used cached values for calculation and refactoring the updateReward modifier to reuse cached state.
