
## 2024-05-15 - Refactored PurDexStakingRewards.sol to remove redundant executions
**Learning:** Found that `exit()` invoked both `withdraw()` and `getReward()`, which were `public nonReentrant updateReward(msg.sender)`. This resulted in the `nonReentrant` and `updateReward` modifiers executing twice, and the KYC gate `_requireVerified(msg.sender)` being checked multiple times, causing wasted gas.
**Action:** Always create internal helper methods for actions that might be combined externally. Apply modifiers at the topmost external boundary and ensure helpers bypass those redundant checks.
