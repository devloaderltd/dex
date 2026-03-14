import { ethers, network } from "hardhat";
import * as fs from "fs";
import * as path from "path";
import * as dotenv from "dotenv";

dotenv.config();

/**
 * Usage:
 *  USER=0x... COUNTRY=18 DEADLINE_SECONDS=3600 KYC_SIGNER_PRIVATE_KEY=0x... \
 *    npx hardhat run scripts/kyc/sign-kyc.ts --network sepolia
 */
async function main() {
  const user = process.env.USER;
  const country = Number(process.env.COUNTRY || "18");
  const ttl = Number(process.env.DEADLINE_SECONDS || "3600");
  const pk = process.env.KYC_SIGNER_PRIVATE_KEY;

  if (!user) throw new Error("Missing env USER");
  if (!pk) throw new Error("Missing env KYC_SIGNER_PRIVATE_KEY");

  const depFile = path.join(__dirname, "..", "..", "deployments", `${network.name}.json`);
  const dep = JSON.parse(fs.readFileSync(depFile, "utf-8"));
  const kycManager = dep.contracts?.PurDexKYCManager?.address;
  if (!kycManager) throw new Error("deployments file missing contracts.PurDexKYCManager.address");

  const provider = ethers.provider;
  const signerWallet = new ethers.Wallet(pk, provider);

  const kyc = await ethers.getContractAt("PurDexKYCManager", kycManager);
  const nonce = await kyc.nonces(user);
  const deadline = BigInt(Math.floor(Date.now() / 1000) + ttl);

  const chainId = (await provider.getNetwork()).chainId;
  const domain = {
    name: "PurDexKYCManager",
    version: "1",
    chainId,
    verifyingContract: kycManager,
  };

  const types = {
    KYCApproval: [
      { name: "user", type: "address" },
      { name: "country", type: "uint16" },
      { name: "deadline", type: "uint256" },
      { name: "nonce", type: "uint256" },
    ],
  };

  const value = {
    user,
    country,
    deadline,
    nonce,
  };

  const signature = await signerWallet.signTypedData(domain as any, types as any, value as any);

  console.log("KYC signer:", signerWallet.address);
  console.log("User:", user);
  console.log("Country:", country);
  console.log("Deadline:", deadline.toString());
  console.log("Nonce:", nonce.toString());
  console.log("Signature:", signature);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
