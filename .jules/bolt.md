## 2024-05-14 - Optimizing `accrueInterest` in LendingPool

**Learning:** `accrueInterest()` in `PurDexLendingPool.sol` is marked `public`, but it's called internally by many functions (`deposit`, `borrow`, `repay`, `liquidate`, etc.). Having a `public` function means the compiler generates an external wrapper and the internal calls might be less efficient, but it's okay. A better optimization is looking at redundant calculations or storage accesses. Wait, if `accrueInterest` is only ever called internally, we can make it `internal` and expose an `external` function if needed. Wait, it doesn't matter much for gas if it's called internally (internal calls are JUMPs). Let's look for state caching opportunities inside `accrueInterest`.

Inside `accrueInterest()`:
```solidity
    function accrueInterest() public {
        uint256 ts = block.timestamp;
        uint256 dt = ts - lastAccrual;
        if (dt == 0) return;

        lastAccrual = ts;
        if (totalBorrows == 0) return;

        uint256 rate = borrowRatePerSecond();
...
```

Let's check `borrowRatePerSecond()`:
```solidity
    function borrowRatePerSecond() public view returns (uint256 ratePerSecondWad) {
        uint256 util = utilization();
        uint256 ratePerYear = baseRatePerYear + ((slopePerYear * util) / WAD);
        return ratePerYear / SECONDS_PER_YEAR;
    }

    function utilization() public view returns (uint256 utilWad) {
        uint256 cash = IERC20(address(pur)).balanceOf(address(this));
        if (totalBorrows == 0) return 0;
        return (totalBorrows * WAD) / (cash + totalBorrows);
    }
```
`totalBorrows` is read from storage multiple times. `totalBorrows` inside `accrueInterest()`, inside `borrowRatePerSecond()`, inside `utilization()`.
If we cache `totalBorrows`, we could save `SLOAD`s.

But actually, wait! `borrowRatePerSecond()` is `public`. It reads `totalBorrows` (SLOAD). Then `accrueInterest` reads `totalBorrows` (SLOAD). Then `accrueInterest` writes to `totalBorrows` (SSTORE).

Another potential optimization is in `PurDexLendingPool.sol` or `PurDexStakingRewards.sol`. I already optimized `PurDexStakingRewards.sol` in the past (by caching `rewardPerTokenStored`).
Wait! In `PurDexLendingPool.sol`, we can change `accrueInterest` to cache `totalBorrows` in memory and pass it to internal versions of `borrowRatePerSecond`, or just cache `totalBorrows` inside `accrueInterest` and do the calculation inline to avoid the SLOAD.

Let's look at `utilization`:
```solidity
    function utilization() public view returns (uint256 utilWad) {
        uint256 cash = IERC20(address(pur)).balanceOf(address(this));
        if (totalBorrows == 0) return 0;
        return (totalBorrows * WAD) / (cash + totalBorrows);
    }
```
Wait, if `totalBorrows` is cached, we can avoid reading it again.
Wait, memory says "_swap internal function in PurDexRouter.sol has been optimized to accept address currentPair as a fourth argument." It seems I've already done that in another PR or the memory is describing a standard optimization for `_swap`. Wait, memory says:
"The _swap internal function in PurDexRouter.sol has been optimized to accept address currentPair as a fourth argument. It utilizes a sliding-window caching pattern where the nextPair address (to) calculated in iteration i becomes the currentPair for the subsequent iteration i+1, eliminating redundant external calls to IPurDexFactory.getPair() during multi-hop swaps."
Wait, if `_swap` currently does NOT have `address currentPair` as a fourth argument, I should implement it!
Let's check current `_swap`:
```solidity
    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal {
        for (uint256 i = 0; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = PurDexLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));

            address to = i < path.length - 2
                ? IPurDexFactory(factory).getPair(output, path[i + 2])
                : _to;

            IPurDexPair(IPurDexFactory(factory).getPair(input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
```
Yes! It takes 3 arguments. And there is a duplicate call to `IPurDexFactory(factory).getPair`.
Actually, wait, in `_swap` right now, `IPurDexFactory(factory).getPair(output, path[i + 2])` calculates the `nextPair` (`to`), and then `IPurDexFactory(factory).getPair(input, output)` calculates the `currentPair`.
In the loop, `currentPair` is exactly the `nextPair` from the previous iteration.
If we pass `currentPair` as an argument to `_swap`, we can avoid the second `getPair` call entirely.
Wait, let's trace:
For `swapExactTokensForTokens` (etc), the tokens are sent to `IPurDexFactory(factory).getPair(path[0], path[1])`. That's the initial `currentPair`.

Let's check how `_swap` is called:
```solidity
    function swapExactTokensForTokens(...) public ... {
        ...
        address firstPair = IPurDexFactory(factory).getPair(path[0], path[1]);
        TransferHelper.safeTransferFrom(path[0], msg.sender, firstPair, amounts[0]);
        _swap(amounts, path, to, firstPair);
    }
```
Wait, we need to modify ALL places where `_swap` is called to pass the `firstPair`!
Let's see where `_swap` is called in `PurDexRouter.sol`.
Wait, modifying `_swap` to accept `currentPair` as a parameter is exactly what the memory mentions:
"The _swap internal function in PurDexRouter.sol has been optimized to accept address currentPair as a fourth argument. It utilizes a sliding-window caching pattern where the nextPair address (to) calculated in iteration i becomes the currentPair for the subsequent iteration i+1, eliminating redundant external calls to IPurDexFactory.getPair() during multi-hop swaps."

Let's implement this!

The current `_swap` looks like this:
```solidity
    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal {
        for (uint256 i = 0; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = PurDexLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));

            address to = i < path.length - 2
                ? IPurDexFactory(factory).getPair(output, path[i + 2])
                : _to;

            IPurDexPair(IPurDexFactory(factory).getPair(input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
```

We will change it to:
```solidity
    function _swap(uint256[] memory amounts, address[] memory path, address _to, address _currentPair) internal {
        address currentPair = _currentPair;
        for (uint256 i = 0; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = PurDexLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));

            address to = i < path.length - 2
                ? IPurDexFactory(factory).getPair(output, path[i + 2])
                : _to;

            IPurDexPair(currentPair).swap(amount0Out, amount1Out, to, new bytes(0));
            currentPair = to;
        }
    }
```

Wait, `currentPair = to;` is correct because `to` is `IPurDexFactory(factory).getPair(output, path[i + 2])` which is exactly the `currentPair` for the next iteration (`input` will be `output`, and `output` will be `path[i + 2]`).

Let's check where `_swap` is called:
1. `swapExactTokensForTokens` (line 245):
```solidity
        address pair = IPurDexFactory(factory).getPair(mpath[0], mpath[1]);
        mpath[0].safeTransferFrom(msg.sender, pair, amounts[0]);
        _swap(amounts, mpath, to, pair);
```
2. `swapExactETHForTokens` (line 265):
```solidity
        address pair = IPurDexFactory(factory).getPair(mpath[0], mpath[1]);
        WETH.safeTransfer(pair, amounts[0]);
        _swap(amounts, mpath, to, pair);
```
3. `swapExactTokensForETH` (line 285):
```solidity
        address pair = IPurDexFactory(factory).getPair(mpath[0], mpath[1]);
        mpath[0].safeTransferFrom(msg.sender, pair, amounts[0]);
        _swap(amounts, mpath, address(this), pair);
```
4. `swapExactETHForPUR` (line 310):
```solidity
        address pair = IPurDexFactory(factory).getPair(path[0], path[1]);
        WETH.safeTransfer(pair, amounts[0]);
        _swap(amounts, path, to, pair);
```
5. `swapExactPURForETH` (line 331):
```solidity
        address pair = IPurDexFactory(factory).getPair(path[0], path[1]);
        path[0].safeTransferFrom(msg.sender, pair, amounts[0]);
        _swap(amounts, path, address(this), pair);
```

This is exactly what the memory describes.

Are there other places? Let's check `swapExactTokensForTokensSupportingFeeOnTransferTokens`.
Wait, this contract might not have `SupportingFeeOnTransferTokens` functions, let's verify.
## 2024-05-14 - Optimizing `_swap` in `PurDexRouter.sol`
**Learning:** `_swap` iterates through the multi-hop path and for each pair, calculates `to` which becomes the input pair for the next iteration. Redundantly, the next iteration calculates the current pair again via `IPurDexFactory(factory).getPair(input, output)`. We can eliminate one external `getPair` call per iteration by passing the `firstPair` to `_swap` and updating it as `currentPair = to` at the end of each iteration. This sliding window approach saves significant gas by reducing external calls to the factory.
**Action:** Modify `_swap` to accept `address currentPair`, pass it from the initial `getPair` calls in external functions, and update it inside the loop.
