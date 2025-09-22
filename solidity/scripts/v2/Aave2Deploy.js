const { ethers, upgrades } = require("hardhat");

async function main() {
    const [deployer1, deployer2, deployer3] = await ethers.getSigners();
    console.log("Aave Owner:", deployer1.address);
    console.log("Chainlink Owner:", deployer1.address);

    // 配置延迟时间（Sepolia需要更长时间）
    const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
    const DELAY_TIME = 10000; // 10秒

    // 等待交易确认的辅助函数
    async function waitForTransaction(transaction, confirmations = 1) {
        const receipt = await transaction.wait(confirmations);
        await delay(DELAY_TIME);
        return receipt;
    }

    try {
        // 部署Aave代币合约
        const aaveToken = await ethers.getContractFactory("Token");
        const AaveToken = await aaveToken.connect(deployer1).deploy("AAVE Token", "AAVE");
        await waitForTransaction(AaveToken.deploymentTransaction());
        console.log("Aave token address:", AaveToken.target);

        // 部署USDC代币合约
        const usdcDebtToken = await ethers.getContractFactory("Token");
        const USDCToken = await usdcDebtToken.connect(deployer1).deploy("USDC Token", "USDC");
        await waitForTransaction(USDCToken.deploymentTransaction());

        // mint USDC
        const mintTx1 = await USDCToken.mint(deployer2.address, BigInt(1000000000000000000 * 100000000));
        await waitForTransaction(mintTx1);
        console.log("USDC token address:", USDCToken.target);

        // 继续其他部署，确保每个交易都使用 waitForTransaction
        const toshiDebtToken = await ethers.getContractFactory("Token");
        const TOSHIToken = await toshiDebtToken.connect(deployer1).deploy("TOSHI Token", "TOSHI");
        await waitForTransaction(TOSHIToken.deploymentTransaction());

        // mint TOSHI
        const mintTx2 = await TOSHIToken.mint(deployer3.address, BigInt(1000000000000000000 * 100000000));
        await waitForTransaction(mintTx2);
        console.log("TOSHI token address:", TOSHIToken.target);

        // 部署DEGEN代币合约
        const degenDebtToken = await ethers.getContractFactory("Token");
        const DEGENToken = await degenDebtToken.connect(deployer1).deploy("DEGEN Token", "DEGEN");
        await waitForTransaction(DEGENToken.deploymentTransaction());

        // mint DEGEN
        const mintTx3 = await DEGENToken.mint(deployer3.address, BigInt(1000000000000000000 * 100000000));
        await waitForTransaction(mintTx3);
        console.log("DEGEN token address:", DEGENToken.target);

        // 部署chainlink合约
        const chainlink = await ethers.getContractFactory("Chainlink");
        const Chainlink = await chainlink.connect(deployer1).deploy();
        await waitForTransaction(Chainlink.deploymentTransaction());
        console.log("Chainlink address:", Chainlink.target);

        // 部署Aave2Pool（可升级合约）
        const Aave2Pool = await ethers.getContractFactory("Aave2Pool");
        const aave2Pool = await upgrades.deployProxy(
            Aave2Pool,
            [
                deployer1.address,
                await AaveToken.getAddress(),
                await USDCToken.getAddress(),
                await Chainlink.getAddress()
            ],
            {
                initializer: "initialize",
                kind: "uups"
            }
        );
        await aave2Pool.waitForDeployment();
        console.log("Aave pool proxy address:", await aave2Pool.getAddress());
        console.log("Aave pool implementation address:", await upgrades.erc1967.getImplementationAddress(await aave2Pool.getAddress()));
        await delay(DELAY_TIME);

        // 设置价格和参数
        const priceTx1 = await Chainlink.setTokenPrice(await USDCToken.getAddress(), ethers.parseUnits("1", 2));
        await waitForTransaction(priceTx1);

        const priceTx2 = await Chainlink.setTokenPrice(await DEGENToken.getAddress(), ethers.parseUnits("2", 2));
        await waitForTransaction(priceTx2);

        const priceTx3 = await Chainlink.setTokenPrice(await TOSHIToken.getAddress(), ethers.parseUnits("4", 2));
        await waitForTransaction(priceTx3);

        const collateralTx1 = await aave2Pool.setCollateral(await DEGENToken.getAddress(), 1000000, 800000, 600000);
        await waitForTransaction(collateralTx1);

        const collateralTx2 = await aave2Pool.setCollateral(await TOSHIToken.getAddress(), 1000000, 800000, 600000);
        await waitForTransaction(collateralTx2);

        const feeTx1 = await aave2Pool.setLiquidationPenaltyFeeRate4Protocol(50000);
        await waitForTransaction(feeTx1);

        const feeTx2 = await aave2Pool.setLiquidationPenaltyFeeRate4Cleaner(50000);
        await waitForTransaction(feeTx2);

        const interestTx = await aave2Pool.setInterestRate(100000);
        await waitForTransaction(interestTx);

        console.log("Aave2Pool deployed successfully!");

        // Aave Owner: 0xb052360268d7F2FA4Eb62eD1c6194257935C0BfE
        // Chainlink Owner: 0xb052360268d7F2FA4Eb62eD1c6194257935C0BfE
        // Aave token address: 0x3c3f96E280A11dB6b45ceED62054FaE2A7BA7521
        // USDC token address: 0x22244735041413ad0F0F2d2B4A4687B626B922Ba
        // TOSHI token address: 0x4533840185dF00119F5a3cD8F2379C0160CA875b
        // DEGEN token address: 0x0A38A1Ef0fae4DC3AAd1A5FD419CBc4687A2C05C
        // Chainlink address: 0x1e38DCE5381c91F21842a6A80E94e0a06bA4A67A
        // Aave pool proxy address: 0xC0AF09A3986b237Faf6a66AC94C49376953F93DA
        // Aave pool implementation address: 0xfd7FE61173872108F08292a17e2DC82a7D10aB90
        // Aave2Pool deployed successfully!
    } catch (error) {
        console.error("Deployment failed:", error);
        throw error;
    }
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });