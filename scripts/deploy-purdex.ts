import { ethers, network, upgrades } from "hardhat";
import * as fs from "fs";
import * as path from "path";
import * as dotenv from "dotenv";

dotenv.config();

function loadDeployment(netName: string) {
  const file = path.join(__dirname, "..", "deployments", `${netName}.json`);
  if (!fs.existsSync(file)) {
    throw new Error(`Missing deployments file: ${file}`);
  }
  return { file, json: JSON.parse(fs.readFileSync(file, "utf-8")) };
}

function mergeDeployment(file: string, existing: any, extraContracts: any) {
  const out = { ...existing };
  out.contracts = { ...(existing.contracts || {}), ...extraContracts };
  out.updatedAt = new Date().toISOString();
  fs.writeFileSync(file, JSON.stringify(out, null, 2));
  return out;
}

async function main() {
  // Fix bad RPCs that return `to: ""` for contract-creation txs.
// Spec requires `to: null` for contract creation.
const p: any = network.provider;

if (p?.request) {
  const orig = p.request.bind(p);
  p.request = async (args: { method: string; params?: any[] }) => {
    const res = await orig(args);
    if (
      (args.method === "eth_getTransactionByHash" || args.method === "eth_getTransactionReceipt") &&
      res && typeof res === "object" && (res as any).to === ""
    ) {
      (res as any).to = null;
    }
    return res;
  };
}
  const [deployer] = await ethers.getSigners();
  console.log(`Network: ${network.name}`);
  console.log(`Deployer: ${deployer.address}`);

  const { file, json: dep } = loadDeployment(network.name);
  const pur = dep.contracts?.PuriCoin?.address;
  const navOracle = dep.contracts?.NAVOracle?.address;
  if (!pur) {
    throw new Error("deployments/<network>.json must include PuriCoin addresses");
  }

  // As requested: use the deployer as the treasury + admin.
  const treasury = deployer.address;
  console.log(`Treasury (feeTo + admin): ${treasury}`);

  // --- 2) Deploy WETH ---
  const WETH9 = await ethers.getContractFactory("WETH9");
  const weth = await WETH9.deploy();
  await weth.waitForDeployment();
  const wethAddr = await weth.getAddress();
  console.log("WETH9:", wethAddr);

  // --- 3) Deploy Pair implementation + Pair beacon (upgrade path for all pairs) ---
  const Pair = await ethers.getContractFactory("PurDexPair");
  const pairImplCtr = await Pair.deploy();
  await pairImplCtr.waitForDeployment();
  const pairImplAddr = await pairImplCtr.getAddress();
  console.log("PurDexPair implementation:", pairImplAddr);

  const Beacon = await ethers.getContractFactory("PurDexPairBeacon");
  const pairBeacon = await Beacon.deploy(pairImplAddr);
  await pairBeacon.waitForDeployment();
  const pairBeaconAddr = await pairBeacon.getAddress();
  console.log("Pair Beacon:", pairBeaconAddr);

  // --- 4) Deploy Factory (UUPS proxy) ---
  const Factory = await ethers.getContractFactory("PurDexFactory");
  const factory = await upgrades.deployProxy(Factory, [treasury, pairBeaconAddr], {
    kind: "uups",
    unsafeAllow: ["constructor"],
  });
  await factory.waitForDeployment();
  const factoryAddr = await factory.getAddress();
  const factoryImpl = await upgrades.erc1967.getImplementationAddress(factoryAddr);
  console.log("PurDexFactory (proxy):", factoryAddr);

  // feeTo -> treasury
  await (await factory.setFeeTo(treasury)).wait();
  console.log("Factory: setFeeTo(treasury)");

  // --- 5) Deploy Router (UUPS proxy) ---
  const Router = await ethers.getContractFactory("PurDexRouter");
  const router = await upgrades.deployProxy(
    Router,
    [factoryAddr, wethAddr, pur],
    { kind: "uups", unsafeAllow: ["constructor"] }
  );
  await router.waitForDeployment();
  const routerAddr = await router.getAddress();
  const routerImpl = await upgrades.erc1967.getImplementationAddress(routerAddr);
  console.log("PurDexRouter (proxy):", routerAddr);

  // --- 6) Create the initial PUR/WETH pair ---
  await (await factory.createPair(pur, wethAddr)).wait();
  const pairAddr = await factory.getPair(pur, wethAddr);
  console.log("PUR/WETH Pair:", pairAddr);

  // --- 7) Deploy LP staking rewards (UUPS proxy) ---
  const rewardsDuration = Number(process.env.REWARDS_DURATION_SECONDS || "604800"); // 7 days
  const Staking = await ethers.getContractFactory("PurDexStakingRewards");
  const staking = await upgrades.deployProxy(
    Staking,
    [pairAddr, pur, rewardsDuration],
    { kind: "uups", unsafeAllow: ["constructor"] }
  );
  await staking.waitForDeployment();
  const stakingAddr = await staking.getAddress();
  const stakingImpl = await upgrades.erc1967.getImplementationAddress(stakingAddr);
  console.log("PurDexStakingRewards (proxy):", stakingAddr);

  // Give staking contract agent role so it can mint rewards (optional feature)
  const purToken = await ethers.getContractAt("PuriCoin", pur);
  await (await purToken.setAgent(stakingAddr, true)).wait();
  console.log("PuriCoin: setAgent(staking,true)");

  // --- 8) Deploy oracle router + lending pool (both UUPS proxies) ---
  const ethUsdFeed = process.env.ETH_USD_FEED || ethers.ZeroAddress;
  const Oracle = await ethers.getContractFactory("PurDexOracleRouter");
  const oracle = await upgrades.deployProxy(Oracle, [ethUsdFeed, navOracle || ethers.ZeroAddress], {
    kind: "uups",
    unsafeAllow: ["constructor"],
  });
  await oracle.waitForDeployment();
  const oracleAddr = await oracle.getAddress();
  const oracleImpl = await upgrades.erc1967.getImplementationAddress(oracleAddr);
  console.log("PurDexOracleRouter (proxy):", oracleAddr);

  const Lending = await ethers.getContractFactory("PurDexLendingPool");
  const lending = await upgrades.deployProxy(Lending, [pur, wethAddr, oracleAddr], {
    kind: "uups",
    unsafeAllow: ["constructor"],
  });
  await lending.waitForDeployment();
  const lendingAddr = await lending.getAddress();
  const lendingImpl = await upgrades.erc1967.getImplementationAddress(lendingAddr);
  console.log("PurDexLendingPool (proxy):", lendingAddr);

  // --- 8) Persist deployment info ---
  const extra = {
    WETH9: { address: wethAddr, constructorArguments: [] },
    PurDexPairImplementation: { address: pairImplAddr, constructorArguments: [] },
    PurDexPairBeacon: { address: pairBeaconAddr, constructorArguments: [pairImplAddr] },
    PurDexFactory: {
      address: factoryAddr,
      proxy: true,
      implementation: factoryImpl,
      initializerArguments: [treasury, pairBeaconAddr],
    },
    PurDexRouter: {
      address: routerAddr,
      proxy: true,
      implementation: routerImpl,
      initializerArguments: [factoryAddr, wethAddr, pur],
    },
    PurDexPair_PUR_WETH: { address: pairAddr, constructorArguments: [] },
    PurDexStakingRewards: {
      address: stakingAddr,
      proxy: true,
      implementation: stakingImpl,
      initializerArguments: [pairAddr, pur, rewardsDuration],
    },
    PurDexOracleRouter: {
      address: oracleAddr,
      proxy: true,
      implementation: oracleImpl,
      initializerArguments: [ethUsdFeed, navOracle || ethers.ZeroAddress],
    },
    PurDexLendingPool: {
      address: lendingAddr,
      proxy: true,
      implementation: lendingImpl,
      initializerArguments: [pur, wethAddr, oracleAddr],
      params: {
        variableRate: { base: "2%", slope: "20%" },
        collateral: "ETH-only",
        ltv: "50%",
        liquidationThreshold: "60%",
        liquidationBonus: "5%",
        feeTo: treasury,
      },
    },
  };

  mergeDeployment(file, dep, extra);
  console.log("Updated deployment file:", file);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
