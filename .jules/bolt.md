## 2024-05-24 - Cache memory array lengths
**Learning:** Caching the length of an array stored in `memory` (`uint256 length = path.length`) into a local variable before iterating over it avoids the repeated `mload` operation in loop conditions, leading to noticeable gas savings.
**Action:** Next time writing `for` loops that iterate over memory or storage arrays, cache the `.length` explicitly.
