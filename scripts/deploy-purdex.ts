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
  const [deployer] = await ethers.getSigners();
  console.log(`Network: ${network.name}`);
  console.log(`Deployer: ${deployer.address}`);

  const { file, json: dep } = loadDeployment(network.name);
  const pur = dep.contracts?.PuriCoin?.address;
  const identityRegistry = dep.contracts?.IdentityRegistry?.address;
  const navOracle = dep.contracts?.NAVOracle?.address;
  if (!pur || !identityRegistry) {
    throw new Error("deployments/<network>.json must include PuriCoin and IdentityRegistry addresses");
  }

  // As requested: use the deployer as the treasury + admin.
  const treasury = deployer.address;
  console.log(`Treasury (feeTo + admin): ${treasury}`);

  // --- 1) Deploy KYC Manager (UUPS proxy) ---
  const kycSigner = process.env.KYC_SIGNER_ADDRESS || deployer.address;
  const KYC = await ethers.getContractFactory("PurDexKYCManager");
  const kyc = await upgrades.deployProxy(KYC, [identityRegistry, kycSigner], {
    kind: "uups",
    // We intentionally keep a constructor that calls _disableInitializers() to lock the implementation.
    // OZ docs recommend this pattern and allow it via the unsafe-allow option.
    unsafeAllow: ["constructor"],
  });
  await kyc.waitForDeployment();
  const kycAddr = await kyc.getAddress();
  const kycImpl = await upgrades.erc1967.getImplementationAddress(kycAddr);
  console.log("PurDexKYCManager:", kycAddr);

  // Make KYC manager a KYCAgent on your already deployed IdentityRegistry
  const idReg = await ethers.getContractAt("IdentityRegistry", identityRegistry);
  const txAgent = await idReg.setKYCAgent(kycAddr, true);
  await txAgent.wait();
  console.log("IdentityRegistry: setKYCAgent(KYCManager,true)");

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
  const factory = await upgrades.deployProxy(Factory, [treasury, kycAddr, pairBeaconAddr], {
    kind: "uups",
    unsafeAllow: ["constructor"],
  });
  await factory.waitForDeployment();
  const factoryAddr = await factory.getAddress();
  const factoryImpl = await upgrades.erc1967.getImplementationAddress(factoryAddr);
  console.log("PurDexFactory (proxy):", factoryAddr);

  // Wire factory into KYC manager (so Factory can auto-register pairs)
  const txSetFactory = await kyc.setFactory(factoryAddr);
  await txSetFactory.wait();
  console.log("KYCManager: setFactory(factory)");

  // feeTo -> treasury
  await (await factory.setFeeTo(treasury)).wait();
  console.log("Factory: setFeeTo(treasury)");

  // --- 5) Deploy Router (UUPS proxy) ---
  const Router = await ethers.getContractFactory("PurDexRouter");
  const router = await upgrades.deployProxy(
    Router,
    [factoryAddr, wethAddr, pur, identityRegistry],
    { kind: "uups", unsafeAllow: ["constructor"] }
  );
  await router.waitForDeployment();
  const routerAddr = await router.getAddress();
  const routerImpl = await upgrades.erc1967.getImplementationAddress(routerAddr);
  console.log("PurDexRouter (proxy):", routerAddr);

  // Optional: register core DEX contracts as verified (not required, but harmless)
  await (await kyc.registerDexContract(factoryAddr)).wait();
  await (await kyc.registerDexContract(routerAddr)).wait();
  await (await kyc.registerDexContract(wethAddr)).wait();
  console.log("KYCManager: registered factory/router/weth as verified addresses");

  // --- 6) Create the initial PUR/WETH pair (auto-registered by the factory hook) ---
  await (await factory.createPair(pur, wethAddr)).wait();
  const pairAddr = await factory.getPair(pur, wethAddr);
  console.log("PUR/WETH Pair:", pairAddr);

  // --- 7) Deploy LP staking rewards (UUPS proxy) ---
  const rewardsDuration = Number(process.env.REWARDS_DURATION_SECONDS || "604800"); // 7 days
  const Staking = await ethers.getContractFactory("PurDexStakingRewards");
  const staking = await upgrades.deployProxy(
    Staking,
    [pairAddr, pur, identityRegistry, rewardsDuration],
    { kind: "uups", unsafeAllow: ["constructor"] }
  );
  await staking.waitForDeployment();
  const stakingAddr = await staking.getAddress();
  const stakingImpl = await upgrades.erc1967.getImplementationAddress(stakingAddr);
  console.log("PurDexStakingRewards (proxy):", stakingAddr);

  // Register staking contract as verified (so it can hold/mint PUR)
  await (await kyc.registerDexContract(stakingAddr)).wait();

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
  const lending = await upgrades.deployProxy(Lending, [pur, wethAddr, identityRegistry, oracleAddr], {
    kind: "uups",
    unsafeAllow: ["constructor"],
  });
  await lending.waitForDeployment();
  const lendingAddr = await lending.getAddress();
  const lendingImpl = await upgrades.erc1967.getImplementationAddress(lendingAddr);
  console.log("PurDexLendingPool (proxy):", lendingAddr);

  await (await kyc.registerDexContract(lendingAddr)).wait();
  console.log("KYCManager: registered lending pool as verified address");

  // --- 8) Persist deployment info ---
  const extra = {
    PurDexKYCManager: {
      address: kycAddr,
      proxy: true,
      implementation: kycImpl,
      initializerArguments: [identityRegistry, kycSigner],
    },
    WETH9: { address: wethAddr, constructorArguments: [] },
    PurDexPairImplementation: { address: pairImplAddr, constructorArguments: [] },
    PurDexPairBeacon: { address: pairBeaconAddr, constructorArguments: [pairImplAddr] },
    PurDexFactory: {
      address: factoryAddr,
      proxy: true,
      implementation: factoryImpl,
      initializerArguments: [treasury, kycAddr, pairBeaconAddr],
    },
    PurDexRouter: {
      address: routerAddr,
      proxy: true,
      implementation: routerImpl,
      initializerArguments: [factoryAddr, wethAddr, pur, identityRegistry],
    },
    PurDexPair_PUR_WETH: { address: pairAddr, constructorArguments: [] },
    PurDexStakingRewards: {
      address: stakingAddr,
      proxy: true,
      implementation: stakingImpl,
      initializerArguments: [pairAddr, pur, identityRegistry, rewardsDuration],
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
      initializerArguments: [pur, wethAddr, identityRegistry, oracleAddr],
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
