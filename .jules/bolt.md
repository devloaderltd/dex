## 2026-07-02 - Avoid redundant rewardPerToken recalculation in modifier
**Learning:** In Synthetix-style staking contracts, calling `earned()` inside `updateReward` causes `rewardPerToken()` to be evaluated again (incurring extra SLOADs) even though its value was just cached in `rewardPerTokenStored`.
**Action:** Inline the earned calculation using the already cached `rewardPerTokenStored` inside the modifier to save gas.
