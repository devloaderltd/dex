## 2025-04-09 - Caching memory array length in a local variable before loops
**Learning:** Caching memory array length in a local variable before loops (e.g., 'uint256 length = path.length') is a standard gas optimization used in 'PurDexRouter.sol' to avoid redundant 'MLOAD' operations in loop conditions.
**Action:** Always cache the length of array in a local variable when using it in loop conditional statements.
