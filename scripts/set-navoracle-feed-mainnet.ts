/**
 * NAVOracle — Update Chainlink Feed (mainnet)
 * Calls NAVOracle.setChainlinkFeed(feed) on an existing deployed NAVOracle.
 *
 * Env (.env)
 * - NAV_ORACLE_ADDRESS           : existing NAVOracle address (mainnet)
 * - CHAINLINK_NAV_FEED_ADDRESS   : desired Chainlink AggregatorV3 proxy (mainnet)
 *
 * Usage:
 *   npx hardhat run scripts/set-navoracle-feed-mainnet.ts --network mainnet
 */

import hre from "hardhat";
import * as dotenv from "dotenv";

dotenv.config();

function mustGet(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing env var: ${name}`);
  return v;
}

async function main() {
  const navOracleAddress = mustGet("NAV_ORACLE_ADDRESS");
  const feed = mustGet("CHAINLINK_NAV_FEED_ADDRESS");

  const [deployer] = await hre.ethers.getSigners();
  const net = await hre.ethers.provider.getNetwork();

  console.log("Network chainId:", net.chainId.toString());
  console.log("Caller (must be NAVOracle owner):", deployer.address);
  console.log("NAVOracle:", navOracleAddress);
  console.log("New Chainlink feed:", feed);

  const navOracle = await hre.ethers.getContractAt("NAVOracle", navOracleAddress, deployer);
  const tx = await navOracle.setChainlinkFeed(feed);
  console.log("tx:", tx.hash);

  const receipt = await tx.wait();
  console.log("confirmed in block:", receipt?.blockNumber);

  const current = await navOracle.chainlinkFeed();
  console.log("chainlinkFeed now:", current);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
