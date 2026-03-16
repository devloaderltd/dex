## 2024-05-24 - Redundant Oracle Calls in PurDexLendingPool
**Learning:** `PurDexLendingPool` makes a redundant external call to `oracle.purUsdPrice()` in `_canBorrow`. The function calls `accountLiquidity(borrower)` which fetches BOTH `ethUsdPrice()` and `purUsdPrice()` from the oracle. Then `_canBorrow` fetches `purUsdPrice()` AGAIN to calculate the USD value of the newly borrowed tokens. Oracle calls are external contract calls, and often state reads, which can cost 2100+ gas each.
**Action:** Extract the core logic of `accountLiquidity` into an internal function that returns the fetched prices alongside the liquidity stats, OR refactor `_canBorrow` to compute `addUsd` using a single shared oracle read.
Wait, if we change `accountLiquidity` to an internal `_accountLiquidity` that returns `(collateralUsd, debtUsd, maxBorrowUsd, liquidatable, ethPrice, purPrice)`, then `accountLiquidity` can just call it and return the first 4.
`_canBorrow` and `_isHealthy` can call `_accountLiquidity`. This removes 1 external call from `_canBorrow`!
This is a high-impact, clean, <50 lines optimization.
