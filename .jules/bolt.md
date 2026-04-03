## 2026-04-03 - Optimize StakingRewards exit() function
**Learning:** In Synthetix-based staking rewards contracts, calling `withdraw()` and `getReward()` sequentially within `exit()` causes redundant gas costs. The `updateReward` modifier performs multiple expensive SLOAD and SSTORE operations, and `nonReentrant` changes storage state twice.
**Action:** Extract logic into internal functions (`_withdraw` and `_getReward`), and apply the modifiers only once at the external entry point (`exit()`). This prevents double-execution of modifiers and significantly reduces gas.
