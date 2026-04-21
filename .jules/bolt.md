
## 2024-05-24 - BeaconProxy Caching Requirement
**Learning:** In the PurDex architecture, AMM pair addresses are deployed as `BeaconProxy` instances rather than standard pairs. Because of this, pair addresses cannot be computed locally via CREATE2 hash using standard UniswapV2 libraries. Resolving pair addresses requires a costly external call to `IPurDexFactory.getPair()`.
**Action:** When implementing loops that traverse multiple hops (e.g., in `PurDexRouter._swap`), always cache the resolved pair addresses (`currentPair` and `nextPair`) and reuse them across iterations. This eliminates redundant external calls and significantly reduces gas costs in multi-hop swaps.
