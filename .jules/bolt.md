## 2024-05-18 - Avoid redundant pair address resolution
**Learning:** In PurDex, pair addresses are `BeaconProxy` instances and cannot be computed locally via CREATE2 hashes. Resolving a pair address requires an external call to the Factory contract.
**Action:** Cache pair addresses in local variables and re-use them during multi-hop loops (e.g. in Router's `_swap` function) to avoid redundant external calls and save gas.
