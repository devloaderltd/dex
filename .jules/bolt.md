
## 2026-05-27 - Optimize StakingRewards gas usage
**Learning:** Found redundant gas usage patterns in StakingRewards. Specifically, calling `earned(account)` inside `updateReward` redundantly recalculates `rewardPerToken()` even though it's already cached in `rewardPerTokenStored` the line before. Also, composite functions like `exit()` calling `withdraw()` and `getReward()` execute the `nonReentrant` and `updateReward` modifiers three times total instead of once.
**Action:** Inline `earned` calculation in `updateReward` using `rewardPerTokenStored`. Refactor `public` functions into internal helpers and `external` wrappers, then have composite functions call the internal helpers directly to apply modifiers only once.
