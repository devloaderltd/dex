/**
 * PuriCoin — Hardhat Verify Script (generic)
 * -----------------------------------------
 * Company : Dev Loader (CronLab)
 * Website : https://devloader.com
 * Date    : 2025-12-22
 *
 * Purpose
 * - Verify deployed contracts on the network explorer using Hardhat's verify task.
 * - Reads `deployments/<network>.json` created by your deploy script and verifies each address.
 *
 * Requirements
 * - Hardhat verification plugin configured (e.g., hardhat-etherscan) and the correct API key set in `.env`.
 * - Constructor arguments must match exactly what was used at deployment time.
 */
import { network, run } from "hardhat";
import * as fs from "fs";
import * as path from "path";

/**
 * Verifies each contract listed in the deployment JSON for the active Hardhat network.
 *
 * Typical usage:
 *   npx hardhat run scripts/verify.ts --network sepolia
 *
 * Notes for buyers:
 * - If verification fails with "Already Verified", it's safe to ignore.
 * - If constructor args mismatch, update `constructorArguments` in your deployment JSON generation.
 */
async function main() {
  // Deployment JSON created by deploy script
  const file = path.join(__dirname, "..", "deployments", `${network.name}.json`);
  if (!fs.existsSync(file)) {
    throw new Error(`Deployment file not found: ${file}`);
  }

  const deployment = JSON.parse(fs.readFileSync(file, "utf8")) as any;

  for (const [name, info] of Object.entries<any>(deployment.contracts)) {
    // For upgradeable contracts, verify the implementation (proxies are usually already verified by explorers).
    const targetAddress = info.proxy && info.implementation ? info.implementation : info.address;
    const label = info.proxy && info.implementation ? `${name} (implementation)` : name;

    console.log(`Verifying ${label} at ${targetAddress}...`);
    try {
      await run("verify:verify", {
        address: targetAddress,
        constructorArguments: info.constructorArguments || [],
      });
      console.log(`✅ ${label} verified`);
    } catch (e: any) {
      console.log(`⚠️ ${label} verification issue: ${e.message}`);
    }
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
