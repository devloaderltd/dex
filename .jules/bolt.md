## 2024-06-27 - Inline earned calculation in StakingRewards
**Learning:** The `earned()` function redundantly recalculates `rewardPerToken()` when called inside the `updateReward` modifier. Since `rewardPerTokenStored` is already up-to-date and cached in the modifier, inlining the calculation saves gas by avoiding the function call and redundant math.
**Action:** Always use the cached `rewardPerTokenStored` value to inline the reward calculation inside modifiers rather than delegating to an external/public view function.
