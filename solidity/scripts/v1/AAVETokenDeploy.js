// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.

const {ethers} = require("hardhat");

async function main() {
    const [deployer1, deployer2, deployer3] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer1.address);
    const debtToken = await ethers.getContractFactory("Token");
    const Token = await debtToken.connect(deployer1).deploy("AAVE Token", "AAVE");
    console.log("AAVE Token address:", Token.target); // 0x82E7602d093149C1280D0a625B3b11fE4Ce66B0F
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });