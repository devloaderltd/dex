
## 2024-05-18 - Array Length Caching Optimization
**Learning:** Caching memory array length in a local variable before loops (e.g., `uint256 length = path.length`) avoids redundant `MLOAD` operations during each loop iteration. This is particularly useful in multi-hop swap iterations within a DEX router context.
**Action:** Always check array lengths within loops and extract them to a local variable if the array size does not mutate during iteration.
