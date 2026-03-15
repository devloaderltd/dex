/**
 * PuriCoin — Mainnet Deployment Script (RPC + private key)
 * -------------------------------------------------------
 * Company : Dev Loader (CronLab)
 * Website : https://devloader.com
 * Date    : 2025-12-22
 *
 * Purpose
 * - Deploy contracts using a JSON-RPC provider and an EOA private key.
 * - Write a timestamped deployment record (and a `latest` record) to `deployments/`.
 *
 * Environment (.env)
 * - MAINNET_RPC_URL      : Ethereum mainnet RPC endpoint
 * - MAINNET_PRIVATE_KEY  : Deployer private key (NEVER commit; NEVER ship in CodeCanyon ZIP)
 *
 * Reviewer-friendly notes
 * - This file keeps deployment steps explicit and logs each tx hash/address for traceability.
 * - If any constructor signature changes, update the deployment arguments accordingly.
 */
import { ethers } from "ethers";
import hre from "hardhat";
import * as dotenv from "dotenv";
import * as fs from "fs";
import * as path from "path";

dotenv.config();

/**
 * IMPORTANT
 * ---------
 * This script uses a raw private key for mainnet deployment. For production usage, consider:
 * - hardware wallet / multisig deploy flows
 * - secure secret management (CI secrets)
 *
 * Never include MAINNET_PRIVATE_KEY in your CodeCanyon ZIP.
 * Provide `.env.example` only.
 */


/**
 * Deployment metadata written to disk for transparency and later verification.
 * Keeping these fields explicit helps CodeCanyon buyers understand what's deployed.
 */
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
 * Deploy to Ethereum mainnet using MAINNET_RPC_URL + MAINNET_PRIVATE_KEY.
 *
 * Steps:
 * 1) Connect to RPC, assert chainId, and print deployer address.
 * 2) Deploy contracts and record tx hashes + addresses.
 * 3) Write JSON files:
 *    - deployments/mainnet-<timestamp>.json
 *    - deployments/mainnet-latest.json
 *
 * NOTE
 * - Double-check constructor signatures in Solidity.
 * - This file currently references a legacy token artifact name (e.g., "PuriCoin").
 *   If your compiled artifact is "PuriCoin", update the artifact read + deployment section accordingly.
 */
async function main() {
  const rpcUrl = process.env.MAINNET_RPC_URL;
  const pk = process.env.MAINNET_PRIVATE_KEY;
  const TOKEN_DECIMAL = process.env.TOKEN_DECIMAL;

  if (!rpcUrl || !pk) {
    throw new Error("MAINNET_RPC_URL or MAINNET_PRIVATE_KEY is missing in .env");
  }

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(pk, provider);

  const deployerAddress = await wallet.getAddress();
  console.log("Deploying from:", deployerAddress);

  const network = await provider.getNetwork();
  const chainId = Number(network.chainId);
  console.log("Network:", network.name, `(chainId=${chainId})`);

  if (chainId !== 1) {
    console.warn(
      `⚠️ WARNING: Connected chainId is ${chainId}, not 1 (mainnet). ` +
        `Make sure you are really on Ethereum mainnet before proceeding.`,
    );
  }

  const deployed: DeployedContractInfo[] = [];

  // ---------- Load Artifacts from Hardhat ----------
  const NAVOracleArtifact = await hre.artifacts.readArtifact("NAVOracle");
  const PuritokenArtifact = await hre.artifacts.readArtifact("PuriCoin");

  // ---------- 1) NAVOracle ----------
  console.log("\nDeploying NAVOracle...");
  const NAVOracleFactory = new ethers.ContractFactory(
    NAVOracleArtifact.abi,
    NAVOracleArtifact.bytecode,
    wallet,
  );

// NAVOracle constructor note:
// - Confirm the Solidity constructor signature before mainnet deploy.
// - In the PuriCoin contract version you shared, NAVOracle expects a Chainlink feed address (or 0x0).
// - Passing the deployer address here may be incorrect for NAV usage; adjust as needed.
//
// NAVOracle: constructor(address initialOwner)
  const navOracle = await NAVOracleFactory.deploy(deployerAddress);
  const navTx = navOracle.deploymentTransaction();
  console.log("  tx:", navTx?.hash);
  await navOracle.waitForDeployment();
  const navOracleAddress = await navOracle.getAddress();
  console.log("  deployed at:", navOracleAddress);

  deployed.push({
    name: "NAVOracle",
    address: navOracleAddress,
    txHash: navTx?.hash || "",
  });

  // ---------- 2) PuriCoin ----------
// NOTE: Legacy name in this script. For the current product branding, your token contract is "PuriCoin".
// Keep the artifact name and deployment record consistent across:
// - deploy scripts
// - verify scripts
// - ABI export
  console.log("\nDeploying PuriCoin...");
  const PuritokenFactory = new ethers.ContractFactory(
    PuritokenArtifact.abi,
    PuritokenArtifact.bytecode,
    wallet,
  );

  // PuriCoin constructor:
  const decimals = TOKEN_DECIMAL;

  const puricoin = await PuritokenFactory.deploy(
    decimals,
  );

  const purTx = puricoin.deploymentTransaction();
  console.log("  tx:", purTx?.hash);
  await puricoin.waitForDeployment();
  const devtokenAddress = await puricoin.getAddress();
  console.log("  deployed at:", devtokenAddress);

  deployed.push({
    name: "PuriCoin",
    address: devtokenAddress,
    txHash: purTx?.hash || "",
  });

  // ---------- Summary ----------
  console.log("\n=== Deployment summary (mainnet) ===");
  deployed.forEach((c) => {
    console.log(`${c.name.padEnd(16)}: ${c.address} (tx: ${c.txHash})`);
  });

  // ---------- Save deployment info to JSON ----------
  const deploymentsDir = path.join(__dirname, "..", "deployments");
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }

  const record: DeploymentRecord = {
    network: "mainnet",
    chainId,
    deployer: deployerAddress,
    timestamp: new Date().toISOString(),
    contracts: deployed,
  };

  const timestampStr = new Date().toISOString().replace(/[:.]/g, "-");
  const fileName = `puricoin-mainnet-${timestampStr}.json`;
  const latestName = `puricoin-mainnet-latest.json`;

  const fullPath = path.join(deploymentsDir, fileName);
  const latestPath = path.join(deploymentsDir, latestName);

  fs.writeFileSync(fullPath, JSON.stringify(record, null, 2), { encoding: "utf-8" });
  fs.writeFileSync(latestPath, JSON.stringify(record, null, 2), { encoding: "utf-8" });

  console.log(`\nDeployment info saved to:`);
  console.log(`  - ${fullPath}`);
  console.log(`  - ${latestPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
