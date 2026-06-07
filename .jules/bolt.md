## 2024-05-15 - [Initial Journal]
**Learning:** Initialized Bolt journal.
**Action:** Ready to track performance optimizations.

## 2024-06-07 - [StakingRewards Modifier and Composite Function Redundancies]
**Learning:** Found two common redundant patterns in StakingRewards: 1. Modifiers recalculating state that was just cached (e.g., `updateReward` caching `rewardPerTokenStored` but calling `earned()` which recalculates `rewardPerToken()`). 2. Composite functions like `exit()` calling public functions `withdraw()` and `getReward()`, leading to redundant executions of modifiers like `nonReentrant` and `updateReward`.
**Action:** When working on StakingRewards or similar contracts, aggressively inline state calculations when caching has already occurred inside modifiers, and separate public-facing logic from internal logic using `_withdraw()` and `_getReward()` to allow composite functions to bypass duplicate modifier checks.
