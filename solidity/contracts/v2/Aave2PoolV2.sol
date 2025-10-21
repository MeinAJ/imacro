// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IChainlink} from "../IChainlink.sol";
import {DynamicInterestRateCalculator} from "../DynamicInterestRateCalculator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Aave2Pool is Initializable, UUPSUpgradeable, OwnableUpgradeable {

    using SafeERC20 for IERC20;
    using DynamicInterestRateCalculator for uint256;

    uint256 public constant TOKEN_DECIMALS = DynamicInterestRateCalculator.PRECISION; // 代币精度
    uint256 public constant RATE_DECIMALS = DynamicInterestRateCalculator.RATE_PRECISION; // 利率精度6位
    uint256 public constant DOLLAR_DECIMALS = DynamicInterestRateCalculator.DOLLAR_PRECISION; // 美元精度2位
    uint256 public constant SECONDS_PER_YEAR = 365 days;


    address public feeReceiver;
    uint256 public reserveFactor; // 储备金系数 (6位精度)

    // 分开的指数系统
    uint256 public liquidityIndex;      // 存款指数 (初始 1e27)
    uint256 public borrowIndex;         // 借款指数 (初始 1e27)
    uint256 public lastUpdateTimestamp; // 最后更新时间

    uint256 public safeHealthFactor; // 安全健康系数，默认1.2，1200000 (6位精度)

    address public aaveTokenAddress;
    address public usdcTokenAddress;
    address public cUsdcTokenAddress;
    address public chainlinkAddress;

    address[] public supportedCollateralAddresses;
    uint256 public liquidationPenaltyFeeRate4Cleaner; // 清算惩罚率 (6位精度)
    uint256 public closeFactor; // 关闭因子，决定一次清算可以清算多少债务 (6位精度)

    // 本金总额 (不包含利息)
    uint256 public totalPrincipalLend;    // 存款本金总额
    uint256 public totalPrincipalBorrow;  // 借款本金总额

    // 用户存款记录
    mapping(address => LendRecord[]) public userLendAmount;

    // 用户借款记录
    mapping(address => mapping(address => uint256)) public userDepositTokenAmount;
    mapping(address => mapping(address => BorrowRecord[])) public userBorrowAmount;
    mapping(address => address[]) public tokenBorrower;

    // 抵押物信息
    mapping(address => Collateral) public collaterals;

    struct LendRecord {
        uint256 principalAmount;      // 本金金额
        uint256 liquidityIndexSnapshot; // 存款时的流动性指数
        uint256 timestamp;
    }

    struct BorrowRecord {
        uint256 principalAmount;      // 本金金额
        uint256 borrowIndexSnapshot;   // 借款时的借款指数
        uint256 timestamp;
    }

    struct Collateral {
        address tokenAddress;
        uint256 totalCollateral;      // 总抵押数量
        uint256 totalBorrowPrincipal; // 该抵押物的总借款本金
        uint256 liquidationThreshold;
        uint256 collateralizationRatio;
    }

    event LendDeposited(address indexed user, uint256 amount, uint256 liquidityIndex);
    event LendWithdraw(address indexed user, uint256 amount, uint256 interest);
    event DepositCollateral(address indexed user, address indexed collateralToken, uint256 collateralAmount);
    event DepositCollateralWithdraw(address indexed user, address indexed collateralToken, uint256 collateralAmount);
    event BorrowDeposited(address indexed user, address indexed collateralToken, uint256 borrowAmount);
    event BorrowRepay(address indexed user, address indexed collateralToken, uint256 repayAmount);
    event Liquidated(address indexed borrower, address indexed liquidator, address collateralToken, uint256 liquidatedAmount, uint256 collateralSeized);

    function initialize(
        address _feeReceiver,
        address _aaveTokenAddress,
        address _usdcTokenAddress,
        address _cUsdcTokenAddress,
        address _chainlinkAddress
    ) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        _inner_initialize(
            _feeReceiver,
            _aaveTokenAddress,
            _usdcTokenAddress,
            _cUsdcTokenAddress,
            _chainlinkAddress
        );
        _inner_basic_init();
    }

    function _inner_basic_init() internal {
        reserveFactor = 1e5; // 100000 = 10%
        liquidityIndex = 1e27;   // 初始存款指数
        borrowIndex = 1e27;      // 初始借款指数
        lastUpdateTimestamp = block.timestamp;
        totalPrincipalLend = 0;
        totalPrincipalBorrow = 0;
        liquidationPenaltyFeeRate4Cleaner = 1e5; // 10%
        closeFactor = 5e5; // 50% 默认关闭因子
    }

    function _inner_initialize(
        address _feeReceiver,
        address _aaveTokenAddress,
        address _usdcTokenAddress,
        address _cUsdcTokenAddress,
        address _chainlinkAddress
    ) internal {
        feeReceiver = _feeReceiver;
        aaveTokenAddress = _aaveTokenAddress;
        usdcTokenAddress = _usdcTokenAddress;
        cUsdcTokenAddress = _cUsdcTokenAddress;
        chainlinkAddress = _chainlinkAddress;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ========== 核心指数计算函数 ==========

    function getTokenBorrowInfo(address collateralToken) public view returns (uint256 borrowed, uint256 borrowable, uint256 utilizationRate) {
        require(collaterals[collateralToken].tokenAddress != address(0), "Collateral not supported");
        Collateral storage collateral = collaterals[collateralToken];
        uint256 totalCollateral = collateral.totalCollateral;
        uint256 tokenPrice = IChainlink(chainlinkAddress).getTokenPrice(collateralToken);
        uint256 usdcPrice = IChainlink(chainlinkAddress).getTokenPrice(usdcTokenAddress);

        // 计算总借款
        borrowed = getTotalBorrowWithInterestByToken(collateralToken) * usdcPrice;
        // 计算总可借款
        borrowable = (totalCollateral * tokenPrice - getTotalBorrowWithInterestByToken(collateralToken) * usdcPrice) * collateral.collateralizationRatio / RATE_DECIMALS;
        // 计算利用率
        utilizationRate = borrowed * RATE_DECIMALS / (borrowed + borrowable);
    }

    /**
     * @dev 更新存款和借款指数
     * 基于复利公式: index_new = index_old * (1 + rate * timeDelta)
     */
    function updateIndexes() internal {
        uint256 currentTimestamp = block.timestamp;
        if (currentTimestamp <= lastUpdateTimestamp) {
            return;
        }

        uint256 timeDelta = currentTimestamp - lastUpdateTimestamp;

        // 计算当前利用率
        uint256 currentUtilizationRate = getCurrentUtilizationRate();

        if (currentUtilizationRate > 0) {
            // 计算借款利率 (年化)
            uint256 borrowRate = DynamicInterestRateCalculator.calculateBorrowRate(currentUtilizationRate);

            // 计算存款利率 (年化)
            uint256 supplyRate = DynamicInterestRateCalculator.calculateSupplyRate(
                currentUtilizationRate,
                borrowRate,
                reserveFactor
            );

            // 更新借款指数: borrowIndex = borrowIndex * (1 + borrowRate * timeDelta / SECONDS_PER_YEAR)
            uint256 borrowInterestFactor = (borrowRate * timeDelta * 1e27) / (SECONDS_PER_YEAR * RATE_DECIMALS);
            borrowIndex += (borrowIndex * borrowInterestFactor) / 1e27;

            // 更新存款指数: liquidityIndex = liquidityIndex * (1 + supplyRate * timeDelta / SECONDS_PER_YEAR)
            uint256 supplyInterestFactor = (supplyRate * timeDelta * 1e27) / (SECONDS_PER_YEAR * RATE_DECIMALS);
            liquidityIndex += (liquidityIndex * supplyInterestFactor) / 1e27;
        }

        lastUpdateTimestamp = currentTimestamp;
    }

    /**
     * @dev 获取当前利用率 (实时计算)
     */
    function getCurrentUtilizationRate() public view returns (uint256) {
        uint256 totalLendWithInterest = getTotalLendWithInterest();
        if (totalLendWithInterest == 0) return 0;
        uint256 totalBorrowWithInterest = getTotalBorrowWithInterest();
        return (totalBorrowWithInterest * RATE_DECIMALS) / totalLendWithInterest;
    }

    /**
     * @dev 获取总存款 (包含利息)
     */
    function getTotalLendWithInterest() public view returns (uint256) {
        return (totalPrincipalLend * getCurrentLiquidityIndex()) / 1e27;
    }

    /**
     * @dev 获取总借款 (包含利息)
     */
    function getTotalBorrowWithInterest() public view returns (uint256) {
        return (totalPrincipalBorrow * getCurrentBorrowIndex()) / 1e27;
    }

    /**
     * @dev 获取某个抵押代币的可借金额
     */
    function getTotalBorrowWithInterestByToken(address collateralToken) public view returns (uint256) {
        require(collaterals[collateralToken].tokenAddress != address(0), "Collateral not supported");
        Collateral storage collateral = collaterals[collateralToken];
        uint256 totalBorrowPrincipal = collateral.totalBorrowPrincipal;
        return (totalBorrowPrincipal * getCurrentBorrowIndex()) / 1e27;
    }

    /**
 * @dev 获取某个抵押代币的借款率
     */
    function getTotalBorrowWithInterestByToken(address collateralToken) public view returns (uint256) {
        require(collaterals[collateralToken].tokenAddress != address(0), "Collateral not supported");
        Collateral storage collateral = collaterals[collateralToken];
        uint256 totalBorrowPrincipal = collateral.totalBorrowPrincipal;
        return (totalBorrowPrincipal * getCurrentBorrowIndex()) / 1e27;
    }

    /**
     * @dev 获取当前存款指数 (包含未累积的利息)
     */
    function getCurrentLiquidityIndex() public view returns (uint256) {
        uint256 currentTimestamp = block.timestamp;
        if (currentTimestamp <= lastUpdateTimestamp) {
            return liquidityIndex;
        }

        uint256 timeDelta = currentTimestamp - lastUpdateTimestamp;
        uint256 currentUtilizationRate = getCurrentUtilizationRate();

        if (currentUtilizationRate == 0) return liquidityIndex;

        uint256 borrowRate = DynamicInterestRateCalculator.calculateBorrowRate(currentUtilizationRate);
        uint256 supplyRate = DynamicInterestRateCalculator.calculateSupplyRate(
            currentUtilizationRate,
            borrowRate,
            reserveFactor
        );

        uint256 supplyInterestFactor = (supplyRate * timeDelta * 1e27) / (SECONDS_PER_YEAR * RATE_DECIMALS);
        return liquidityIndex + (liquidityIndex * supplyInterestFactor) / 1e27;
    }

    /**
     * @dev 获取当前借款指数 (包含未累积的利息)
     */
    function getCurrentBorrowIndex() public view returns (uint256) {
        uint256 currentTimestamp = block.timestamp;
        if (currentTimestamp <= lastUpdateTimestamp) {
            return borrowIndex;
        }

        uint256 timeDelta = currentTimestamp - lastUpdateTimestamp;
        uint256 currentUtilizationRate = getCurrentUtilizationRate();

        if (currentUtilizationRate == 0) return borrowIndex;

        uint256 borrowRate = DynamicInterestRateCalculator.calculateBorrowRate(currentUtilizationRate);
        uint256 borrowInterestFactor = (borrowRate * timeDelta * 1e27) / (SECONDS_PER_YEAR * RATE_DECIMALS);
        return borrowIndex + (borrowIndex * borrowInterestFactor) / 1e27;
    }

    // ========== 用户计算函数 ==========

    /**
     * @dev 计算用户存款总额 (包含利息)
     */
    function calculateUserLendTotal(address user) public view returns (uint256 totalWithInterest) {
        uint256 currentLiquidityIndex = getCurrentLiquidityIndex();
        LendRecord[] storage records = userLendAmount[user];

        for (uint256 i = 0; i < records.length; i++) {
            LendRecord memory record = records[i];
            uint256 amountWithInterest = (record.principalAmount * currentLiquidityIndex) / record.liquidityIndexSnapshot;
            totalWithInterest += amountWithInterest;
        }
    }

    /**
     * @dev 计算用户借款总额 (包含利息)
     */
    function calculateUserBorrowTotal(address user, address collateralToken) public view returns (uint256 totalWithInterest) {
        uint256 currentBorrowIndex = getCurrentBorrowIndex();
        BorrowRecord[] storage records = userBorrowAmount[collateralToken][user];

        for (uint256 i = 0; i < records.length; i++) {
            BorrowRecord memory record = records[i];
            uint256 amountWithInterest = (record.principalAmount * currentBorrowIndex) / record.borrowIndexSnapshot;
            totalWithInterest += amountWithInterest;
        }
    }

    // ========== 核心业务函数 ==========

    /**
     * @dev 存款功能
     */
    function depositLend(uint256 _amount) external {
        require(_amount > 0, "Amount must be greater than 0");

        // 更新指数
        updateIndexes();

        // 转移USDC到合约
        IERC20(usdcTokenAddress).safeTransferFrom(msg.sender, address(this), _amount);

        // 更新存款本金总额
        totalPrincipalLend += _amount;

        // 记录存款
        userLendAmount[msg.sender].push(LendRecord({
            principalAmount: _amount,
            liquidityIndexSnapshot: liquidityIndex,
            timestamp: block.timestamp
        }));

        emit LendDeposited(msg.sender, _amount, liquidityIndex);
    }

    /**
     * @dev 取款功能
     */
    function depositLendWithdraw(uint256 _amount) external {
        require(_amount > 0, "Amount must be greater than 0");

        // 更新指数
        updateIndexes();

        uint256 userTotalWithInterest = calculateUserLendTotal(msg.sender);
        require(userTotalWithInterest >= _amount, "Insufficient balance");

        // 处理用户存款记录，计算需要减少的本金
        uint256 remaining = _amount;
        uint256 principalToReduce = 0;
        LendRecord[] storage records = userLendAmount[msg.sender];

        for (int256 i = int256(records.length) - 1; i >= 0 && remaining > 0; i--) {
            LendRecord storage record = records[uint256(i)];
            uint256 recordTotalWithInterest = (record.principalAmount * liquidityIndex) / record.liquidityIndexSnapshot;

            if (recordTotalWithInterest <= remaining) {
                // 完全提取这条记录
                principalToReduce += record.principalAmount;
                remaining -= recordTotalWithInterest;

                // 删除记录
                records[uint256(i)] = records[records.length - 1];
                records.pop();
            } else {
                // 部分提取
                uint256 principalPart = (remaining * record.liquidityIndexSnapshot) / liquidityIndex;
                principalToReduce += principalPart;
                record.principalAmount -= principalPart;
                remaining = 0;
            }
        }

        require(remaining == 0, "Insufficient funds after processing");

        // 更新存款本金总额
        totalPrincipalLend -= principalToReduce;

        // 计算利息
        uint256 interestEarned = _amount - principalToReduce;

        // 转移资金给用户
        IERC20(usdcTokenAddress).safeTransfer(msg.sender, _amount);

        emit LendWithdraw(msg.sender, _amount, interestEarned);
    }

    /**
     * @dev 抵押
     * _tokenAddress 抵押物代币地址
     * _tokenAmount 抵押物数量
     */
    function depositCollateral(address _tokenAddress, uint256 _tokenAmount) external {
        require(_tokenAmount > 0, "Amount must be greater than 0");
        require(collaterals[_tokenAddress].tokenAddress != address(0), "Collateral not supported");

        // 更新指数
        updateIndexes();

        // 转移抵押代币到合约
        IERC20(_tokenAddress).safeTransferFrom(msg.sender, address(this), _tokenAmount);

        // 更新抵押物信息
        collaterals[_tokenAddress].totalCollateral += _tokenAmount;
        userDepositTokenAmount[_tokenAddress][msg.sender] += _tokenAmount;

        emit DepositCollateral(msg.sender, _tokenAddress, _tokenAmount);
    }

    /**
     * @dev 抵押撤回
     * _tokenAddress 抵押物代币地址
     * _withdrawPercentage 抵押物百分比
     */
    function depositCollateralWithdraw(address _tokenAddress, uint256 _withdrawPercentage) external {
        require(_withdrawPercentage <= RATE_DECIMALS, "Percentage too high");
        require(collaterals[_tokenAddress].tokenAddress != address(0), "Collateral not supported");

        // 更新指数
        updateIndexes();

        Collateral storage collateral = collaterals[_tokenAddress];
        // 总已借USDC数量（包含利息）
        uint256 totalBorrowedWithInterest = calculateUserBorrowTotal(msg.sender, _tokenAddress);
        // 总可借USDC数量
        uint256 maxBorrowUSDCAmount = _getCollateralValue(
            _tokenAddress,
            userDepositTokenAmount[_tokenAddress][msg.sender],
            RATE_DECIMALS
        ) * collateral.collateralizationRatio / RATE_DECIMALS;
        // 可撤回的USDC价值数量
        uint256 withdrawAmount =(maxBorrowUSDCAmount - totalBorrowedWithInterest) * _withdrawPercentage / RATE_DECIMALS;
        // 计算需要撤回的数量
        uint256 tokenPrice = IChainlink(chainlinkAddress).getTokenPrice(_tokenAddress);
        uint256 usdcPrice = IChainlink(chainlinkAddress).getTokenPrice(usdcTokenAddress);
        uint256 withdrawTokenAmount = withdrawAmount * usdcPrice * DOLLAR_DECIMALS / tokenPrice;

        // 更新抵押数量
        userDepositTokenAmount[_tokenAddress][msg.sender] -= withdrawTokenAmount;
        collateral.totalCollateral -= withdrawTokenAmount;

        // 将抵押物转移回用户
        IERC20(_tokenAddress).safeTransfer(msg.sender, withdrawTokenAmount);

        emit DepositCollateralWithdraw(msg.sender, _tokenAddress, withdrawTokenAmount);
    }

    /**
     * @dev 抵押借款
     * _tokenAddress 抵押物代币地址
     * _borrowPercentage 借款比例 (100% = 1e6)
     */
    function borrow(address _tokenAddress, uint256 _borrowPercentage) external {
        require(collaterals[_tokenAddress].tokenAddress != address(0), "Collateral not supported");
        require(_borrowPercentage <= 1e6, "Borrow percentage too high");
        require(userDepositTokenAmount[_tokenAddress][msg.sender] > 0, "No collateral deposited");

        // 更新指数
        updateIndexes();

        // 先计算还可以借款多少usdc
        Collateral storage collateral = collaterals[_tokenAddress];
        uint256 totalTokenAmount = userDepositTokenAmount[_tokenAddress][msg.sender];
        uint256 maxBorrowUSDCAmount = _getCollateralValue(_tokenAddress, totalTokenAmount, RATE_DECIMALS) * collateral.collateralizationRatio / RATE_DECIMALS;
        uint256 totalBorrowedWithInterest = calculateUserBorrowTotal(msg.sender, _tokenAddress);

        // 计算还可以最多贷款多少
        require(maxBorrowUSDCAmount >= totalBorrowedWithInterest, "Insufficient collateral value");
        uint256 maxBorrowAmount = maxBorrowUSDCAmount - totalBorrowedWithInterest;

        // 计算借款数量
        uint256 actualBorrowAmount = maxBorrowAmount * _borrowPercentage / RATE_DECIMALS;
        require(actualBorrowAmount > 0, "Insufficient collateral value");

        // 检查合约是否有足够的流动性
        uint256 availableLiquidity = getTotalLendWithInterest() - getTotalBorrowWithInterest();
        require(availableLiquidity >= actualBorrowAmount, "Insufficient liquidity");

        // 更新抵押物信息
        collateral.totalBorrowPrincipal += actualBorrowAmount;

        // 记录借款
        userBorrowAmount[_tokenAddress][msg.sender].push(BorrowRecord({
            principalAmount: actualBorrowAmount,
            borrowIndexSnapshot: borrowIndex,
            timestamp: block.timestamp
        }));

        // 更新借款本金总额
        totalPrincipalBorrow += actualBorrowAmount;

        // 添加借款人到列表
        _addBorrowerToToken(_tokenAddress, msg.sender);

        // 转移借款给用户
        IERC20(usdcTokenAddress).safeTransfer(msg.sender, actualBorrowAmount);

        emit BorrowDeposited(msg.sender, _tokenAddress, actualBorrowAmount);
    }

    /**
     * @dev 抵押借款后还钱
     * _tokenAddress 抵押物代币地址
     * repayPercentage 还款百分比 (100% = 1e6)
     */
    function borrowRepay(address _tokenAddress, uint256 repayPercentage) external {
        require(collaterals[_tokenAddress].tokenAddress != address(0), "Collateral not supported");
        require(userBorrowAmount[_tokenAddress][msg.sender].length > 0, "No borrowed");

        // 更新指数
        updateIndexes();

        uint256 totalBorrowAmountWithInterest = calculateUserBorrowTotal(msg.sender, _tokenAddress);
        require(totalBorrowAmountWithInterest > 0, "No borrow to repay");
        uint256 actualReplayAmount = totalBorrowAmountWithInterest * repayPercentage / RATE_DECIMALS;

        // 转移还款资金
        IERC20(usdcTokenAddress).safeTransferFrom(msg.sender, address(this), actualReplayAmount);
        // 返回抵押物
        uint256 tokenPrice = IChainlink(chainlinkAddress).getTokenPrice(_tokenAddress);
        uint256 usdcPrice = IChainlink(chainlinkAddress).getTokenPrice(usdcTokenAddress);
        uint256 withdrawTokenAmount = actualReplayAmount * usdcPrice * DOLLAR_DECIMALS / tokenPrice;
        IERC20(_tokenAddress).safeTransfer(msg.sender, withdrawTokenAmount);

        // 更新用户抵押物数量
        userDepositTokenAmount[_tokenAddress][msg.sender] += withdrawTokenAmount;
        // 更新总抵押物数量
        collaterals[_tokenAddress].totalCollateral -= actualReplayAmount;
        // 更新借款本金
        BorrowRecord[] storage records = userBorrowAmount[_tokenAddress][msg.sender];

        uint256 remaining = actualReplayAmount;
        for (int256 i = int256(records.length) - 1; i >= 0 && remaining > 0; i--) {
            // 计算每个借款记录的本金+利息
            BorrowRecord storage record = records[uint256(i)];
            uint256 principalWithInterest = (record.principalAmount * borrowIndex) / record.borrowIndexSnapshot;
            if (principalWithInterest <= remaining) {
                // 这个记录可以全部还清
                remaining -= principalWithInterest;
                // 删除记录
                records[uint256(i)] = records[records.length - 1];
                records.pop();
            } else {
                // 这个记录部分还清
                uint256 principalPart = (remaining * record.borrowIndexSnapshot) / borrowIndex;
                record.principalAmount -= principalPart;
                remaining = 0;
            }
        }
        emit BorrowRepay(msg.sender, _tokenAddress, actualReplayAmount);
    }

    // ========== 辅助函数 ==========

    function _addBorrowerToToken(address _tokenAddress, address _borrower) internal {
        address[] storage borrowers = tokenBorrower[_tokenAddress];
        for (uint256 i = 0; i < borrowers.length; i++) {
            if (borrowers[i] == _borrower) {
                return;
            }
        }
        borrowers.push(_borrower);
    }

    function _calculateUserBorrowPrincipal(address _tokenAddress, address _user) internal view returns (uint256 totalPrincipal) {
        BorrowRecord[] storage records = userBorrowAmount[_tokenAddress][_user];
        for (uint256 i = 0; i < records.length; i++) {
            totalPrincipal += records[i].principalAmount;
        }
    }

    function _getCollateralValue(address tokenAddress, uint256 _amount, uint256 borrowPercentage) internal view returns (uint256) {
        // 简化实现 - 实际应该从Chainlink获取价格
        uint256 tokenPrice = IChainlink(chainlinkAddress).getTokenPrice(tokenAddress);
        uint256 usdcPrice = IChainlink(usdcTokenAddress).getTokenPrice(usdcTokenAddress);
        return _amount * tokenPrice * DOLLAR_DECIMALS / usdcPrice / DOLLAR_DECIMALS * borrowPercentage / RATE_DECIMALS;
    }

    // ========== 清算相关函数 ==========

    /**
     * @dev 设置清算参数
     */
    function setLiquidationParameters(
        uint256 _liquidationPenaltyFeeRate4Cleaner,
        uint256 _closeFactor
    ) external onlyOwner {
        require(_liquidationPenaltyFeeRate4Cleaner <= 200000, "Penalty too high"); // 最大20%清算奖励（惩罚率）
        require(_liquidationPenaltyFeeRate4Cleaner <= 250000, "Invalid close factor"); // 最大25%清算比例

        liquidationPenaltyFeeRate4Cleaner = _liquidationPenaltyFeeRate4Cleaner;
        closeFactor = _closeFactor;
    }

    /**
     * @dev 计算用户的健康因子
     * 健康因子 = (抵押物价值 × 清算阈值) / 总债务价值
     * 健康因子 < 1 表示可被清算
     */
    function calculateHealthFactor(
        address user,
        address collateralToken
    ) public view returns (uint256) {
        uint256 totalDebtValue = calculateUserTotalDebtValue(collateralToken, user);
        if (totalDebtValue == 0) return type(uint256).max;

        uint256 collateralValue = calculateUserTotalCollateralValue(collateralToken, user);
        Collateral memory collateralConfig = collaterals[collateralToken];
        uint256 liquidationThresholdValue = (collateralValue * collateralConfig.liquidationThreshold) / RATE_DECIMALS;

        if (liquidationThresholdValue == 0) return 0;

        return (liquidationThresholdValue * RATE_DECIMALS) / totalDebtValue;
    }

    /**
     * @dev 计算用户总债务价值 (usdc价格)
     */
    function calculateUserTotalDebtValue(address collateralToken, address user) public view returns (uint256 totalDebtValue) {
        uint256 borrowAmountWithInterest = calculateUserBorrowTotal(user, collateralToken);
        if (borrowAmountWithInterest > 0) {
            // 预言机获取价格
            totalDebtValue = borrowAmountWithInterest;
        }
    }

    /**
     * @dev 计算用户总抵押物价值（usdc价格）
     */
    function calculateUserTotalCollateralValue(address collateralToken, address user) public view returns (uint256 totalCollateralValue) {
        // 这里需要实现用户抵押物记录查询
        // 简化实现：遍历所有支持的抵押物，计算用户抵押的价值
        uint256 userCollateralAmount = userDepositTokenAmount[collateralToken][user];
        if (userCollateralAmount > 0) {
            // 预言机获取价格
            uint256 tokenPrice = IChainlink(chainlinkAddress).getTokenPrice(collateralToken);
            uint256 usdcPrice = IChainlink(usdcTokenAddress).getTokenPrice(usdcTokenAddress);
            totalCollateralValue = userCollateralAmount * tokenPrice * DOLLAR_DECIMALS / usdcPrice / DOLLAR_DECIMALS;
        }
    }

    /**
     * @dev 检查可清算的用户
     */
    function checkLiquidate(address _tokenAddress) public view returns (ReturnLiquidateInfo[] memory) {
        require(collaterals[_tokenAddress].tokenAddress != address(0), "Collateral not supported");

        address[] memory borrowers = tokenBorrower[_tokenAddress];
        Collateral storage collateral = collaterals[_tokenAddress];
        ReturnLiquidateInfo[] memory liquidatableUsers = new ReturnLiquidateInfo[](borrowers.length);
        uint256 count = 0;

        for (uint256 i = 0; i < borrowers.length; i++) {
            address borrower = borrowers[i];
            uint256 healthFactor = calculateHealthFactor(borrower, _tokenAddress);

            // 健康因子 < 1 表示可被清算
            if (healthFactor < RATE_DECIMALS) {
                uint256 totalDebtValue = calculateUserTotalDebtValue(_tokenAddress, borrower);
                uint256 userCollateralAmount = calculateUserTotalCollateralValue(_tokenAddress, borrower);

                liquidatableUsers[count] = ReturnLiquidateInfo({
                    borrower: borrower,
                    usdcPrice: getTokenPrice(usdcTokenAddress),
                    tokenPrice: getTokenPrice(_tokenAddress),
                    userTotal: totalDebtValue,
                    userDeposited: userCollateralAmount,
                    healthFactor: healthFactor,
                    liquidationThreshold: collateral.liquidationThreshold,
                    maxLiquidationAmount: calculateMaxLiquidationAmount(borrower, _tokenAddress)
                });
                count++;
            }
        }

        // 调整数组大小
        ReturnLiquidateInfo[] memory result = new ReturnLiquidateInfo[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = liquidatableUsers[i];
        }

        return result;
    }

    /**
     * @dev 计算最大可清算金额
     */
    function calculateMaxLiquidationAmount(address borrower, address collateralToken) public view returns (uint256) {
        uint256 totalDebt = calculateUserTotalDebtValue(collateralToken, borrower);
        uint256 healthFactor = calculateHealthFactor(borrower, collateralToken);

        if (healthFactor >= RATE_DECIMALS) {
            return 0;
        }

        // 计算需要偿还多少债务才能使健康因子恢复到1.2以上(safeHealthFactor = 1.2)
        uint256 collateralValue = calculateUserTotalCollateralValue(borrower, borrower);
        uint256 tokenLiquidationThreshold = collaterals[collateralToken].liquidationThreshold;

        uint256 maxLiquidation = (totalDebt * safeHealthFactor - collateralValue * tokenLiquidationThreshold) / (safeHealthFactor - tokenLiquidationThreshold);
        return maxLiquidation > totalDebt ? totalDebt : maxLiquidation;
    }

    /**
     * @dev 执行清算
     */
    function liquidate(
        address _tokenAddress,
        address _borrower,
        uint256 _debtAmountToCover
    ) external {
        require(collaterals[_tokenAddress].tokenAddress != address(0), "Collateral not supported");
        require(_debtAmountToCover > 0, "Amount must be greater than 0");

        // 更新指数
        updateIndexes();

        // 检查健康因子
        uint256 healthFactor = calculateHealthFactor(_borrower, _tokenAddress);
        require(healthFactor < RATE_DECIMALS, "Borrower is not liquidatable");

        // 检查最大清算金额
        uint256 maxLiquidationAmount = calculateMaxLiquidationAmount(_borrower, _tokenAddress);
        require(_debtAmountToCover <= maxLiquidationAmount, "Liquidation amount exceeds maximum");

        uint256 totalBorrowAmountWithInterest = calculateUserBorrowTotal(_borrower, _tokenAddress);
        require(_debtAmountToCover <= totalBorrowAmountWithInterest, "Liquidation amount exceeds debt");

        Collateral storage collateral = collaterals[_tokenAddress];

        // 计算抵押物价格和清算奖励
        uint256 collateralPrice = getTokenPrice(_tokenAddress);
        uint256 usdcPrice = getTokenPrice(usdcTokenAddress);

        // 计算清算人可获得的抵押物数量
        uint256 collateralAmountToLiquidator = (_debtAmountToCover * usdcPrice) / collateralPrice;

        // 添加清算奖励
        uint256 bonusAmount = (collateralAmountToLiquidator * liquidationPenaltyFeeRate4Cleaner) / RATE_DECIMALS;
        uint256 totalCollateralToLiquidator = collateralAmountToLiquidator + bonusAmount;

        // 检查抵押物是否足够
        uint256 userCollateralAmount = userDepositTokenAmount[_tokenAddress][_borrower];
        require(totalCollateralToLiquidator <= userCollateralAmount, "Insufficient collateral for liquidation");

        // 转移USDC从清算人到合约
        IERC20(usdcTokenAddress).safeTransferFrom(msg.sender, address(this), _debtAmountToCover);

        // 计算对应的借款本金减少
        uint256 currentBorrowIndex = borrowIndex;
        uint256 principalReduction = (_debtAmountToCover * 1e27) / currentBorrowIndex;

        // 更新借款记录
        _reduceUserBorrowPrincipal(_tokenAddress, _borrower, principalReduction);

        // 更新总借款本金
        totalPrincipalBorrow -= principalReduction;
        collateral.totalBorrowPrincipal -= principalReduction;

        // 更新抵押物
        collateral.totalCollateral -= totalCollateralToLiquidator;

        // 转移抵押物给清算人
        IERC20(_tokenAddress).safeTransfer(msg.sender, totalCollateralToLiquidator);

        emit Liquidated(_borrower, msg.sender, _tokenAddress, _debtAmountToCover, totalCollateralToLiquidator);
    }

    /**
     * @dev 减少用户借款本金
     */
    function _reduceUserBorrowPrincipal(
        address _tokenAddress,
        address _user,
        uint256 _principalReduction
    ) internal {
        BorrowRecord[] storage records = userBorrowAmount[_tokenAddress][_user];
        uint256 remainingReduction = _principalReduction;

        for (int256 i = int256(records.length) - 1; i >= 0 && remainingReduction > 0; i--) {
            BorrowRecord storage record = records[uint256(i)];

            if (record.principalAmount <= remainingReduction) {
                // 完全清除这条记录
                remainingReduction -= record.principalAmount;
                records[uint256(i)] = records[records.length - 1];
                records.pop();
            } else {
                // 部分减少
                record.principalAmount -= remainingReduction;
                remainingReduction = 0;
            }
        }

        require(remainingReduction == 0, "Insufficient borrow records to cover reduction");

        // 如果用户没有借款记录了，从借款人列表中移除
        if (records.length == 0) {
            _removeBorrowerFromToken(_tokenAddress, _user);
        }
    }

    /**
     * @dev 从借款人列表中移除用户
     */
    function _removeBorrowerFromToken(address _tokenAddress, address _borrower) internal {
        address[] storage borrowers = tokenBorrower[_tokenAddress];
        for (uint256 i = 0; i < borrowers.length; i++) {
            if (borrowers[i] == _borrower) {
                borrowers[i] = borrowers[borrowers.length - 1];
                borrowers.pop();
                break;
            }
        }
    }

    // ========== 价格获取函数 ==========

    /**
     * @dev 获取代币价格
     */
    function getTokenPrice(address token) public view returns (uint256) {
        return IChainlink(chainlinkAddress).getTokenPrice(token);
    }

    // ========== 视图函数 ==========

    /**
     * @dev 获取用户健康因子信息
     * _tokenAddress 抵押物地址
     * _user 用户地址
     */
    function getUserHealthInfo(address _tokenAddress, address _user) external view returns (
        uint256 healthFactor,
        uint256 totalCollateralValue,
        uint256 totalDebtValue,
        bool isLiquidatable
    ) {
        healthFactor = calculateHealthFactor(_user, _tokenAddress);
        totalCollateralValue = calculateUserTotalCollateralValue(_tokenAddress, _user);
        totalDebtValue = calculateUserTotalDebtValue(_tokenAddress, _user);
        isLiquidatable = (healthFactor < RATE_DECIMALS);
    }

    struct ReturnLiquidateInfo {
        address borrower; // 借款人
        uint256 usdcPrice; // usdc价格：美元，两位小数
        uint256 tokenPrice; // token价格：美元，两位小数
        uint256 userTotal; // 用户债务总额：usdc
        uint256 userDeposited; // 用户抵押物数量：usdc
        uint256 healthFactor; // 健康因子
        uint256 liquidationThreshold; // 清算阈值
        uint256 maxLiquidationAmount;
    }

}
