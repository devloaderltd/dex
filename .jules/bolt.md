
## 2026-04-17 - Optimize internal function calls with heavy access modifiers
**Learning:** In Solidity, calling `public` functions from within the contract (like `exit()` calling `withdraw()` and `getReward()`) is less efficient than using `internal` functions. If the public functions have heavy access modifiers like `nonReentrant` or `updateReward(msg.sender)`, those modifiers get evaluated multiple times if called individually and then together in a wrapper function, which wastes gas.
**Action:** Refactor `public` functions that are called internally into an `internal` base version and an `external` wrapper. Apply heavy modifiers only to the `external` wrappers to avoid duplicate modifier execution.
