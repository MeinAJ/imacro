const {expect} = require("chai")
const {ethers} = require("hardhat")

let address1, address2, address3
let Aave2Pool, Chainlink, AaveToken, USDCToken, DEGENToken, TOSHIToken

describe("Basic Info Test", function () {
    beforeEach(async function () {
        [address1, address2, address3] = await ethers.getSigners();

        // 部署Aave Token
        const debtToken = await ethers.getContractFactory("Token");
        AaveToken = await debtToken.deploy("AAVE Token", "AAVE");
        await AaveToken.waitForDeployment(); // 等待部署完成

        // 部署USDC Token
        const usdcToken = await ethers.getContractFactory("Token");
        USDCToken = await usdcToken.deploy("USDC Token", "USDC");
        await USDCToken.waitForDeployment(); // 等待部署完成

        // mint usdc tokens 100000000个（18位精度）
        await USDCToken.mint(address1.address, ethers.parseUnits("100000000", 18));

        // 部署DEGEN Token
        const degenToken = await ethers.getContractFactory("Token");
        DEGENToken = await degenToken.deploy("DEGEN Token", "DEGEN");
        await DEGENToken.waitForDeployment(); // 等待部署完成

        // mint usdc tokens 100000000个（18位精度）
        await DEGENToken.mint(address1.address, ethers.parseUnits("100000000", 18));

        // 部署TOSHI Token
        const toshiToken = await ethers.getContractFactory("Token");
        TOSHIToken = await toshiToken.deploy("TOSHI Token", "TOSHI");
        await TOSHIToken.waitForDeployment(); // 等待部署完成

        // mint toshi tokens 100000000个（18位精度）
        await TOSHIToken.mint(address1.address, ethers.parseUnits("100000000", 18));

        // 部署Chainlink Price Oracle
        const chainlink = await ethers.getContractFactory("Chainlink");
        Chainlink = await chainlink.deploy();
        await Chainlink.waitForDeployment(); // 等待部署完成

        // 设置价格：
        Chainlink.setTokenPrice(await USDCToken.getAddress(), ethers.parseUnits("1", 2));
        Chainlink.setTokenPrice(await DEGENToken.getAddress(), ethers.parseUnits("80.5", 2));
        Chainlink.setTokenPrice(await TOSHIToken.getAddress(), ethers.parseUnits("42.15", 2));
    
        // 部署Aave2Pool
        const aave2PoolFactory = await ethers.getContractFactory("Aave2Pool")
        Aave2Pool = await aave2PoolFactory.deploy(
            address1.address,
            await AaveToken.getAddress(),
            await USDCToken.getAddress(),
            await Chainlink.getAddress()
        );
        await Aave2Pool.waitForDeployment();

    })

    describe("constructor test", async () => {
        it("should deploy successfully", async () => {
            const feeReceiver = await Aave2Pool.getFeeReceiver();
            const aaveTokenAddress = await Aave2Pool.getAaveTokenAddress();
            const usdcTokenAddress = await Aave2Pool.getUsdcTokenAddress();
            const chainlinkAddress = await Aave2Pool.getChainlinkAddress();

            expect(feeReceiver).to.equal(address1.address);
            expect(aaveTokenAddress).to.equal(await AaveToken.getAddress());
            expect(usdcTokenAddress).to.equal(await USDCToken.getAddress());
            expect(chainlinkAddress).to.equal(await Chainlink.getAddress());

            expect(feeReceiver).to.not.equal(address2.address);
            expect(aaveTokenAddress).to.not.equal(address2.address);
            expect(usdcTokenAddress).to.not.equal(address2.address);
            expect(chainlinkAddress).to.not.equal(address2.address);
        })
    })

    describe("basic info test", async () => {
        it("should set interest rate successfully", async () => {
            // 首先检查合约是否有setInterestRate函数
            // 如果是交易，需要等待交易确认
            const tx = await Aave2Pool.setInterestRate(100000);
            await tx.wait(); // 等待交易确认
            // 或者检查交易是否成功
            expect(tx.hash).to.not.be.null;
            // 如果是view/pure函数，直接读取返回值
            const interestRate = await Aave2Pool.getInterestRate();
            expect(interestRate).to.equal(100000);
        })

        it("should not set interest rate successfully", async () => {
            // 首先检查合约是否有setInterestRate函数
            // 如果是交易，需要等待交易确认
            const tx = await Aave2Pool.setInterestRate(100000);
            await tx.wait(); // 等待交易确认
            // 或者检查交易是否成功
            expect(tx.hash).to.not.be.null;

            // 如果是view/pure函数，直接读取返回值
            const interestRate = await Aave2Pool.getInterestRate();
            expect(interestRate).to.not.equal(100001);

        })

        it("should set collateral successfully", async () => {
            // 如果是交易，需要等待交易确认
            const tx = await Aave2Pool.setCollateral(await DEGENToken.getAddress(), 1000000, 800000, 800000);
            await tx.wait(); // 等待交易确认
            // 或者检查交易是否成功
            expect(tx.hash).to.not.be.null;

            // 如果是view/pure函数，直接读取返回值
            const collateralDetail = await Aave2Pool.getCollateral(await DEGENToken.getAddress());
            expect(collateralDetail.healthFactor).to.equal(1000000);
            expect(collateralDetail.liquidationThreshold).to.equal(800000);
            expect(collateralDetail.collateralizationRatio).to.equal(800000);
        })

        it("should set fee rate successfully", async () => {
            // 如果是交易，需要等待交易确认
            const tx1 = await Aave2Pool.setLiquidationPenaltyFeeRate4Protocol(50000);
            await tx1.wait(); // 等待交易确认
            // 或者检查交易是否成功
            expect(tx1.hash).to.not.be.null;
            // 如果是view/pure函数，直接读取返回值
            const liquidationPenaltyFeeRate4Protocol = await Aave2Pool.getLiquidationPenaltyFeeRate4Protocol();
            expect(liquidationPenaltyFeeRate4Protocol).to.equal(50000);


            // 如果是交易，需要等待交易确认
            const tx2 = await Aave2Pool.setLiquidationPenaltyFeeRate4Cleaner(50000);
            await tx2.wait(); // 等待交易确认
            // 或者检查交易是否成功
            expect(tx2.hash).to.not.be.null;

            // 如果是view/pure函数，直接读取返回值
            const liquidationPenaltyFeeRate4Cleaner = await Aave2Pool.getLiquidationPenaltyFeeRate4Cleaner();
            expect(liquidationPenaltyFeeRate4Cleaner).to.equal(50000);
        })
    })
})