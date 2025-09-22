const {expect} = require("chai")
const {ethers} = require("hardhat")

let address1, address2, address3
let Aave2Pool, Chainlink, AaveToken, USDCToken, DEGENToken, TOSHIToken

describe("deposit borrow Test", function () {
    beforeEach(async function () {
        [address1, address2, address3] = await ethers.getSigners();

        // 部署Aave Token
        const debtToken = await ethers.getContractFactory("Token");
        AaveToken = await debtToken.deploy("AAVE Token", "AAVE");
        await AaveToken.waitForDeployment();

        // 部署USDC Token
        const usdcToken = await ethers.getContractFactory("Token");
        USDCToken = await usdcToken.deploy("USDC Token", "USDC");
        await USDCToken.waitForDeployment();

        // mint usdc tokens 100000000个（18位精度）
        await USDCToken.mint(address2.address, ethers.parseUnits("100000000", 18));

        // 部署DEGEN Token
        const degenToken = await ethers.getContractFactory("Token");
        DEGENToken = await degenToken.deploy("DEGEN Token", "DEGEN");
        await DEGENToken.waitForDeployment();

        // mint degen tokens 100000000个（18位精度）
        await DEGENToken.mint(address3.address, ethers.parseUnits("100000000", 18));

        // 部署TOSHI Token
        const toshiToken = await ethers.getContractFactory("Token");
        TOSHIToken = await toshiToken.deploy("TOSHI Token", "TOSHI");
        await TOSHIToken.waitForDeployment();

        // mint toshi tokens 100000000个（18位精度）
        await TOSHIToken.mint(address3.address, ethers.parseUnits("100000000", 18));

        // 部署Chainlink Price Oracle
        const chainlink = await ethers.getContractFactory("Chainlink");
        Chainlink = await chainlink.deploy();
        await Chainlink.waitForDeployment();

        // 部署Aave2Pool
        const aave2PoolFactory = await ethers.getContractFactory("Aave2Pool")
        Aave2Pool = await aave2PoolFactory.deploy(
            address1.address,
            await AaveToken.getAddress(),
            await USDCToken.getAddress(),
            await Chainlink.getAddress()
        );
        await Aave2Pool.waitForDeployment();

        // 设置每个代币价格：
        await Chainlink.setTokenPrice(await USDCToken.getAddress(), ethers.parseUnits("1", 2));
        await Chainlink.setTokenPrice(await DEGENToken.getAddress(), ethers.parseUnits("2", 2));
        await Chainlink.setTokenPrice(await TOSHIToken.getAddress(), ethers.parseUnits("4", 2));

        // 设置每个代币的基础信息
        await Aave2Pool.setCollateral(await DEGENToken.getAddress(), 1000000, 800000, 800000);
        await Aave2Pool.setCollateral(await TOSHIToken.getAddress(), 1000000, 800000, 800000);

        // 设置平台和清算人的奖励利率
        await Aave2Pool.setLiquidationPenaltyFeeRate4Protocol(50000);
        await Aave2Pool.setLiquidationPenaltyFeeRate4Cleaner(50000);

        // 设置借入人利率
        await Aave2Pool.setInterestRate(100000);
    })
    describe("should deposit borrow successfully", async () => {
        it("should deposit borrow successfully", async () => {
            // 首先授权 Aave2Pool 合约可以操作 address2 的 USDC
            const approveTx = await USDCToken.connect(address2).approve(
                await Aave2Pool.getAddress(),
                2n ** 256n - 1n
            );
            await approveTx.wait();

            {
                // 然后调用 depositLend
                const tx1 = await Aave2Pool.connect(address2).depositLend(ethers.parseUnits("1000", 18));
                await tx1.wait();
                expect(tx1.hash).to.not.be.null;

                // 检查合约状态
                const utilizationRate = await Aave2Pool.getUtilizationRate();
                const totalBorrow = await Aave2Pool.getTotalBorrow();
                const totalLend = await Aave2Pool.getTotalLend();
                // 判断利用率
                expect(utilizationRate).to.equal(0);
                // 判断借出总金额
                expect(totalBorrow).to.equal(0);
                // 判断借入总金额
                expect(totalLend).to.equal(ethers.parseUnits("1000", 18));
                // 判断address2在平台中的借入总金额
                expect(await Aave2Pool.getUserLend(address2.address)).to.equal(ethers.parseUnits("1000", 18));
                // 判断address2的USDC余额
                expect(await USDCToken.balanceOf(address2.address)).to.equal(ethers.parseUnits("99999000", 18));
                // 判断Aave2Pool的USDC余额
                expect(await USDCToken.balanceOf(await Aave2Pool.getAddress())).to.equal(ethers.parseUnits("1000", 18));
                // 判断borrowable
                const degenCollateralDetail = await Aave2Pool.getCollateral(await DEGENToken.getAddress());
                expect(degenCollateralDetail.borrowable).to.equal(ethers.parseUnits("500", 18));
                const toshiCollateralDetail = await Aave2Pool.getCollateral(await TOSHIToken.getAddress());
                expect(toshiCollateralDetail.borrowable).to.equal(ethers.parseUnits("500", 18));
            }

            {
                // 然后调用 depositLend
                const tx3 = await Aave2Pool.connect(address2).depositLend(ethers.parseUnits("1000", 18));
                await tx3.wait();
                expect(tx3.hash).to.not.be.null;
                // 检查合约状态
                const utilizationRate = await Aave2Pool.getUtilizationRate();
                const totalBorrow = await Aave2Pool.getTotalBorrow();
                const totalLend = await Aave2Pool.getTotalLend();
                // 判断利用率
                expect(utilizationRate).to.equal(0);
                // 判断借出总金额
                expect(totalBorrow).to.equal(0);
                // 判断借入总金额
                expect(totalLend).to.equal(ethers.parseUnits("2000", 18));
                // 判断address2在平台中的借入总金额
                expect(await Aave2Pool.getUserLend(address2.address)).to.equal(ethers.parseUnits("2000", 18));
                // 判断address2的USDC余额
                expect(await USDCToken.balanceOf(address2.address)).to.equal(ethers.parseUnits("99998000", 18));
                // 判断Aave2Pool的USDC余额
                expect(await USDCToken.balanceOf(await Aave2Pool.getAddress())).to.equal(ethers.parseUnits("2000", 18));
                // 判断borrowable
                const degenCollateralDetail = await Aave2Pool.getCollateral(await DEGENToken.getAddress());
                expect(degenCollateralDetail.borrowable).to.equal(ethers.parseUnits("1000", 18));
                const toshiCollateralDetail = await Aave2Pool.getCollateral(await TOSHIToken.getAddress());
                expect(toshiCollateralDetail.borrowable).to.equal(ethers.parseUnits("1000", 18));
            }

            {
                // 首先授权 Aave2Pool 合约可以操作 address3 的 USDC
                const approveTx = await DEGENToken.connect(address3).approve(
                    await Aave2Pool.getAddress(),
                    2n ** 256n - 1n
                );
                await approveTx.wait();
            }

            // 借100个DEGEN，能借出200 * 0.8 = 160个usdc
            {
                const tx = await Aave2Pool.connect(address3).depositBorrow(
                    await DEGENToken.getAddress(),
                    ethers.parseUnits("100", 18) // 100个DEGEN，能借160个usdc
                )
                await tx.wait();
                expect(tx.hash).to.not.be.null;

                // 检查合约状态
                const utilizationRate = await Aave2Pool.getUtilizationRate();
                const totalBorrow = await Aave2Pool.getTotalBorrow();
                const totalLend = await Aave2Pool.getTotalLend();
                // 判断利用率
                expect(utilizationRate).to.equal(80000);
                // 判断借出总金额
                expect(totalBorrow).to.equal(ethers.parseUnits("160", 18));
                // 判断借入总金额
                expect(totalLend).to.equal(ethers.parseUnits("2000", 18));
                // 判断address3拥有的usdc
                expect(await USDCToken.balanceOf(address3.address)).to.equal(ethers.parseUnits("160", 18));

                // 判断borrowable
                const degenCollateralDetail = await Aave2Pool.getCollateral(await DEGENToken.getAddress());
                expect(degenCollateralDetail.borrowable).to.equal(ethers.parseUnits("920", 18));
                const toshiCollateralDetail = await Aave2Pool.getCollateral(await TOSHIToken.getAddress());
                expect(toshiCollateralDetail.borrowable).to.equal(ethers.parseUnits("920", 18));
            }
        })
    })
})