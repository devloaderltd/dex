## 2024-05-05 - Multi-hop Swap Optimization
**Learning:** In the PurDexRouter._swap function, external calls to IPurDexFactory.getPair are redundantly executed. The 'to' address derived for step i matches the pair address for step i+1.
**Action:** Implement sliding window caching for the currentPair address during loops to save gas.
