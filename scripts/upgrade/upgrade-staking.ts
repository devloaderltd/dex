import { ethers, upgrades } from "hardhat";
import { loadDeployments, saveDeployments, mustGetAddress } from "./_helpers";

async function main() {
  const dep = loadDeployments();
  const proxy = mustGetAddress(dep, "PurDexStakingRewards");

  const Staking = await ethers.getContractFactory("PurDexStakingRewards");
  const upgraded = await upgrades.upgradeProxy(proxy, Staking, { kind: "uups", unsafeAllow: ["constructor"] });
  await upgraded.waitForDeployment();

  const impl = await upgrades.erc1967.getImplementationAddress(proxy);
  dep.contracts.PurDexStakingRewards.implementation = impl;
  saveDeployments(dep);

  console.log("Upgraded PurDexStakingRewards. Proxy:", proxy);
  console.log("New implementation:", impl);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
