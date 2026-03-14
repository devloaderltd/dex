import { ethers, upgrades } from "hardhat";
import { loadDeployments, saveDeployments, mustGetAddress } from "./_helpers";

async function main() {
  const dep = loadDeployments();
  const proxy = mustGetAddress(dep, "PurDexRouter");

  const Router = await ethers.getContractFactory("PurDexRouter");
  const upgraded = await upgrades.upgradeProxy(proxy, Router, { kind: "uups", unsafeAllow: ["constructor"] });
  await upgraded.waitForDeployment();

  const impl = await upgrades.erc1967.getImplementationAddress(proxy);
  dep.contracts.PurDexRouter.implementation = impl;
  saveDeployments(dep);

  console.log("Upgraded PurDexRouter. Proxy:", proxy);
  console.log("New implementation:", impl);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
