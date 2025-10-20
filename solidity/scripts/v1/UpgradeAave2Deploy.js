const {ethers, upgrades} = require("hardhat");

// Aave Owner: 0xb052360268d7F2FA4Eb62eD1c6194257935C0BfE
// Chainlink Owner: 0xb052360268d7F2FA4Eb62eD1c6194257935C0BfE
// Aave token address: 0x3c3f96E280A11dB6b45ceED62054FaE2A7BA7521
// USDC token address: 0x22244735041413ad0F0F2d2B4A4687B626B922Ba
// TOSHI token address: 0x4533840185dF00119F5a3cD8F2379C0160CA875b
// DEGEN token address: 0x0A38A1Ef0fae4DC3AAd1A5FD419CBc4687A2C05C
// Chainlink address: 0x1e38DCE5381c91F21842a6A80E94e0a06bA4A67A
// Aave pool proxy address: 0xC0AF09A3986b237Faf6a66AC94C49376953F93DA
// Aave pool implementation address: 0x1a3FdB0eE3Bd19460Bbe3968C56888d1B7deD90f

async function main() {
    console.log("Starting Aave2Pool upgrade...");

    const [deployer] = await ethers.getSigners();
    console.log("Upgrading with account:", deployer.address);

    // 添加延迟函数
    const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
    await delay(2000);

    // 1. 首先获取当前的代理合约地址
    const proxyAddress = "0xC0AF09A3986b237Faf6a66AC94C49376953F93DA";
    console.log("Proxy address:", proxyAddress);

    // 2. 获取当前的实现地址
    const currentImplementation = await upgrades.erc1967.getImplementationAddress(proxyAddress);
    console.log("Current implementation address:", currentImplementation);

    // 3. 部署新版本的合约
    console.log("Deploying new version of Aave2Pool...");
    const Aave2PoolV2 = await ethers.getContractFactory("Aave2Pool");

    // 4. 升级合约
    console.log("Upgrading proxy to new implementation...");
    const upgraded = await upgrades.upgradeProxy(proxyAddress, Aave2PoolV2);
    await upgraded.waitForDeployment();
    console.log("Upgrade completed successfully!");

    // 5. 验证升级结果
    const newImplementation = await upgrades.erc1967.getImplementationAddress(proxyAddress);
    console.log("New implementation address:", newImplementation);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error("Upgrade failed:", error);
        process.exit(1);
    });