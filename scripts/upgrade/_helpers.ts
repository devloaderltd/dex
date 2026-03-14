import * as fs from "fs";
import * as path from "path";
import { network } from "hardhat";

export type DeploymentsFile = {
  network: string;
  deployedAt?: string;
  contracts: Record<string, any>;
};

export function loadDeployments(): DeploymentsFile {
  const file = path.join(__dirname, "..", "..", "deployments", `${network.name}.json`);
  if (!fs.existsSync(file)) {
    throw new Error(`Missing deployments file: ${file}`);
  }
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

export function saveDeployments(data: DeploymentsFile) {
  const file = path.join(__dirname, "..", "..", "deployments", `${network.name}.json`);
  fs.writeFileSync(file, JSON.stringify(data, null, 2));
}

export function mustGetAddress(dep: DeploymentsFile, key: string): string {
  const entry = dep.contracts[key];
  if (!entry?.address) throw new Error(`Missing address for ${key} in deployments/${network.name}.json`);
  return entry.address;
}
