// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.

const {ethers} = require("hardhat");

async function main() {
    const [deployer1, deployer2, deployer3] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer1.address);
    const chainlink = await ethers.getContractFactory("Chainlink");
    const Chainlink = await chainlink.connect(deployer1).deploy();
    console.log("Chainlink address:", Chainlink.target); // 0x75511991BDD25886d9f6fe229303B5c0eA2c3D0C
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });