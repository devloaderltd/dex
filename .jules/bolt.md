## 2024-06-23 - Redundant calculations in StakingRewards
**Learning:** The `updateReward` modifier recalculated `rewardPerToken` implicitly via `earned()`, and composite functions like `exit()` executed `nonReentrant` and `updateReward` twice by calling public functions.
**Action:** Always inline calculations inside modifiers using cached state variables, and extract internal helpers for public functions to avoid double-modifier execution.
