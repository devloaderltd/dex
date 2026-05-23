## 2026-05-23 - Optimize PurDexStakingRewards
**Learning:** Redundant `updateReward` and `nonReentrant` modifier executions occur when composite functions like `exit()` call other public functions (`withdraw`, `getReward`). Also, recalculating `rewardPerToken()` inside `earned()` when called from the `updateReward` modifier wastes gas.
**Action:** Use internal helper functions for repeated logic to avoid double-modifier execution. Inline calculations inside modifiers when values like `rewardPerTokenStored` are already updated and cached.
