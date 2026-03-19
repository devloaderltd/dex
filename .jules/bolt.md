
## 2024-03-19 - Cache getPair addresses in multi-hop swaps
**Learning:** In the PurDex architecture, AMM pair addresses cannot be computed locally via CREATE2 hash because they are deployed as `BeaconProxy` instances. Resolving pair addresses requires an external call to `IPurDexFactory.getPair()`. During multi-hop swaps inside the Router, making this external call repeatedly per hop wastes gas.
**Action:** When working with BeaconProxy pairs, cache the pair address obtained during the initial lookup or multi-hop loops, and pass it along instead of redundantly calling `getPair()`.
