# PurDex (PuriCoin DEX) + Pools (Hardhat)

This repo extends your existing **PuriCoin (PUR)** permissioned token project (ERC3643-style KYC gating) with:

- **PurDex AMM** (UniswapV2-style constant product): Factory / Pair / Router
- **Auto-KYC gateway** (`PurDexKYCManager`) using **EIP-712 signatures**
- **LP staking / liquidity mining** (`PurDexStakingRewards`) paying rewards in **PUR**
- **Minimal lending pool** (`PurDexLendingPool`) where:
  - Suppliers deposit **PUR** to earn interest
  - Borrowers lock **ETH (WETH)** collateral and borrow **PUR**

### Upgradeability (your request)

- **Core contracts** (`PurDexKYCManager`, `PurDexFactory`, `PurDexRouter`, `PurDexOracleRouter`, `PurDexLendingPool`, `PurDexStakingRewards`) are deployed behind **OpenZeppelin UUPS proxies**.
- **All AMM pairs** are deployed behind **BeaconProxy** instances. A single **beacon** controls the pair implementation. Upgrading the beacon upgrades **every pair** at once.

“Save everything in your database” is handled by these registries:

- `deployments/<network>.json` (human readable)
- `.openzeppelin/<network>.json` (OpenZeppelin Upgrades plugin registry)

> ⚠️ These contracts are a *starter implementation* for development / testnet use.
> Do **not** use in production without professional security review + audits.

---

## Your already deployed Sepolia contracts

You already have `deployments/sepolia.json` with:

- `IdentityRegistry`: `0x252CB7b4677AAeC7867bAFC3FD7A33EaceE9B922`
- `BasicCompliance`: `0x5Fa97756B263C1826A1912818C2365b8AafdBC52`
- `PuriCoin`: `0xB682Fd3274CD531D8171C621eCa35D7a970062FD`
- `NAVOracle`: `0xE2eCeaAEaa6A017BbD374eA59F053DF9426357b7`
- `ProofRegistry`: `0xB8052c4f88701b2147BB1A89e5Df128f87dAa7aa`

The DEX deployment script reads this file and **deploys new DEX/pool contracts wired to these addresses**.

---

## Contracts added

### 1) Auto-KYC

**`contracts/kyc/PurDexKYCManager.sol`**

- You set this contract as a `KYCAgent` on `IdentityRegistry`.
- Your backend performs KYC off-chain, then signs an EIP-712 message.
- User submits the signature on-chain to self-register as verified.

Key functions:

- `verifySelfWithSig(country, deadline, sig)`
- `verifyWithSig(user, country, deadline, sig)`
- `registerDexContract(contractAddr)`

### 2) AMM / DEX

**`contracts/dex/`**

- `PurDexFactory`: deploys Pair contracts and (optionally) auto-registers them as verified via `PurDexKYCManager`.
- `PurDexPair`: constant-product pool with a 0.30% swap fee.
- `PurDexRouter`: add/remove liquidity + swaps, with a **KYC gate** for any swap/liquidity path that touches PUR.
- `WETH9`: wrapped ETH used by the router.

### 3) LP Rewards

**`contracts/rewards/PurDexStakingRewards.sol`**

- Stake LP token and earn PUR.
- Owner starts reward periods with `notifyRewardAmount(reward)`.
- It will **try to mint** PUR into itself (requires `setAgent(staking,true)` on `PuriCoin`).

### 4) Lending / Borrowing

**`contracts/lending/PurDexLendingPool.sol`**

- Supply PUR → earn interest.
- Deposit ETH collateral (stored as WETH) → borrow PUR.
- Includes basic liquidation logic.

**`contracts/lending/PurDexOracleRouter.sol`**

- ETH/USD from Chainlink (optional)
- PUR/USD from your NAVOracle (optional)
- Can fall back to manual prices.

---

## Deploying the DEX + Pools on Sepolia

### 1) Environment

Create `.env` (see `.env.example`):

```bash
SEPOLIA_RPC_URL="..."
SEPOLIA_PRIVATE_KEY="0x..."  # MUST be the same wallet that owns IdentityRegistry + PuriCoin (your deployer)

# Optional (for oracle router): Sepolia ETH/USD Chainlink feed address
ETH_USD_FEED="0x..."

# Optional: the address that signs KYC approvals
KYC_SIGNER_ADDRESS="0x..."   # defaults to deployer if omitted

# Optional: rewards duration
REWARDS_DURATION_SECONDS="604800" # 7 days
```

### 2) Install + deploy

```bash
npm i
npm run build

# Deploy PurDex + pools (reads deployments/sepolia.json)
npm run deploy:purdex:sepolia
```

After deployment, your `deployments/sepolia.json` is updated with new entries:

- `PurDexKYCManager`
- `WETH9`
- `PurDexFactory`
- `PurDexRouter`
- `PurDexPair_PUR_WETH`
- `PurDexStakingRewards`
- `PurDexOracleRouter`
- `PurDexLendingPool`

Each proxy entry also stores its **implementation** address (needed for upgrades).

---

## KYC flow (how the “auto verify” works)

### Production idea

1) User completes KYC on your website.
2) Your backend signs an **EIP-712 typed message** approving the user.
3) The user calls `verifySelfWithSig(...)` on-chain with the signature.
4) Because the DEX router + pools require `IdentityRegistry.isVerified(user)`, the user can now trade/borrow/earn.

### Local test signing

Generate a signature (example):

```bash
USER=0xYourWallet COUNTRY=18 DEADLINE_SECONDS=3600 KYC_SIGNER_PRIVATE_KEY=0x... \
  npx hardhat run scripts/kyc/sign-kyc.ts --network sepolia
```

Then submit it:

```bash
USER=0xYourWallet COUNTRY=18 DEADLINE=1700000000 SIGNATURE=0x... \
  npx hardhat run scripts/kyc/verify-kyc.ts --network sepolia
```

---

## How front-end should interact

### DEX swaps

Use **Router**:

- ETH → PUR: `swapExactETHForTokens(amountOutMin, [WETH, PUR], to, deadline)`
- PUR → ETH: `swapExactTokensForETH(amountIn, amountOutMin, [PUR, WETH], to, deadline)`
- Token → Token: `swapExactTokensForTokens(amountIn, amountOutMin, [tokenIn, ..., tokenOut], to, deadline)`

Convenience (no `path` needed):

- ETH → PUR: `swapExactETHForPUR(amountOutMin, to, deadline)`
- PUR → ETH: `swapExactPURForETH(amountIn, amountOutMin, to, deadline)`

✅ If the `path` includes **PUR**, router enforces:

- `IdentityRegistry.isVerified(msg.sender) == true`
- `IdentityRegistry.isVerified(to) == true`

### Add/Remove liquidity

- `addLiquidity(PUR, WETH, ...)`
- `addLiquidityETH(PUR, ...)`
- `removeLiquidity(PUR, WETH, ...)`

Same rule: if the pair contains PUR, the router requires verified addresses.

### LP rewards

1) User gets LP tokens by adding liquidity.
2) User stakes LP tokens in `PurDexStakingRewards.stake(amount)`.
3) User claims via `getReward()`.

Owner starts reward periods:

- `PurDexStakingRewards.notifyRewardAmount(reward)`

If you enabled minting rewards (default in contract), you must:

- `PuriCoin.setAgent(PurDexStakingRewards, true)`
- Ensure the staking contract is verified in `IdentityRegistry` (done by deploy script)

### Lending pool

**Supplier:**

- Approve PUR to LendingPool
- `supply(amount)`
- `withdraw(shares)`

**Borrower:**

- `depositCollateralETH()` (send ETH)
- `borrow(amountPur)`
- `repay(amountPur)`
- `withdrawCollateralETH(amountWeth)` (only if still healthy)

Prices:

- `PurDexOracleRouter` can read Chainlink ETH/USD + NAVOracle PUR/USD
- Or use manual fallback via `setManualEthUsdPrice()` / `setManualPurUsdPrice()`

---

## ABI export

To export ABIs for your frontend:

```bash
npm run export-abis
```

---

## Notes / next improvements

If you want to take this closer to “real Aave”:

- Add multi-asset markets (not only ETH collateral and PUR borrowing)
- Add isolation mode / caps
- Add eMode / better interest rate model
- Add flashloans
- Add governance for params
- Add TWAP price oracle from AMM

If you want stricter compliance:

- Block LP token transfers to non-verified addresses
- Force all routers to call KYC manager before allowing any pool interaction

---

## Upgrading later (examples)

UUPS proxy upgrades:

```bash
npx hardhat run scripts/upgrade/upgrade-router.ts --network sepolia
npx hardhat run scripts/upgrade/upgrade-factory.ts --network sepolia
npx hardhat run scripts/upgrade/upgrade-lending.ts --network sepolia
```

Upgrade ALL pairs at once (beacon):

```bash
npx hardhat run scripts/upgrade/upgrade-pair-beacon.ts --network sepolia
```




I didn’t include a **full security testing suite** by default. What you have now (smoke + fork E2E tests) proves **functionality**, but it’s not a security audit.

Below is a practical “security test pack” you can add and run with simple scripts.

----------

## Security testing stack (best ROI)

### 1) Static analysis (find common bugs fast)

-   **Slither** (best first pass)
    
-   **solhint** (linting)
    
-   **openzeppelin upgrades validation** (upgrade safety checks)
    
-   **dependency audit** (`npm audit`)
    

### 2) Dynamic tests (catch edge cases)

-   **hardhat-coverage** (ensure tests cover critical paths)
    
-   **fuzz / invariant testing** (best is Foundry or Echidna)
    

### 3) (Optional) symbolic analysis

-   **Mythril** (useful but slower/noisier)
    

----------

# A) Add npm scripts (copy into `package.json`)

Add these under `"scripts"`:

{  
 "scripts": {  
 "lint:sol": "solhint \"contracts/**/*.sol\"",  
 "lint:ts": "eslint \"{scripts,test}/**/*.{ts,js}\"",  
 "test": "hardhat test",  
 "test:fork": "hardhat test test/fork --network hardhat",  
 "coverage": "hardhat coverage",  
 "deps:audit": "npm audit --audit-level=high",  
 "slither:docker": "docker run --rm -v \"%cd%:/src\" -w /src trailofbits/eth-security-toolbox slither . --config-file slither.config.json",  
 "mythril:docker": "docker run --rm -v \"%cd%:/src\" -w /src mythril/myth analyze contracts --solc-json /src/mythril.solc.json",  
 "foundry:invariant": "forge test --match-path test/invariant/** -vvv"  
 }  
}

> Notes:
> 
> -   `slither:docker` works on Windows if Docker Desktop is installed.
>     
> -   `foundry:invariant` requires Foundry installed (recommended for fuzz/invariants).
>     

----------

# B) Install dev tools (Hardhat side)

npm i -D solhint eslint @typescript-eslint/parser @typescript-eslint/eslint-plugin hardhat-gas-reporter solidity-coverage

Then add to `hardhat.config.ts`:

import  "solidity-coverage";

Now run:

npm run coverage  
npm run lint:sol  
npm run deps:audit

----------

# C) Slither setup (best security quick scan)

### 1) Create `slither.config.json` in project root

{  
 "filter_paths": ["node_modules", "artifacts", "cache", "typechain-types"],  
 "solc_remaps": [  
  "@openzeppelin=node_modules/@openzeppelin"  
 ]  
}

### 2) Run Slither

npm run slither:docker

This will highlight:

-   reentrancy possibilities
    
-   dangerous external calls
    
-   uninitialized storage (upgradeability)
    
-   incorrect ERC20 usage patterns
    
-   etc.
    

----------

# D) Upgrade-safety checks (important for UUPS/Beacon)

### 1) Add a validation script: `scripts/security/validate-upgrades.ts`

import { ethers, upgrades } from  "hardhat";  
import  *  as  fs  from  "fs";  
  
function  loadDeployments() {  
  const  dep  =  JSON.parse(fs.readFileSync("deployments/sepolia.json", "utf8"));  
  return  dep.contracts;  
}  
  
async  function  main() {  
  const  dep  =  loadDeployments();  
  
  // Validate implementations against current storage layout  
  // (This catches storage layout breaking changes.)  
  await  upgrades.validateImplementation(await  ethers.getContractFactory("PurDexRouter"), { kind: "uups" });  
  await  upgrades.validateImplementation(await  ethers.getContractFactory("PurDexFactory"), { kind: "uups" });  
  await  upgrades.validateImplementation(await  ethers.getContractFactory("PurDexKYCManager"), { kind: "uups" });  
  await  upgrades.validateImplementation(await  ethers.getContractFactory("PurDexStakingRewards"), { kind: "uups" });  
  await  upgrades.validateImplementation(await  ethers.getContractFactory("PurDexOracleRouter"), { kind: "uups" });  
  await  upgrades.validateImplementation(await  ethers.getContractFactory("PurDexLendingPool"), { kind: "uups" });  
  
  console.log("✅ Upgrade implementations validated (UUPS).");  
  
  // If you upgrade Pair via beacon, validate Pair impl too:  
  await  upgrades.validateImplementation(await  ethers.getContractFactory("PurDexPair"), { kind: "beacon" });  
  console.log("✅ Pair implementation validated (Beacon).");  
}  
  
main().catch((e) => {  
  console.error(e);  
  process.exit(1);  
});

### 2) Add npm script

"validate:upgrades": "hardhat run scripts/security/validate-upgrades.ts"

Run:

npm run validate:upgrades

----------

# E) Fuzz / invariant testing (recommended)

Hardhat itself isn’t great for fuzzing. The best practice is:

✅ Keep Hardhat for deploy/scripts  
✅ Add **Foundry** only for fuzz/invariants (it can live in the same repo)

### 1) Install Foundry

-   Windows: easiest in **WSL2** (Ubuntu).  
    (Foundry on native Windows is improving, but WSL2 is still the smoothest.)
    

### 2) Add minimal invariant tests

Create folder:

test/invariant/

Example invariant ideas (what to test)

-   **DEX Pair**:
    
    -   swaps don’t allow draining reserves
        
    -   liquidity mint/burn keeps reserves consistent
        
-   **Lending**:
    
    -   user can’t borrow above max LTV
        
    -   repay never increases debt
        
-   **KYC**:
    
    -   if receiver not verified, PUR transfer paths revert
        

If you want, I’ll generate **real invariant test files** for your exact contracts (Pair, Router, Lending), but I need your final contract names and function signatures as they exist in your repo.

Run invariants:

npm run foundry:invariant

----------

# F) “Security test run” checklist (what to run before mainnet)

Run these every release:

npm run build  
npm test  
npm run test:fork  
npm run coverage  
npm run validate:upgrades  
npm run lint:sol  
npm run slither:docker  
npm run deps:audit

Optional:

npm run mythril:docker  
npm run foundry:invariant

----------

## If you want, I can tailor this to your repo in 1 shot

If you paste your `contracts/` tree (just filenames) or upload the zip you’re using now, I’ll give you:

-   a ready `package.json` scripts block
    
-   `slither.config.json`
    
-   a few **real** invariants (Pair + Lending + KYC) that match your contract names exactly.
# dex
