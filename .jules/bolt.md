## 2025-06-08 - Redundant modifiers on external calls

**Learning:** When an external function (e.g. `exit`) calls other external-facing functions (`withdraw`, `getReward`), it triggers `nonReentrant` and `updateReward(msg.sender)` multiple times, unnecessarily increasing gas costs due to extra SLOADs, SSTOREs and computations.
**Action:** Refactor the external-facing functions to call internal helpers (`_withdraw`, `_getReward`) and have the composite function (`exit`) call those internal helpers directly. This way, the modifier `updateReward` and `nonReentrant` are only applied once when `exit` is called, rather than multiple times.
