## 2024-05-08 - Redundant rewardPerToken() recalculation in StakingRewards
**Learning:** The updateReward modifier computes rewardPerToken() and updates rewardPerTokenStored. Immediately after, it calls earned(), which redundantly recalculates rewardPerToken() from scratch, wasting gas on SLOADs and math operations.
**Action:** Inline the earned calculation using the freshly cached rewardPerTokenStored variable within updateReward to save gas.
