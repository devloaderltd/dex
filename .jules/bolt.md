## 2024-04-10 - Expensive Pair Resolving via Factory

**Learning:** In PurDex, pair addresses are BeaconProxies created dynamically, and unlike pure CREATE2 factories, you cannot easily compute their address offchain/locally without querying `IPurDexFactory(factory).getPair(tokenA, tokenB)`. Because of this, standard UniswapV2 `_swap` loops will do an expensive external cross-contract call (`getPair`) for each hop. When a pair is looked up multiple times in multi-hop trades, it drastically wastes gas.

**Action:** When working on multi-hop loops, cache the pair lookup. Look up the `nextPair` inside the loop (which gives the `to` address for the current pair swap) and then advance `currentPair = nextPair` so that you don't look up the same pair again on the next iteration.
