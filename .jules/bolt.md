## 2024-04-25 - Consolidate Modifiers for Gas Optimization
**Learning:** In Solidity, running access modifiers like `nonReentrant` and `updateReward` on internal functions that are then called by an external function (which also uses them or could use them) results in redundant SLOAD/SSTORE operations and external calls, wasting gas.
**Action:** Extract core logic into `internal` functions devoid of access modifiers. Apply the modifiers once on the `external` entry points (e.g., `exit()`), preventing duplicated state access while retaining full security and functionality.
