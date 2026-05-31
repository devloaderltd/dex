import { expect } from "chai";
import { ethers } from "hardhat";

describe("PurDexRouter", function () {
  it("compiles and has no syntax errors", async function () {
    const Router = await ethers.getContractFactory("PurDexRouter");
    expect(Router).to.not.be.undefined;
  });
});
