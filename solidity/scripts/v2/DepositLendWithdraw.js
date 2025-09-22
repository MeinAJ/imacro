const {ethers} = require("hardhat");

const Aave2PoolAddress = "0xC0AF09A3986b237Faf6a66AC94C49376953F93DA";
const USDCAddress = "0x22244735041413ad0F0F2d2B4A4687B626B922Ba";

async function main() {
    const [deployer1, deployer2, deployer3] = await ethers.getSigners();

    console.log("Using account:", deployer1.address);
    console.log("Account balance:", (await ethers.provider.getBalance(deployer1.address)).toString());

    // 1. 获取已部署的USDC代币合约实例
    const USDCToken = await ethers.getContractAt("Token", USDCAddress);
    console.log("USDC Token address:", await USDCToken.getAddress());

    // 2. 首先授权 Aave2Pool 合约可以操作 deployer2 的 USDC
    console.log("Approving USDC for Aave2Pool...");
    const approveTx = await USDCToken.connect(deployer2).approve(
        Aave2PoolAddress,
        2n ** 256n - 1n  // 使用 ethers 提供的最大uint256值
    );
    await approveTx.wait();
    console.log("Approval confirmed");

    // 3. 获取已部署的Aave2Pool合约实例
    const Aave2Pool = await ethers.getContractAt("Aave2Pool", Aave2PoolAddress);
    console.log("Aave2Pool contract address:", await Aave2Pool.getAddress());

    // 4. 准备存款参数
    const depositAmount = ethers.parseUnits("1000", 18); // 假设存入1000 USDC，根据USDC的实际小数位调整（USDC通常是6位小数）
    console.log("Deposit amount:", depositAmount.toString());

    // 5. 调用depositLend方法
    console.log("Calling depositLend...");
    const depositTx = await Aave2Pool.connect(deployer2).depositLend(
        depositAmount
    );

    // 等待交易确认
    await depositTx.wait();

    // 6.查看存款后的余额
    const totalLend = await Aave2Pool.connect(deployer1).getTotalLend();
    console.log("total lend amount:", totalLend)

    // 7.查看存款后的最新更新时间
    const userLendLastTime = await Aave2Pool.connect(deployer1).getUserLendLastTime(deployer2.address);
    console.log("user lend last time:", userLendLastTime)

    // withdraw 部分
    // 8. 准备取款参数
    const withdrawAmount = ethers.parseUnits("500", 18); // 假设取出500 USDC，根据USDC的实际小数位调整
    console.log("Withdraw amount:", withdrawAmount.toString());

    // 9. 调用withdrawLend方法
    console.log("Calling withdrawLend...");
    const withdrawTx = await Aave2Pool.connect(deployer2).depositLendWithdraw(
        withdrawAmount
    );

    // 等待交易确认
    await withdrawTx.wait();

    // 10.查看取款后的余额
    const totalLendAfterWithdraw = await Aave2Pool.connect(deployer1).getTotalLend();
    console.log("total lend amount after withdraw:", totalLendAfterWithdraw)

    // 11.查看取款后的最新更新时间
    const userLendLastTimeAfterWithdraw = await Aave2Pool.connect(deployer1).getUserLendLastTime(deployer2.address);
    console.log("user lend last time after withdraw:", userLendLastTimeAfterWithdraw)
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });