// scripts/mint-one-billion.ts
import { ethers } from "hardhat";

async function main() {
  const tokenAddress = process.env.DEVTOKEN_CONTRACT_ADDRESS;
  const ownerAddress = process.env.ISSUER_ADDRESS;

  if (!tokenAddress || !ownerAddress) {
    throw new Error("Please set DEVTOKEN_CONTRACT_ADDRESS and ISSUER_ADDRESS in your .env");
  }

  // Attach to PuriCoin contract (name must match your artifacts)
  const devToken = await ethers.getContractAt("PuriCoin", tokenAddress);

  // Read decimals from contract
  const decimals = await devToken.decimals();

  // 1,000,000,000 DVT with <decimals> decimals
  // ethers v6:
  const amount = ethers.parseUnits("1000000000", decimals);
  // if you are on ethers v5, use:
  // const amount = ethers.utils.parseUnits("1000000000", decimals);

  console.log("Minting 1,000,000,000 DVT to:", ownerAddress);
  console.log("Token address:", tokenAddress);
  console.log("Raw amount (wei):", amount.toString());

  const tx = await devToken.mint(ownerAddress, amount);
  console.log("Tx sent:", tx.hash);
  const receipt = await tx.wait();
  console.log("Mint confirmed in block:", receipt.blockNumber);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
