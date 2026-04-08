## 2024-04-08 - Caching Array Lengths in Solidity Loops
**Learning:** In Solidity, accessing `array.length` within a loop condition triggers a redundant `MLOAD` operation for memory arrays or `SLOAD` for storage arrays on each iteration. This is a common performance anti-pattern that unnecessarily consumes gas.
**Action:** Always cache the array length in a local variable before the loop (e.g., `uint256 length = path.length;`) and use the local variable in the loop condition to avoid redundant reads and save gas.
