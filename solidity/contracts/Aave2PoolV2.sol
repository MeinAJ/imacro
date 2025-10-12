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

    uint256 public reserveFactor; // 储备金系数
    uint256 public reserveIndex; // 储备金指数
    uint256 public liquidityIndex; // 流动性指数
    uint256 public lastUpdatedTime; // 上次更新时间


    address public aaveTokenAddress; // 平台代币地址
    address public usdcTokenAddress; // USDC地址
    address public cUsdcTokenAddress; // cUSDC地址

    address public chainlinkAddress; // 链上价格源地址


    address[] public supportedCollateralAddresses; // 支持的抵押代币地址

    uint256 public liquidationPenaltyFeeRate4Cleaner; // 清算惩罚费率，清算人收入


    // utilization rate
    uint256 public utilizationRate;
    // total borrow，单位：USDC
    uint256 public totalBorrow;
    // total deposits，单位：USDC
    uint256 public totalLend;


    // every address supply,key=user address,value=supply，单位：USDC
    mapping(address => LendRecord[]) public userLendAmount;

    // key=tokenAddress,value=userAddress[]
    mapping(address => address[]) public tokenBorrower;
    // key=tokenAddress,value=(key=userAddress,value=borrowDepositedAmount) 单位：代币
    mapping(address => mapping(address => BorrowRecord[])) public userBorrowAmount;

    mapping(address => Collateral) public collaterals; // 记录每个抵押代币的相关信息

    struct LendRecord {
        uint256 amount; // 存款数量
        uint256 liquidityIndex; // 历史存款流动性指数
        uint256 lastTime; // 最后存款时间
    }

    struct BorrowRecord {
        uint256 amount; // 借款数量
        uint256 liquidityIndex; // 历史借款流动性指数
        uint256 lastTime; // 最后借款时间
    }

    struct Collateral {
        address tokenAddress; // 代币地址
        uint256 utilizationRate; // 利用率
        uint256 borrowed; // 已抵押数量
        uint256 borrowable; // 可抵押数量
        uint256 healthFactor; // 健康因子
        uint256 liquidationThreshold; // 清算阈值
        uint256 collateralizationRatio; // 抵押率
        uint256 liquidityIndex; // 历史存款流动性指数
        uint256 lastTime; // 最后存款时间
    }

    // 构造函数替换为初始化函数
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
        reserveFactor = 10 ** 5; // 100000 = 10%
        reserveIndex = 10**18; // 初始储备金指数为10**18
        liquidityIndex = 10**18; // 初始流动性指数为10**18
        lastUpdatedTime = block.timestamp; // 初始时间戳为当前时间
        utilizationRate = 0; // 初始利用率为0
        totalBorrow = 0; // 初始借款总额为0
        totalLend = 0; // 初始存款总额为0
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

    // UUPS 升级授权
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setCollateral(
        address _tokenAddress, 
        uint256 _healthFactor, 
        uint256 _liquidationThreshold, 
        uint256 _collateralizationRate
    ) external onlyOwner {
        require(_tokenAddress != address(0), "Invalid token address");
        require(collaterals[_tokenAddress].tokenAddress == address(0), "Collateral already exists");

        collaterals[_tokenAddress] = Collateral(
            _tokenAddress, 
            0, 
            0, 
            0, 
            _healthFactor, 
            _liquidationThreshold, 
            _collateralizationRate,
            10**18, // 初始流动性指数为10**18
            block.timestamp // 初始时间戳为当前时间
        );
        supportedCollateralAddresses.push(_tokenAddress);
    }

    // _depositLend(借入) - Gas optimized version
    function depositLend(uint256 _amount) external {

    }
    // _depositWithdraw（借入取钱） - Gas optimized version
    function depositLendWithdraw(uint256 _amount) external {

    }
    // _depositBorrow 抵押借出（_tokenAddress为抵押代币地址，_amount为抵押数量） - Gas optimized version
    function depositBorrow(address _tokenAddress, uint256 _amount) external {

    }
    // _depositBorrowWithdraw，抵押借出
    function depositBorrowWithdraw(address _tokenAddress) external {

    }
    // 检查有哪些人需要被清算
    function checkLiquidate(address _tokenAddress) public view returns (ReturnLiquidateInfo[] memory) {

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

    }
}
