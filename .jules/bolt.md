## 2024-04-04 - Consolidating Access Modifiers on External Wrappers
**Learning:** In the PurDexStakingRewards contract, `exit()` called `withdraw()` and `getReward()`, both of which had `nonReentrant` and `updateReward` modifiers. This caused redundant and expensive modifier executions.
**Action:** Extract core logic into `internal` functions (e.g., `_withdraw`, `_getReward`), keep the modifiers on the `external` entry points, and have composite functions like `exit()` apply the modifiers once and call the internal logic. This saves significant gas.
