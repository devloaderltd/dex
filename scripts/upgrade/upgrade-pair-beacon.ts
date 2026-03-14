import { ethers } from "hardhat";
import { loadDeployments, saveDeployments, mustGetAddress } from "./_helpers";

async function main() {
  const dep = loadDeployments();
  const beaconAddr = mustGetAddress(dep, "PurDexPairBeacon");

  // 1) Deploy a new pair implementation
  const Pair = await ethers.getContractFactory("PurDexPair");
  const impl = await Pair.deploy();
  await impl.waitForDeployment();
  const newImpl = await impl.getAddress();

  // 2) Point beacon to the new implementation (upgrades ALL pairs)
  const beacon = await ethers.getContractAt("PurDexPairBeacon", beaconAddr);
  await (await beacon.upgradeTo(newImpl)).wait();

  dep.contracts.PurDexPairImplementation = { address: newImpl, constructorArguments: [] };
  // keep beacon entry as-is
  saveDeployments(dep);

  console.log("Upgraded pair beacon:", beaconAddr);
  console.log("New pair implementation:", newImpl);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
