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
    const receipt = await depositTx.wait();

    // 6.查看存款后的余额
    const totalLend = await Aave2Pool.connect(deployer1).getTotalLend();
    console.log("total lend amount:", totalLend)

    // 7.查看存款后的最新更新时间
    const userLendLastTime = await Aave2Pool.connect(deployer1).getUserLendLastTime(deployer2.address);
    console.log("user lend last time:", userLendLastTime)

    // 检查日志
    if (receipt && receipt.logs) {
        console.log(`日志数量: ${receipt.logs.length}`);

        // 1. 首先，计算 DepositLend 事件签名的 Keccak256 哈希（假设事件定义为 DepositLend(address indexed user, uint256 amount)）
        // 事件签名要注意参数类型和空格，顺序必须与合约中定义的事件完全一致
        const eventSignature = "DepositLend(address,address,uint256)";
        const eventTopic = ethers.keccak256(ethers.toUtf8Bytes(eventSignature));
        console.log(`计算的 DepositLend 事件主题 (topic[0]): ${eventTopic}`);

        // 2. 遍历所有日志，寻找匹配的 topic[0]
        for (let i = 0; i < receipt.logs.length; i++) {
            const log = receipt.logs[i];
            console.log(`\n--- 日志索引 ${i} ---`);
            console.log(`日志地址: ${log.address}`); // 发出事件的合约地址
            console.log(`主题数组 (topics): ${JSON.stringify(log.topics)}`);
            console.log(`数据 (data): ${log.data}`);

            // 检查当前日志的 topics[0] 是否与我们计算的事件签名哈希匹配
            if (log.topics[0] === eventTopic) {
                console.log(`🎉 找到 DepositLend 事件！位于日志索引 ${i}。`);

                // 3. 解码日志数据 (如果需要解析未索引的参数)
                // 你需要提供事件的 ABI 片段来解码
                const iface = new ethers.Interface([
                    "event DepositLend(address indexed user, address pool, uint256 amount)"
                ]);
                const parsedLog = iface.parseLog(log);
                console.log("解析后的事件参数:", parsedLog.args);

                // parsedLog.args 是一个对象，包含解码后的事件参数
                // 例如：parsedLog.args.user, parsedLog.args.amount
            }
        }
    }

    console.log("Deposit transaction confirmed in block:", receipt.blockNumber);
    console.log("Transaction hash:", receipt.hash);
    console.log("Deposit completed successfully!");

    /**
     * Using account: 0xb052360268d7F2FA4Eb62eD1c6194257935C0BfE
     * Account balance: 3831885915414820687
     * USDC Token address: 0xa859487335500Ca73525588eBe8B724185AcE3df
     * Approving USDC for Aave2Pool...
     * Approval confirmed
     * Aave2Pool contract address: 0x37BFA80E1Ad07BA04bE4D7e49497D639e018352e
     * Deposit amount: 1000000000000000000000
     * Calling depositLend...
     * Deposit transaction confirmed in block: 9226682
     * Transaction hash: 0x98a1abd1559c9a5f9976118be3e02aefb98e107a15ba52b0de00a29433ac591d
     * Deposit completed successfully!
     */
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });