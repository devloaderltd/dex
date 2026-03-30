
## 2024-03-30 - Refactoring double modifier execution
**Learning:** In smart contracts, public/external functions with heavy modifiers (like `nonReentrant` and `updateReward`) that call each other (e.g. `exit` calling `withdraw` and `getReward`) end up executing the modifiers twice per transaction. This leads to redundant SLOADs and SSTOREs, unnecessarily increasing gas consumption.
**Action:** Refactor the public/external functions to use internal un-modified versions (e.g. `_withdraw` and `_getReward`), and apply the modifiers once directly on the wrapper functions and composite functions (e.g. `exit`).
