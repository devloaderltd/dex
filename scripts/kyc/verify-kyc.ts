import { ethers, network } from "hardhat";
import * as fs from "fs";
import * as path from "path";
import * as dotenv from "dotenv";

dotenv.config();

/**
 * Usage:
 *  USER=0x... COUNTRY=18 DEADLINE=1700000000 SIGNATURE=0x... \
 *    npx hardhat run scripts/kyc/verify-kyc.ts --network sepolia
 */
async function main() {
  const user = process.env.USER;
  const country = Number(process.env.COUNTRY || "18");
  const deadline = BigInt(process.env.DEADLINE || "0");
  const signature = process.env.SIGNATURE;

  if (!user) throw new Error("Missing env USER");
  if (!signature) throw new Error("Missing env SIGNATURE");
  if (deadline === 0n) throw new Error("Missing/invalid env DEADLINE");

  const depFile = path.join(__dirname, "..", "..", "deployments", `${network.name}.json`);
  const dep = JSON.parse(fs.readFileSync(depFile, "utf-8"));
  const kycManager = dep.contracts?.PurDexKYCManager?.address;
  if (!kycManager) throw new Error("deployments file missing contracts.PurDexKYCManager.address");

  const kyc = await ethers.getContractAt("PurDexKYCManager", kycManager);
  const tx = await kyc.verifyWithSig(user, country, deadline, signature);
  console.log("verifyWithSig tx:", tx.hash);
  await tx.wait();
  console.log("Verified! user:", user);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
