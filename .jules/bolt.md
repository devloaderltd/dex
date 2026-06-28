## 2026-06-28 - Optimize multi-hop swaps with sliding-window caching
**Learning:** The `_swap` function in `PurDexRouter.sol` made redundant external calls to `IPurDexFactory(factory).getPair()` inside its loop. Since the `to` address for iteration `i` is often the pair address for iteration `i+1`, we can cache this value and pass it to the next iteration to save gas.
**Action:** Add a `currentPair` parameter to `_swap` and update it at the end of each iteration to eliminate the redundant external calls.
