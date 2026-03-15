
import { ethers, network } from "hardhat";
import * as fs from "fs";
import * as path from "path";
import * as dotenv from "dotenv";

dotenv.config();

function env(name: string, fallback?: string): string {
  const v = process.env[name];
  if (v !== undefined && v.trim() !== "") return v;
  if (fallback !== undefined) return fallback;
  throw new Error(`Missing env var: ${name}`);
}

function envInt(name: string, fallback: string): number {
  const v = env(name, fallback);
  const n = Number.parseInt(v, 10);
  if (!Number.isFinite(n)) throw new Error(`Invalid integer for ${name}: ${v}`);
  return n;
}
async function main() {
  const [deployer] = await ethers.getSigners();

  // Token meta (set once at deployment time; changing later requires redeploy)
  const TOKEN_SYMBOL = env("TOKEN_SYMBOL", "PUR");
  const TOKEN_DECIMALS = envInt("TOKEN_DECIMALS", "18");
  // Supply config (human-readable tokens, not wei)
  const INITIAL_SUPPLY = env("INITIAL_SUPPLY", "0");
  const INVESTOR_COUNTRY_CODE = env("INVESTOR_COUNTRY_CODE", "18");

  if (TOKEN_DECIMALS < 0 || TOKEN_DECIMALS > 18) {
    throw new Error("TOKEN_DECIMALS must be between 0 and 18");
  }

  console.log(`Deploying from: ${deployer.address}`);
  console.log(`Network: ${network.name}`);

  const PuriCoin = await ethers.getContractFactory("PuriCoin");
  const puricoin = await PuriCoin.deploy(
    TOKEN_DECIMALS
  );
  await puricoin.waitForDeployment();
  console.log("PuriCoin:", await puricoin.getAddress());

  const tx3 = await puricoin.mint(
    deployer.address,
    ethers.parseUnits(INITIAL_SUPPLY, TOKEN_DECIMALS)
  );
  await tx3.wait();
  console.log("Minted ",INITIAL_SUPPLY, TOKEN_SYMBOL," to deployer");

  const feedAddr = process.env.CHAINLINK_NAV_FEED_ADDRESS || ethers.ZeroAddress;
  const NAVOracle = await ethers.getContractFactory("NAVOracle");
  const navOracle = await NAVOracle.deploy(feedAddr);
  await navOracle.waitForDeployment();
  console.log("NAVOracle:", await navOracle.getAddress());

/**
 * Demo NAV value:
 * - 1_000_000_000 with 8 decimals => 10.00000000 (example)
 * Buyers can adjust these values based on their RWA valuation logic.
 */
const navTx = await navOracle.setManualNAV(1_000_000_000, 18);
  await navTx.wait();

  const deployment = {
    network: network.name,
    deployedAt: new Date().toISOString(),
    contracts: {
      PuriCoin: {
        address: await puricoin.getAddress(),
        constructorArguments: [
          TOKEN_DECIMALS,
        ],
      },
      NAVOracle: {
        address: await navOracle.getAddress(),
        constructorArguments: [feedAddr],
      },
    },
  };

  const dir = path.join(__dirname, "..", "deployments");
  fs.mkdirSync(dir, { recursive: true });
  const outFile = path.join(dir, `${network.name}.json`);
  fs.writeFileSync(outFile, JSON.stringify(deployment, null, 2));

  console.log("Deployment info saved to", outFile);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
