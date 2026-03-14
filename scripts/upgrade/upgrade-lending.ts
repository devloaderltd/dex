import { ethers, upgrades } from "hardhat";
import { loadDeployments, saveDeployments, mustGetAddress } from "./_helpers";

async function main() {
  const dep = loadDeployments();
  const proxy = mustGetAddress(dep, "PurDexLendingPool");

  const Lending = await ethers.getContractFactory("PurDexLendingPool");
  const upgraded = await upgrades.upgradeProxy(proxy, Lending, { kind: "uups", unsafeAllow: ["constructor"] });
  await upgraded.waitForDeployment();

  const impl = await upgrades.erc1967.getImplementationAddress(proxy);
  dep.contracts.PurDexLendingPool.implementation = impl;
  saveDeployments(dep);

  console.log("Upgraded PurDexLendingPool. Proxy:", proxy);
  console.log("New implementation:", impl);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
