## 2026-05-28 - Optimize _swap with sliding-window caching
**Learning:** Redundant external calls to IPurDexFactory.getPair() during multi-hop swaps can be avoided by carrying the next pair address forward as the current pair for the next iteration.
**Action:** Use a sliding-window caching pattern in loops performing chained AMM operations to avoid redundant external reads.
