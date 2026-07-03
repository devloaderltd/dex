## 2024-05-24 - Sliding-window caching pattern for multi-hop swaps
**Learning:** In PurDexRouter._swap, calculating the next pair address (to) inherently yields the current pair address for the subsequent loop iteration. Fetching it again via IPurDexFactory.getPair is a redundant external call.
**Action:** Use a sliding-window caching pattern where `nextPair` becomes `currentPair` to eliminate redundant external factory calls.
