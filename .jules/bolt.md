## 2026-03-26 - Cached Pair Lookups in Router
**Learning:** In PurDex architecture, AMM pair addresses cannot be computed locally via CREATE2 hash because they are deployed as `BeaconProxy` instances. Resolving pair addresses requires an external call to `IPurDexFactory.getPair()`, which is expensive and was redundantly called in `PurDexRouter._swap()` loop.
**Action:** Always cache pair lookups or pass them along in multi-hop loops to avoid redundant gas costs from external calls to the factory.
