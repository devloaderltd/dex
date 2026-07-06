## 2024-05-24 - Eliminate redundant factory calls in router swaps
**Learning:** Multi-hop swaps redundantly fetch the pair address using `IPurDexFactory.getPair()` inside `_swap` which costs unnecessary gas and time.
**Action:** Pass the first `pair` explicitly into `_swap` and use a sliding window caching pattern to reuse the calculated `to` variable as the next `currentPair`.
