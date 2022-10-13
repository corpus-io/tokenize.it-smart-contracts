// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from "hardhat";

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  const CorpusToken = await ethers.getContractFactory("CorpusToken");
  
  const signers = await ethers.getSigners();

// address _admin, AllowList _allowList, string memory _name, string memory _symbol
  const corpusToken = await CorpusToken.deploy(signers[0].address, signers[1].address, 0x0, 'Corpus Token', 'COT');

  await corpusToken.deployed();

  console.log("CorpusToken deployed to:", corpusToken.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
