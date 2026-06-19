## 2026-06-19 - Sliding-Window Caching for External Calls
**Learning:** In multi-hop operations (like AMM routing), the target address for step i is often the execution context for step i+1. Re-calculating the address via external calls creates redundant gas costs.
**Action:** Apply a sliding-window cache pattern by passing the initial context and caching the calculated 'next' context for the subsequent iteration.
