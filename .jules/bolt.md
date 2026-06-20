## 2024-05-18 - Optimize Staking Rewards Modifiers & Calculations
**Learning:** Composite external functions calling other external functions trigger redundant modifiers (e.g., `nonReentrant` and `updateReward`), burning gas. `updateReward` also recalculated `rewardPerToken()` via `earned()` unnecessarily.
**Action:** Extract logic into internal functions (`_withdraw`, `_getReward`) for composite functions to use. Use inline calculation with cached state variables to save gas in modifiers.
