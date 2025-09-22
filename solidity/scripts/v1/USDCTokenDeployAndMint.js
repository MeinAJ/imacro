// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.

const {ethers} = require("hardhat");

async function main() {
    const [deployer1,deployer2,deployer3] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer1.address);
    const debtToken = await ethers.getContractFactory("Token");
    const Token = await debtToken.connect(deployer1).deploy("USDC Token", "USDC");
    console.log("USDC Token address:", Token.target); // 0xd31919FacBBe9Bf1f0884fB37dd4A234429Fb76a
    // 等待部署交易确认！！！
    console.log("Waiting for deployment transaction to be confirmed...");
    await Token.deploymentTransaction().wait(); // 关键：等待部署交易确认
    // mint tokens
    await Token.mint(deployer1.address, BigInt(1000000000000000000 * 100000000));
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });