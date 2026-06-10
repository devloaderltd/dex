## 2024-06-10 - StakingRewards redundant reward calculation
**Learning:** Calling `earned()` inside the `updateReward()` modifier causes a redundant execution of `rewardPerToken()`. Since `rewardPerTokenStored` is updated immediately prior, the recalculation is unnecessary and wastes gas by reading multiple state variables again (`_totalSupply`, `lastUpdateTime`, `periodFinish`).
**Action:** Always use the already cached `rewardPerTokenStored` to calculate the current earned amount inline inside the modifier instead of delegating to the `earned()` function.
