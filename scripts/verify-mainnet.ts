/**
 * PuriCoin — Verify Script (mainnet record)
 * ----------------------------------------
 * Company : Dev Loader (CronLab)
 * Website : https://devloader.com
 * Date    : 2025-12-22
 *
 * Purpose
 * - Verify contracts listed in a mainnet deployment record file.
 * - Helpful when using a custom mainnet deploy script that writes a different JSON shape.
 *
 * Reviewer-friendly notes
 * - Verification is optional but recommended for buyer trust and easier integration.
 * - Constructor args MUST match the deployed bytecode configuration exactly.
 */
import hre from "hardhat";
import * as fs from "fs";
import * as path from "path";

interface DeployedContractInfo {
  name: string;
  address: string;
  txHash: string;
}

interface DeploymentRecord {
  network: string;
  chainId: number;
  deployer: string;
  timestamp: string;
  contracts: DeployedContractInfo[];
}

/**
 * Verifies contracts using a mainnet deployment record file.
 *
 * IMPORTANT:
 * - This script assumes the deployment record lists contract names that match your artifacts.
 * - Ensure constructor arguments match the Solidity constructors exactly.
 * - If your deploy-mainnet script deploys a legacy name (e.g., "Puritoken") but your verify
 *   script expects "PuriCoin", verification will fail until names are aligned.
 */
async function main() {
  const deploymentsDir = path.join(__dirname, "..", "deployments");
  const latestPath = path.join(deploymentsDir, "puricoin-mainnet-latest.json");

  if (!fs.existsSync(latestPath)) {
    throw new Error(`Deployment file not found: ${latestPath}`);
  }

  const json = fs.readFileSync(latestPath, "utf-8");
  const record = JSON.parse(json) as DeploymentRecord;

  console.log("Using deployment record:");
  console.log(`  network : ${record.network}`);
  console.log(`  chainId : ${record.chainId}`);
  console.log(`  deployer: ${record.deployer}`);
  console.log("");

  const byName = (name: string): DeployedContractInfo => {
    const found = record.contracts.find((c) => c.name === name);
    if (!found) {
      throw new Error(`Contract ${name} not found in deployment record`);
    }
    return found;
  };

  const identity = byName("IdentityRegistry");
  const compliance = byName("BasicCompliance");
  const navOracle = byName("NAVOracle");
  const proofRegistry = byName("ProofRegistry");
// Token contract name must match the deploy record. If you deployed "Puritoken" on mainnet,
// change this lookup accordingly or update the deploy script to deploy "PuriCoin".
const puricoin = byName("PuriCoin");

// constructor args per contract
// NOTE: These must match the exact Solidity constructor inputs used at deploy-time.
// If NAVOracle expects a Chainlink feed address (or 0x0), do NOT pass deployer by mistake.
  const constructorArgs: Record<string, any[]> = {
    NAVOracle: [record.deployer],
    PuriCoin: [
      identity.address,
      compliance.address,
      8, // decimals_
    ],
    // others have no constructor args
  };

  const contractsToVerify: DeployedContractInfo[] = [
    identity,
    compliance,
    navOracle,
    proofRegistry,
    puricoin,
  ];

  for (const c of contractsToVerify) {
    console.log(`Verifying ${c.name} at ${c.address} ...`);

    try {
      await hre.run("verify:verify", {
        address: c.address,
        constructorArguments: constructorArgs[c.name] ?? [],
      });

      console.log(`✅ ${c.name} verified`);
    } catch (err: any) {
      const msg = (err && err.message) || String(err);
      if (msg.includes("Already Verified")) {
        console.log(`ℹ️  ${c.name} already verified, skipping.`);
      } else {
        console.error(`⚠️  Failed to verify ${c.name}:`, msg);
      }
    }

    console.log("");
  }

  console.log("Done.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
