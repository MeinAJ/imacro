// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IChainlink} from "./IChainlink.sol";
import {DynamicInterestRateCalculator} from "./DynamicInterestRateCalculator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Aave2Pool is Initializable, UUPSUpgradeable, OwnableUpgradeable {

    using DynamicInterestRateCalculator for uint256;

    uint256 public constant TOKEN_DECIMALS = DynamicInterestRateCalculator.PRECISION; // 代币精度

    uint256 public constant RATE_DECIMALS = DynamicInterestRateCalculator.RATE_PRECISION; // 利率精度6位

    uint256 public constant DOLLAR_DECIMALS = DynamicInterestRateCalculator.DOLLAR_PRECISION; // 美元精度2位

    address public feeReceiver; // 手续费接收地址
    uint256 public feeReceiverAmount; // 手续费接收数量

    address public aaveTokenAddress; // 平台代币地址

    address public usdcTokenAddress; // USDC代币地址

    address public chainlinkAddress; // 链上价格源地址

    address[] public supportedCollateralAddresses; // 支持的抵押代币地址

    uint256 public liquidationPenaltyFeeRate4Protocol; // 清算惩罚费率，平台收入

    uint256 public liquidationPenaltyFeeRate4Cleaner; // 清算惩罚费率，清算人收入

    // utilization rate
    uint256 public utilizationRate;

    // total borrow，单位：USDC
    uint256 public totalBorrow;

    // total deposits，单位：USDC
    uint256 public totalLend;

    // interest annual percentage rate (deprecated - now calculated dynamically)
    uint256 public interestRate;

    // reserve factor for supply rate calculation
    uint256 public reserveFactor;

    // every address supply,key=user address,value=supply，单位：USDC
    mapping(address => uint256) public userLendAmount;
    // 记录用户借入的时间，方便计算利率
    mapping(address => uint256) public userLendLastTime;
    mapping(address => uint256) public userLendLastTimeCalculateFee;

    // key=tokenAddress,value=userAddress[]
    mapping(address => address[]) public tokenBorrower;
    // key=tokenAddress,value=(key=userAddress,value=borrowDepositedAmount) 单位：代币
    mapping(address => mapping(address => uint256)) public userBorrowDepositedAmount;
    // key=tokenAddress,value=(key=userAddress,value=borrowAmount) 单位：USDC
    mapping(address => mapping(address => uint256)) public userBorrowAmount;
    // key=tokenAddress,value=(key=userAddress,value=borrowLastTime)
    mapping(address => mapping(address => uint256)) public userBorrowLastTime;
    mapping(address => mapping(address => uint256)) public userBorrowLastTimeCalculateFee;

    mapping(address => Collateral) public collaterals; // 记录每个抵押代币的相关信息

    struct Collateral {
        address tokenAddress; // 代币地址
        uint256 utilizationRate; // 利用率
        uint256 borrowed; // 已抵押数量
        uint256 borrowable; // 可抵押数量
        uint256 healthFactor; // 健康因子
        uint256 liquidationThreshold; // 清算阈值
        uint256 collateralizationRatio; // 抵押率
        uint256 riskFactor; // 风险值（6位精度）
        uint256 maxBorrowableRatio; // 最大可借比例（基于风险调整）
    }

    event DepositLend(address indexed user, address pool, uint256 amount);
    event DepositLendWithdraw(address indexed pool, address user, uint256 amount);
    event DepositBorrow(address indexed user, address indexed tokenAddress, uint256 amount);
    event DepositBorrowWithdraw(address indexed user, address indexed tokenAddress, uint256 amount);
    event Liquidate(address indexed liquidator, address indexed liquidated, address indexed tokenAddress, uint256 usdcAmount);
    event CalculateBorrowable(address indexed collateralAddress, uint256 borrowable);
    event StatusChanged(uint256 utilizationRate, uint256 totalBorrow, uint256 totalDeposits, uint256 interestRate);
    event CollateralChanged(
        address indexed tokenAddress,
        uint256 utilizationRate,
        uint256 borrowed,
        uint256 borrowable,
        uint256 interestRate,
        uint256 healthFactor,
        uint256 liquidationThreshold,
        uint256 collateralizationRatio
    );

    // 构造函数替换为初始化函数
    function initialize(
        address _feeReceiver,
        address _aaveTokenAddress,
        address _usdcTokenAddress,
        address _chainlinkAddress
    ) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        _inner_initialize(_feeReceiver, _aaveTokenAddress, _usdcTokenAddress, _chainlinkAddress);
    }

    function _inner_initialize(
        address _feeReceiver,
        address _aaveTokenAddress,
        address _usdcTokenAddress,
        address _chainlinkAddress
    ) internal {
        feeReceiver = _feeReceiver;
        aaveTokenAddress = _aaveTokenAddress;
        usdcTokenAddress = _usdcTokenAddress;
        chainlinkAddress = _chainlinkAddress;
    }

    // UUPS 升级授权
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function getFeeReceiver() external view returns (address) {
        return feeReceiver;
    }

    function getAaveTokenAddress() external view returns (address) {
        return aaveTokenAddress;
    }

    function getUsdcTokenAddress() external view returns (address) {
        return usdcTokenAddress;
    }

    function getChainlinkAddress() external view returns (address) {
        return chainlinkAddress;
    }

    function getUserLendLastTime(address userAddress) public view returns (uint256){
        return userLendLastTime[userAddress];
    }

    function setUserLendLastTime(address userAddress, uint256 time) public {
        userLendLastTime[userAddress] = time;
    }

    function setUserLendLastTimeCalculateFee(address userAddress, uint256 time) public {
        userLendLastTimeCalculateFee[userAddress] = time;
    }

    function setCollateral(
        address _tokenAddress, 
        uint256 _healthFactor, 
        uint256 _liquidationThreshold, 
        uint256 _collateralizationRate,
        uint256 _riskFactor
    ) external onlyOwner {
        require(_tokenAddress != address(0), "Invalid token address");
        require(collaterals[_tokenAddress].tokenAddress == address(0), "Collateral already exists");
        require(_riskFactor <= RATE_DECIMALS, "Risk factor cannot exceed 100%");
        
        uint256 maxBorrowableRatio = DynamicInterestRateCalculator.calculateCollateralizationAdjustment(_riskFactor);
        collaterals[_tokenAddress] = Collateral(
            _tokenAddress, 
            0, 
            0, 
            0, 
            _healthFactor, 
            _liquidationThreshold, 
            _collateralizationRate,
            _riskFactor,
            maxBorrowableRatio
        );
        supportedCollateralAddresses.push(_tokenAddress);
    }

    function updateCollateralRisk(address _tokenAddress, uint256 _riskFactor) external onlyOwner {
        require(collaterals[_tokenAddress].tokenAddress == _tokenAddress, "Collateral does not exist");
        require(_riskFactor <= RATE_DECIMALS, "Risk factor cannot exceed 100%");
        
        collaterals[_tokenAddress].riskFactor = _riskFactor;
        collaterals[_tokenAddress].maxBorrowableRatio = DynamicInterestRateCalculator.calculateCollateralizationAdjustment(_riskFactor);
        
        // Recalculate borrowable amounts after risk update
        _calculateBorrowable();
    }

    function setReserveFactor(uint256 _reserveFactor) external onlyOwner {
        require(_reserveFactor <= RATE_DECIMALS, "Reserve factor cannot exceed 100%");
        reserveFactor = _reserveFactor;
    }

    function getCollateral(address _tokenAddress) public view returns (Collateral memory) {
        return collaterals[_tokenAddress];
    }

    function setInterestRate(uint256 _interestRate) external onlyOwner {
        require(_interestRate > 0 && _interestRate <= RATE_DECIMALS, "Interest rate must be between 0 and 1000000");
        interestRate = _interestRate;
    }

    function getInterestRate() external view returns (uint256) {
        return interestRate;
    }

    function setLiquidationPenaltyFeeRate4Protocol(uint256 _liquidationPenaltyFeeRate4Protocol) external onlyOwner {
        require(_liquidationPenaltyFeeRate4Protocol > 0 && _liquidationPenaltyFeeRate4Protocol <= RATE_DECIMALS, "Interest rate must be between 0 and 1000000");
        liquidationPenaltyFeeRate4Protocol = _liquidationPenaltyFeeRate4Protocol;
    }

    function getLiquidationPenaltyFeeRate4Protocol() public view returns (uint256) {
        return liquidationPenaltyFeeRate4Protocol;
    }

    function setLiquidationPenaltyFeeRate4Cleaner(uint256 _liquidationPenaltyFeeRate4Cleaner) external onlyOwner {
        require(_liquidationPenaltyFeeRate4Cleaner > 0 && _liquidationPenaltyFeeRate4Cleaner <= RATE_DECIMALS, "Interest rate must be between 0 and 1000000");
        liquidationPenaltyFeeRate4Cleaner = _liquidationPenaltyFeeRate4Cleaner;
    }

    function getLiquidationPenaltyFeeRate4Cleaner() public view returns (uint256) {
        return liquidationPenaltyFeeRate4Cleaner;
    }

    function getUtilizationRate() public view returns (uint256) {
        if (totalLend == 0) {
            return 0;
        }
        return (totalBorrow * RATE_DECIMALS / totalLend);
    }

    function getTotalBorrow() public view returns (uint256) {
        return totalBorrow;
    }

    function getTotalLend() public view returns (uint256) {
        return totalLend;
    }

    function getUserLend(address _userAddress) public view returns (uint256) {
        return userLendAmount[_userAddress];
    }

    function getUserDepositedBorrow(address _tokenAddress, address _userAddress) public view returns (uint256) {
        return userBorrowDepositedAmount[_tokenAddress][_userAddress];
    }

    function getUserDepositedBorrowAmount(address _tokenAddress, address _userAddress) public view returns (uint256) {
        return userBorrowAmount[_tokenAddress][_userAddress];
    }

    // 当借出钱时，实时计算动态利率
    function _getDynamicBorrowRate(address _tokenAddress) internal view returns (uint256) {
        require(collaterals[_tokenAddress].tokenAddress == _tokenAddress, "Invalid collateral address");
        uint256 utilizationRate = collaterals[_tokenAddress].utilizationRate;
        return DynamicInterestRateCalculator.calculateBorrowRate(utilizationRate);
    }

    // 计算存款利率
    function _getDynamicSupplyRate() internal view returns (uint256) {
        uint256 globalUtilizationRate = getUtilizationRate();
        uint256 borrowRate = DynamicInterestRateCalculator.calculateBorrowRate(globalUtilizationRate);
        return DynamicInterestRateCalculator.calculateSupplyRate(globalUtilizationRate, borrowRate, reserveFactor);
    }

    // 获取特定抵押品的当前借贷利率
    function getCurrentBorrowRate(address _tokenAddress) external view returns (uint256) {
        return _getDynamicBorrowRate(_tokenAddress);
    }

    // 获取当前存款利率
    function getCurrentSupplyRate() external view returns (uint256) {
        return _getDynamicSupplyRate();
    }

    function _statusChanged() internal {
        emit StatusChanged(
            getUtilizationRate(),
            totalBorrow,
            totalLend,
            interestRate
        );
    }

    function _collateralChanged() internal {
        for (uint256 i = 0; i < supportedCollateralAddresses.length; i++) {
            address _tokenAddress = supportedCollateralAddresses[i];
            uint256 collateralUtilizationRate = collaterals[_tokenAddress].utilizationRate;
            uint256 borrowed = collaterals[_tokenAddress].borrowed;
            uint256 borrowable = collaterals[_tokenAddress].borrowable;
            uint256 collateralInterestRate = _getDynamicBorrowRate(_tokenAddress);
            uint256 healthFactor = collaterals[_tokenAddress].healthFactor;
            uint256 liquidationThreshold = collaterals[_tokenAddress].liquidationThreshold;
            uint256 collateralizationRatio = collaterals[_tokenAddress].collateralizationRatio;
            emit CollateralChanged(
                _tokenAddress,
                collateralUtilizationRate,
                borrowed,
                borrowable,
                collateralInterestRate,
                healthFactor,
                liquidationThreshold,
                collateralizationRatio);
        }
    }

    // _depositLend(借入)
    function depositLend(uint256 _amount) external {
        require(_amount > 0, "Invalid amount");
        uint256 nowTimestamp = block.timestamp;
        if (userLendLastTime[msg.sender] > 0) {
            // 需要计息了
            uint256 timePassed = nowTimestamp - userLendLastTimeCalculateFee[msg.sender];
            uint256 fee = getFee(userLendAmount[msg.sender], _getDynamicSupplyRate(), timePassed);
            if (fee > 0) {
                // 每次交易时，都会将利息给一部分给平台
                uint256 platformInterest = fee * liquidationPenaltyFeeRate4Protocol / RATE_DECIMALS;
                uint256 userInterest = fee - platformInterest;
                feeReceiverAmount += platformInterest;
                // 加上利息
                userLendAmount[msg.sender] += userInterest;
                totalLend += userInterest;
                userLendLastTimeCalculateFee[msg.sender] = nowTimestamp;
            }
        }
        // 记录当前用户的借入数量
        userLendAmount[msg.sender] += _amount;
        // 借入总数量增加
        totalLend += _amount;
        // 记录用户最后一次借入时间
        userLendLastTime[msg.sender] = nowTimestamp;
        if (userLendLastTimeCalculateFee[msg.sender] == 0) {
            userLendLastTimeCalculateFee[msg.sender] = nowTimestamp;
        }
        // 重新计算borrowable数量
        _calculateBorrowable();
        // 将代币转入该平台合约
        IERC20(usdcTokenAddress).transferFrom(msg.sender, address(this), _amount);
        emit DepositLend(msg.sender, address(this), _amount);
        _statusChanged();
        _collateralChanged();
    }

    // _depositWithdraw（借入取钱）
    function depositLendWithdraw(uint256 _amount) external {
        require(_amount > 0, "Invalid amount");
        require(_getTotalBorrowable() >= _amount, "no more money");
        uint256 nowTimestamp = block.timestamp;
        uint256 timePassed = nowTimestamp - userLendLastTimeCalculateFee[msg.sender];
        uint256 fee = getFee(userLendAmount[msg.sender], _getDynamicSupplyRate(), timePassed);
        if (fee > 0) {
            // 有利息时，分一部分利息的钱给平台，剩下的给用户
            // 修改状态
            uint256 platformInterest = fee * liquidationPenaltyFeeRate4Protocol / RATE_DECIMALS;
            uint256 userInterest = fee - platformInterest;
            // 自己账户是否有这么多
            require((userLendAmount[msg.sender] + userInterest) >= _amount, "no more money");
            feeReceiverAmount += platformInterest;
            userLendAmount[msg.sender] += userInterest;
            totalLend += userInterest;
            userLendLastTimeCalculateFee[msg.sender] = nowTimestamp;
        }
        userLendAmount[msg.sender] -= _amount;
        totalLend -= _amount;
        // 重新计算borrowable数量
        _calculateBorrowable();
        // 最终将钱转给用户
        IERC20(usdcTokenAddress).transfer(msg.sender, _amount);
        emit DepositLendWithdraw(address(this), msg.sender, _amount);
        _statusChanged();
        _collateralChanged();
    }

    // _depositWithdraw（借入取钱）
    function depositLendWithdrawAll() external {
        uint256 nowTimestamp = block.timestamp;
        uint256 timePassed = nowTimestamp - userLendLastTimeCalculateFee[msg.sender];
        uint256 fee = getFee(userLendAmount[msg.sender], _getDynamicSupplyRate(), timePassed);
        if (fee > 0) {
            // 有利息时，分一部分利息的钱给平台，剩下的给用户
            // 修改状态
            uint256 platformInterest = fee * liquidationPenaltyFeeRate4Protocol / RATE_DECIMALS;
            uint256 userInterest = fee - platformInterest;
            feeReceiverAmount += platformInterest;
            userLendAmount[msg.sender] += userInterest;
            totalLend += userInterest;
            userLendLastTimeCalculateFee[msg.sender] = nowTimestamp;
        }
        require(_getTotalBorrowable() >= userLendAmount[msg.sender], "no more money");
        uint256 total = userLendAmount[msg.sender];
        userLendAmount[msg.sender] = 0;
        totalLend -= total;
        // 重新计算borrowable数量
        _calculateBorrowable();
        // 最终将钱转给用户
        IERC20(usdcTokenAddress).transfer(msg.sender, total);
        emit DepositLendWithdraw(address(this), msg.sender, total);
        _statusChanged();
        _collateralChanged();
    }

    // _amount为dollar数量，转为usdc数量
    function _transferDollar2USDC(uint256 _amount) internal view returns (uint256) {
        uint256 usdcPrice = IChainlink(chainlinkAddress).getTokenPrice(usdcTokenAddress);
        // _amount=0.1,usdcPrice=1
        return _amount * DOLLAR_DECIMALS / usdcPrice * TOKEN_DECIMALS / DOLLAR_DECIMALS;
    }

    // 平台分利息的取钱
    function feeReceiverWithdraw(uint256 _amount) external {
        require(msg.sender == feeReceiver, "Only fee receiver can withdraw");
        require(feeReceiverAmount >= _amount, "Not enough fee receiver amount");
        feeReceiverAmount -= _amount;
        IERC20(usdcTokenAddress).transferFrom(address(this), msg.sender, _amount);
    }

    // 计算复利利息
    function getFee(uint256 _supply, uint256 rate, uint256 _eclipsedTime) public pure returns (uint256) {
        return _supply.calculateCompoundInterest(rate, _eclipsedTime);
    }

    // _depositBorrow 抵押借出（_tokenAddress为抵押代币地址，_amount为抵押数量）
    function depositBorrow(address _tokenAddress, uint256 _amount) external {
        require(_amount > 0, "Invalid amount");
        require(collaterals[_tokenAddress].tokenAddress == _tokenAddress, "Invalid collateral address");
        Collateral storage collateral = collaterals[_tokenAddress];
        // 获取抵押代币与usdc的价格比率
        uint256 tokenPrice = IChainlink(chainlinkAddress).getTokenPrice(_tokenAddress);
        uint256 usdcPrice = IChainlink(chainlinkAddress).getTokenPrice(usdcTokenAddress);
        // 计算能抵押多少usdc出来
        uint256 collateralizationRatio = collateral.collateralizationRatio;
        // 计算抵押代币的数量
        uint256 borrowUSDCAmount = _amount * tokenPrice * DOLLAR_DECIMALS / usdcPrice / DOLLAR_DECIMALS * collateralizationRatio / RATE_DECIMALS;
        uint256 nowTimestamp = block.timestamp;
        uint256 protocolFee = 0;
        uint256 borrowFee = 0;
        // 是否借出过
        if (userBorrowLastTime[_tokenAddress][msg.sender] != 0) {
            // 第二次借出时，累加借出的利息
            uint256 timePassed = nowTimestamp - userBorrowLastTimeCalculateFee[_tokenAddress][msg.sender];
            borrowFee = getFee(borrowUSDCAmount, _getDynamicBorrowRate(_tokenAddress), timePassed);
            if (borrowFee > 0) {
                // 平台收入fee
                protocolFee = borrowFee * liquidationPenaltyFeeRate4Protocol / RATE_DECIMALS;
                userBorrowLastTimeCalculateFee[_tokenAddress][msg.sender] = nowTimestamp;
            }
        }
        // 对比_tokenAddress对应的borrowable是否足够
        require(collateral.borrowable >= borrowUSDCAmount, "Not enough borrowable");
        feeReceiverAmount += protocolFee;
        collateral.borrowed += borrowUSDCAmount;
        totalBorrow += borrowUSDCAmount;
        userBorrowAmount[_tokenAddress][msg.sender] += borrowUSDCAmount;
        userBorrowDepositedAmount[_tokenAddress][msg.sender] = _amount;
        bool isNotIn = true;
        for (uint256 i; i < tokenBorrower[_tokenAddress].length; i++) {
            if (tokenBorrower[_tokenAddress][i] == msg.sender) {
                isNotIn = false;
            }
        }
        if (isNotIn) {
            tokenBorrower[_tokenAddress].push(msg.sender);
        }
        // 记录用户借出时间
        userBorrowLastTime[_tokenAddress][msg.sender] = nowTimestamp;
        if (userBorrowLastTimeCalculateFee[_tokenAddress][msg.sender] == 0) {
            userBorrowLastTimeCalculateFee[_tokenAddress][msg.sender] = nowTimestamp;
        }
        // 重新计算borrowable数量
        _calculateBorrowable();
        // 转移抵押代币到该平台合约
        IERC20(_tokenAddress).transferFrom(msg.sender, address(this), _amount);
        // 将相应的usdc转给用户
        IERC20(usdcTokenAddress).transfer(msg.sender, borrowUSDCAmount - borrowFee);
        emit DepositBorrow(msg.sender, _tokenAddress, borrowUSDCAmount);
        _statusChanged();
        _collateralChanged();
    }

    // _depositBorrowWithdraw，抵押借出
    function depositBorrowWithdraw(address _tokenAddress) external {
        require(collaterals[_tokenAddress].tokenAddress == _tokenAddress, "Invalid collateral address");
        require(userBorrowDepositedAmount[_tokenAddress][msg.sender] > 0, "No deposited amount");
        // 计算出需要还多少钱usdc（上次借的钱+从上次借到现在的利息）
        uint256 nowTimestamp = block.timestamp;
        uint256 timePassed = nowTimestamp - userBorrowLastTimeCalculateFee[_tokenAddress][msg.sender];
        uint256 lastTimeUserBorrowAmount = userBorrowAmount[_tokenAddress][msg.sender];
        uint256 fee = getFee(lastTimeUserBorrowAmount, _getDynamicBorrowRate(_tokenAddress), timePassed);
        uint256 protocolFee = fee * liquidationPenaltyFeeRate4Protocol / RATE_DECIMALS;
        // 总共需要还的钱
        uint256 needRepayAmount = lastTimeUserBorrowAmount + fee;
        uint256 wholeAmount = IERC20(usdcTokenAddress).balanceOf(msg.sender);
        require(wholeAmount >= needRepayAmount, "Not enough balance");
        // 将用户的所有数据清零，总的状态要扣减
        totalBorrow -= lastTimeUserBorrowAmount;
        collaterals[_tokenAddress].borrowed -= lastTimeUserBorrowAmount;
        userBorrowAmount[_tokenAddress][msg.sender] = 0;
        userBorrowLastTime[_tokenAddress][msg.sender] = 0;
        userBorrowLastTimeCalculateFee[_tokenAddress][msg.sender] = 0;
        feeReceiverAmount += protocolFee;
        // 重新计算borrowable数量
        _calculateBorrowable();
        // 开始还钱
        IERC20(usdcTokenAddress).transferFrom(msg.sender, address(this), needRepayAmount);
        // 平台将抵押代币转给用户
        IERC20(_tokenAddress).transfer(msg.sender, userBorrowDepositedAmount[_tokenAddress][msg.sender]);
        emit DepositBorrowWithdraw(msg.sender, _tokenAddress, userBorrowDepositedAmount[_tokenAddress][msg.sender]);
        _statusChanged();
        _collateralChanged();
    }

    // 计算剩下的流动性（totalLend-totalBorrow）
    function _getTotalBorrowable() internal view returns (uint256) {
        return totalLend - totalBorrow;
    }

    // 计算borrowable公式，基于风险调整的分配
    function _calculateBorrowable() internal {
        uint256 totalBorrowable = totalLend - totalBorrow;
        if (totalBorrowable == 0 || supportedCollateralAddresses.length == 0) {
            return;
        }

        // 计算总的风险调整权重
        uint256 totalRiskAdjustedWeight = 0;
        for (uint256 i = 0; i < supportedCollateralAddresses.length; i++) {
            address collateralAddress = supportedCollateralAddresses[i];
            Collateral storage collateral = collaterals[collateralAddress];
            totalRiskAdjustedWeight += collateral.maxBorrowableRatio;
        }

        // 根据风险调整权重分配borrowable
        for (uint256 i = 0; i < supportedCollateralAddresses.length; i++) {
            address collateralAddress = supportedCollateralAddresses[i];
            Collateral storage collateral = collaterals[collateralAddress];
            
            // 基于风险调整的borrowable分配
            collateral.borrowable = (totalBorrowable * collateral.maxBorrowableRatio) / totalRiskAdjustedWeight;
            
            // 计算利用率
            uint256 totalSupply = collateral.borrowable + collateral.borrowed;
            if (totalSupply > 0) {
                collateral.utilizationRate = (collateral.borrowed * RATE_DECIMALS) / totalSupply;
            } else {
                collateral.utilizationRate = 0;
            }
            
            emit CalculateBorrowable(collateralAddress, collateral.borrowable);
        }
    }

    // 检查有哪些人需要被清算
    function checkLiquidate(address _tokenAddress) public view returns (ReturnLiquidateInfo[] memory) {
        require(collaterals[_tokenAddress].tokenAddress == _tokenAddress, "invalid collateral address");
        // 逻辑：健康因子 = (所有抵押品价值 × 各自的清算阈值) / 总债务价值，当健康因子小于等于1时，就需要被清算
        // 健康因子 = （100个degen * 2dollar * 800000）/ 120个usdc * 1dollar
        // 健康因子 = 100 * 2 * 800000 / 120 * 1 = 1000000
        // 100 * a * 0.8 = 120 * b
        // 80a=120b
        // a=1.5b
        // b = 1
        // a = 1.5
        Collateral storage collateral = collaterals[_tokenAddress];
        // 抵押品单价
        uint256 tokenPrice = IChainlink(chainlinkAddress).getTokenPrice(_tokenAddress);
        uint256 usdcPrice = IChainlink(chainlinkAddress).getTokenPrice(usdcTokenAddress);
        // 遍历该抵押代币下的所有用户
        address[] memory borrowers = tokenBorrower[_tokenAddress];
        uint256 count = 0;
        if (borrowers.length > 0) {
            uint256 nowTimestamp = block.timestamp;
            // 计算每个用户的总债务（单位为dollar）
            for (uint256 i; i < borrowers.length; i++) {
                address borrower = borrowers[i];
                uint256 timePassed = nowTimestamp - userBorrowLastTimeCalculateFee[_tokenAddress][borrower];
                uint256 latestFee = getFee(userBorrowAmount[_tokenAddress][borrower], _getDynamicBorrowRate(_tokenAddress), timePassed);
                uint256 userTotal = userBorrowAmount[_tokenAddress][borrower] + latestFee;
                // 总债务
                uint256 userTotalDollar = userTotal * usdcPrice;
                // 抵押品
                uint256 userDepositedDollar = userBorrowDepositedAmount[_tokenAddress][borrower] * tokenPrice;
                // 健康因子
                uint256 healthFactor = (userDepositedDollar * collateral.liquidationThreshold) / userTotalDollar;
                if (healthFactor <= RATE_DECIMALS) {
                    count += 1;
                }
            }
            if (count > 0) {
                ReturnLiquidateInfo[] memory returnLiquidateInfos = new ReturnLiquidateInfo[](count);
                uint index = 0;
                for (uint256 i; i < borrowers.length; i++) {
                    address borrower = borrowers[i];
                    uint256 timePassed = nowTimestamp - userBorrowLastTimeCalculateFee[_tokenAddress][borrower];
                    uint256 latestFee = getFee(userBorrowAmount[_tokenAddress][borrower], _getDynamicBorrowRate(_tokenAddress), timePassed);
                    uint256 userTotal = userBorrowAmount[_tokenAddress][borrower] + latestFee;
                    // 总债务
                    uint256 userTotalDollar = userTotal * usdcPrice;
                    // 抵押品
                    uint256 userDepositedDollar = userBorrowDepositedAmount[_tokenAddress][borrower] * tokenPrice;
                    // 健康因子
                    uint256 healthFactor = (userDepositedDollar * collateral.liquidationThreshold) / userTotalDollar;
                    if (healthFactor <= RATE_DECIMALS) {
                        returnLiquidateInfos[index] = ReturnLiquidateInfo(
                            borrower,
                            usdcPrice,
                            tokenPrice,
                            userTotal,
                            userBorrowDepositedAmount[_tokenAddress][borrower],
                            healthFactor,
                            collateral.liquidationThreshold
                        );
                        index += 1;
                    }
                }
                return returnLiquidateInfos;
            }
        }
        return new ReturnLiquidateInfo[](0);
    }

    struct ReturnLiquidateInfo {
        address borrower;
        uint256 usdcPrice;
        uint256 tokenPrice;
        uint256 userTotal;
        uint256 userDeposited;
        uint256 healthFactor;
        uint256 liquidationThreshold;
    }

    // 开始清算
    function liquidate(address _tokenAddress, address _borrower, uint256 _amount) external {
        uint256 nowTimestamp = block.timestamp;
        uint256 timePassed = nowTimestamp - userBorrowLastTimeCalculateFee[_tokenAddress][_borrower];
        uint256 tokenPrice = IChainlink(chainlinkAddress).getTokenPrice(_tokenAddress);
        uint256 usdcPrice = IChainlink(chainlinkAddress).getTokenPrice(usdcTokenAddress);
        uint256 latestFee = getFee(userBorrowAmount[_tokenAddress][_borrower], _getDynamicBorrowRate(_tokenAddress), timePassed);
        uint256 protocolFee = latestFee * liquidationPenaltyFeeRate4Protocol / RATE_DECIMALS;
        uint256 userTotal = userBorrowAmount[_tokenAddress][_borrower] + latestFee;
        // 总债务
        uint256 userTotalDollar = userTotal * usdcPrice;
        // 抵押品
        uint256 userDepositedDollar = userBorrowDepositedAmount[_tokenAddress][_borrower] * tokenPrice;
        // 健康因子
        Collateral storage collateral = collaterals[_tokenAddress];
        uint256 healthFactor = (userDepositedDollar * collateral.liquidationThreshold) / userTotalDollar;
        if (latestFee > 0) {
            userBorrowLastTimeCalculateFee[_tokenAddress][_borrower] = nowTimestamp;
            userBorrowAmount[_tokenAddress][_borrower] += latestFee;
            totalBorrow += latestFee;
            feeReceiverAmount += protocolFee;
        }

        if (healthFactor <= RATE_DECIMALS) {
            uint256 returnAmount = _amount;
            // 需要被清算，清算的逻辑：将他借的钱usdc本金和usdc利息还一部分，还一部分后会得到一部分奖励，奖励的钱就是抵押的代币，就是还的钱的5%
            if (_amount >= userTotal) {
                // 替还的钱大于等于了被清算人的借的钱
                returnAmount = userTotal;
            }
            // 计算奖励
            uint256 rewardTokenAmountAndFee = returnAmount * usdcPrice * (RATE_DECIMALS + liquidationPenaltyFeeRate4Cleaner) / tokenPrice / (RATE_DECIMALS);
            // 120 * 1 * (1.05) / 1.4 = 100
            // 将还的usdc，从清算人还给平台
            IERC20(usdcTokenAddress).transferFrom(msg.sender, address(this), returnAmount);
            // 将代币和奖励的代币，从平台转给清算人
            IERC20(_tokenAddress).transfer(msg.sender, rewardTokenAmountAndFee);
            // 更新状态
            userBorrowAmount[_tokenAddress][_borrower] -= returnAmount;
            collaterals[_tokenAddress].borrowed -= returnAmount;
            totalBorrow -= returnAmount;
            // 重新计算borrowable数量
            _calculateBorrowable();
            emit Liquidate(msg.sender, _borrower, _tokenAddress, returnAmount);
        }
        _statusChanged();
        _collateralChanged();
    }

}
