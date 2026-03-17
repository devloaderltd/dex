## 2024-05-18 - First entry
**Learning:** Initializing bolt.md as requested.
**Action:** None yet.

## 2024-05-18 - Reduce redundant oracle calls in PurDexLendingPool
**Learning:** In the `PurDexLendingPool` contract, calculating the account liquidity requires querying external oracle prices (`ethUsdPrice` and `purUsdPrice`). In functions like `liquidate` and `_canBorrow`, these oracle queries were being made multiple times, which is gas-inefficient due to repeated external calls.
**Action:** Always inspect functions for repeated external contract calls (e.g., oracle queries) and extract them to internal functions or pass the fetched values as parameters if they are used multiple times in the same transaction.
