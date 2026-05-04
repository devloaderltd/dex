## 2024-05-04 - Optimize Router multi-hop pair caching
**Learning:** In PurDex, pair addresses cannot be computed locally via CREATE2 due to BeaconProxy architecture. Calling getPair() redundantly in swaps is expensive.
**Action:** Use a sliding-window caching pattern in multi-hop loops where the `to` address calculated in iteration i becomes `currentPair` for iteration i+1.
