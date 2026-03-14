import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import * as dotenv from "dotenv";

dotenv.config();

const SEPOLIA_RPC_URL = process.env.SEPOLIA_RPC_URL || "";
const SEPOLIA_PRIVATE_KEY = process.env.SEPOLIA_PRIVATE_KEY || "";
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY || "";
const MAINNET_RPC_URL = process.env.MAINNET_RPC_URL || "";
const MAINNET_PRIVATE_KEY = process.env.MAINNET_PRIVATE_KEY || "";

const config: HardhatUserConfig = {
  solidity: {
    // Latest stable Solidity (Feb 2026): https://www.soliditylang.org/
    version: "0.8.34",
    settings: {
      viaIR: true,
      optimizer: { enabled: true, runs: 200 },
    },
  },
  networks: {
   
    mainnet: {
      url: MAINNET_RPC_URL,
      chainId: 1,
      accounts: MAINNET_PRIVATE_KEY ? [MAINNET_PRIVATE_KEY] : [],
    },
     sepolia: {
      url: SEPOLIA_RPC_URL,
      accounts: SEPOLIA_PRIVATE_KEY ? [SEPOLIA_PRIVATE_KEY] : [],
    },
  },
   etherscan: {
    // 👇 V2 style: single string, not { sepolia: key }
    apiKey: ETHERSCAN_API_KEY,
  },
};

export default config;
