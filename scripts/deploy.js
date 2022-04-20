async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await deployer.getBalance()).toString());

  
  // Get the ContractFactories and Signers here.
  const NFT = await ethers.getContractFactory("NFT"); // ContractFactory is a Library for interactions with ethereum nodes, the await is used because blockchain is asynchronous (promise)
  const Marketplace = await ethers.getContractFactory("Marketplace");
  // deploy contracts
  const marketplace = await Marketplace.deploy(1); //1 is the fee percent, this deploys the marketplace smart contract
  const nft = await NFT.deploy(); //Used to deploy the NFT smart contract
  // Save copies of each contracts abi and address to the frontend.
  saveFrontendFiles(marketplace , "Marketplace");
  saveFrontendFiles(nft , "NFT");
}

function saveFrontendFiles(contract, name) {
  const fs = require("fs");
  const contractsDir = __dirname + "/../../frontend/contractsData";
  //This is used to store the smart contract address
  if (!fs.existsSync(contractsDir)) {
    fs.mkdirSync(contractsDir);
  }

  //This is used to store the smart contract abi
  fs.writeFileSync(
    contractsDir + `/${name}-address.json`,
    JSON.stringify({ address: contract.address }, undefined, 2)
  );

  const contractArtifact = artifacts.readArtifactSync(name);

  fs.writeFileSync(
    contractsDir + `/${name}.json`,
    JSON.stringify(contractArtifact, null, 2)
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
