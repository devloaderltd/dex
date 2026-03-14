import { ethers, upgrades } from "hardhat";
import { loadDeployments, saveDeployments, mustGetAddress } from "./_helpers";

async function main() {
  const dep = loadDeployments();
  const proxy = mustGetAddress(dep, "PurDexKYCManager");

  const KYC = await ethers.getContractFactory("PurDexKYCManager");
  const upgraded = await upgrades.upgradeProxy(proxy, KYC, { kind: "uups", unsafeAllow: ["constructor"] });
  await upgraded.waitForDeployment();

  const impl = await upgrades.erc1967.getImplementationAddress(proxy);
  dep.contracts.PurDexKYCManager.implementation = impl;
  saveDeployments(dep);

  console.log("Upgraded PurDexKYCManager. Proxy:", proxy);
  console.log("New implementation:", impl);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
