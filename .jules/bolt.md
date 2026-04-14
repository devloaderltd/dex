## 2024-05-18 - [Gas Optimization: Caching Memory Array Length]
**Learning:** In Solidity, accessing `array.length` for a `memory` array in loop conditions executes an `MLOAD` instruction every iteration, adding unnecessary gas costs. This is particularly relevant in multi-hop loops like `_swap` or `getAmountsOut`.
**Action:** Always cache the length of `memory` arrays in a local `uint256` variable before entering `for` loops to save gas per iteration.
