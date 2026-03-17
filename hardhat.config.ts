import { HardhatUserConfig, extendProvider } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import * as dotenv from "dotenv";

dotenv.config();

// Fix bad RPCs that return `to: ""` for contract-creation txs.
// Spec requires `to: null` for contract creation.
extendProvider((provider) => {
  const origRequest = provider.request.bind(provider);

  provider.request = async (args: { method: string; params?: any[] }) => {
    const res = await origRequest(args);
    if (!res) return res;

    const fixTx = (tx: any) => {
      if (tx && typeof tx === "object" && tx.to === "") {
        tx.to = null;
      }
    };

    if (args.method === "eth_getTransactionByHash" || args.method === "eth_getTransactionReceipt") {
      fixTx(res);
    } else if (args.method === "eth_getBlockByHash" || args.method === "eth_getBlockByNumber") {
      // If the second parameter is true, it returns full transaction objects
      if (args.params && args.params[1] === true && (res as any).transactions) {
        for (const tx of (res as any).transactions) {
          fixTx(tx);
        }
      }
    }

    return res;
  };

  return provider;
});

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
