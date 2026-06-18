## 2026-06-18 - Redundant Calculations and Modifiers in StakingRewards
**Learning:** The updateReward modifier was redundantly calling earned() which recalculated rewardPerToken(), and exit() was redundantly running nonReentrant and updateReward modifiers twice by calling external functions.
**Action:** Inline the earned() logic within updateReward using the already cached rewardPerTokenStored. Refactor external functions called by composite functions into internal helpers to avoid redundant modifier checks.
