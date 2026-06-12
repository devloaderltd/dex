## 2026-06-12 - Sliding Window Cache for Pair Lookups
**Learning:** Redundant external calls in loops can be avoided by passing the previously computed value into the next iteration.
**Action:** Added currentPair argument to _swap to cache the pair address.
