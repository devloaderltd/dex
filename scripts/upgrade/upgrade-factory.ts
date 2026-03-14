import { ethers, upgrades } from "hardhat";
import { loadDeployments, saveDeployments, mustGetAddress } from "./_helpers";

async function main() {
  const dep = loadDeployments();
  const proxy = mustGetAddress(dep, "PurDexFactory");

  const Factory = await ethers.getContractFactory("PurDexFactory");
  const upgraded = await upgrades.upgradeProxy(proxy, Factory, { kind: "uups", unsafeAllow: ["constructor"] });
  await upgraded.waitForDeployment();

  const impl = await upgrades.erc1967.getImplementationAddress(proxy);
  dep.contracts.PurDexFactory.implementation = impl;
  saveDeployments(dep);

  console.log("Upgraded PurDexFactory. Proxy:", proxy);
  console.log("New implementation:", impl);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
