## 2024-05-18 - [Optimized _swap in PurDexRouter]
**Learning:** In PurDex architecture, AMM pair addresses cannot be computed locally via CREATE2 hash because they are deployed as 'BeaconProxy' instances. Resolving pair addresses requires an external call to 'IPurDexFactory.getPair()', which is expensive in multi-hop loops.
**Action:** Use a sliding-window caching pattern in `_swap` where the `nextPair` address calculated in iteration `i` becomes the `currentPair` for the subsequent iteration `i+1`, eliminating redundant external calls to `getPair()` during multi-hop swaps.
