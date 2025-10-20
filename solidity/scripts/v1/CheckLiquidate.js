const {ethers} = require("hardhat");

const Aave2PoolAddress = "0xC0AF09A3986b237Faf6a66AC94C49376953F93DA";
const USDCAddress = "0x22244735041413ad0F0F2d2B4A4687B626B922Ba";
const DEGENAddress = "0x0A38A1Ef0fae4DC3AAd1A5FD419CBc4687A2C05C";

async function main() {
    const [deployer1, deployer2, deployer3] = await ethers.getSigners();

    console.log("Using account:", deployer1.address);
    console.log("Account balance:", (await ethers.provider.getBalance(deployer1.address)).toString());

    // 1. 获取已部署的USDC代币合约实例
    const USDCToken = await ethers.getContractAt("Token", USDCAddress);
    console.log("USDC Token address:", await USDCToken.getAddress());

    const DEGENToken = await ethers.getContractAt("Token", DEGENAddress);
    console.log("DEGEN Token address:", await DEGENToken.getAddress());

    // 2. 获取已部署的Aave2Pool合约实例
    const Aave2Pool = await ethers.getContractAt("Aave2Pool", Aave2PoolAddress);
    console.log("Aave2Pool contract address:", await Aave2Pool.getAddress());

    {
        // 首先授权 Aave2Pool 合约可以操作 deployer2 的 USDC
        const approveTx = await USDCToken.connect(deployer2).approve(
            await Aave2Pool.getAddress(),
            2n ** 256n - 1n
        );
        await approveTx.wait();
    }

    {
        // 然后调用 depositLend
        const tx1 = await Aave2Pool.connect(deployer2).depositLend(ethers.parseUnits("1000", 18));
        await tx1.wait();
    }

    {
        // 然后调用 depositLend
        const tx3 = await Aave2Pool.connect(deployer2).depositLend(ethers.parseUnits("1000", 18));
        await tx3.wait();
    }

    {
        // 首先授权 Aave2Pool 合约可以操作 deployer3 的 USDC
        const approveTx = await DEGENToken.connect(deployer3).approve(
            await Aave2Pool.getAddress(),
            2n ** 256n - 1n
        );
        await approveTx.wait();
    }

    // 借100个DEGEN，能借出200 * 0.6 = 120个usdc
    {
        const tx = await Aave2Pool.connect(deployer3).depositBorrow(
            await DEGENToken.getAddress(),
            ethers.parseUnits("100", 18) // 100个DEGEN，能借120个usdc
        )
        await tx.wait();
    }

    // 先检查一遍清算逻辑
    {
        const addresses = await Aave2Pool.checkLiquidate(
            await DEGENToken.getAddress(),
        );
        console.log("checkLiquidate addresses:", addresses);
    }

    // 降低degen的价格到1.4，触发清算逻辑
    {
        const tx = await Chainlink.setTokenPrice(await DEGENToken.getAddress(), ethers.parseUnits("1.4", 2));
        await tx.wait();
    }

    // 再检查一遍清算逻辑
    {
        const addresses = await Aave2Pool.checkLiquidate(
            await DEGENToken.getAddress(),
        );
        console.log("checkLiquidate addresses:", addresses);
    }

    // 降低degen的价格到1.6，不会触发清算逻辑
    {
        const tx = await Chainlink.setTokenPrice(await DEGENToken.getAddress(), ethers.parseUnits("1.6", 2));
        await tx.wait();
    }

    // 再检查一遍清算逻辑
    {
        const addresses = await Aave2Pool.checkLiquidate(
            await DEGENToken.getAddress(),
        );
        console.log("checkLiquidate addresses:", addresses);
    }
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });