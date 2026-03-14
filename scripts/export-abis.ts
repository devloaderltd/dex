/**
 * PuriCoin — ABI Export Script
 * ---------------------------
 * Company : Dev Loader (CronLab)
 * Website : https://devloader.com
 * Date    : 2025-12-22
 *
 * Purpose
 * - Export ABIs from Hardhat artifacts into a simple `abis/` folder for UI/panel integration.
 *
 * Notes
 * - This is helpful for the Laravel control panel to call contracts using a standard ABI JSON.
 */
import hre from "hardhat";
import * as fs from "fs";
import * as path from "path";

/**
 * Exports ABIs into `abis/` for front-end / Laravel integration.
 * This keeps the panel decoupled from Hardhat artifact folder structure.
 */
async function main() {
  // Output folder for ABI JSON files (created if missing)
  const outputDir = path.join(__dirname, "..", "abis");

  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  // Contracts to export (keep in sync with your suite)
  const contractNames = [
    "IdentityRegistry",
    "BasicCompliance",
    "NAVOracle",
    "ProofRegistry",
    "PuriCoin",

    // --- PurDex + Pools ---
    "PurDexKYCManager",
    "WETH9",
    "PurDexFactory",
    "PurDexPair",
    "PurDexRouter",
    "PurDexStakingRewards",
    "PurDexOracleRouter",
    "PurDexLendingPool",
  ];

  for (const name of contractNames) {
    const artifact = await hre.artifacts.readArtifact(name);
    const abi = artifact.abi;

    const filePath = path.join(outputDir, `${name}.abi.json`);
    fs.writeFileSync(filePath, JSON.stringify(abi, null, 2), {
      encoding: "utf-8",
    });

    console.log(`Exported ABI for ${name} -> ${filePath}`);
  }

  console.log("\nAll ABIs exported.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
