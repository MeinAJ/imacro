const {ethers} = require("hardhat");

//     event DepositLend(address indexed user, address pool, uint256 amount);
//     event DepositLendWithdraw(address indexed pool, address user, uint256 amount);
//     event DepositBorrow(address indexed user, address indexed tokenAddress, uint256 amount);
//     event DepositBorrowWithdraw(address indexed user, address indexed tokenAddress, uint256 amount);
//     event Liquidate(address indexed liquidator, address indexed liquidated, address indexed tokenAddress, uint256 usdcAmount);
//     event CalculateBorrowable(address indexed collateralAddress, uint256 borrowable);
//     event StatusChanged(uint256 utilizationRate, uint256 totalBorrow, uint256 totalDeposits, uint256 interestRate);
//     event CollateralChanged(
//         address indexed tokenAddress,
//         uint256 utilizationRate,
//         uint256 borrowed,
//         uint256 borrowable,
//         uint256 healthFactor,
//         uint256 liquidationThreshold,
//         uint256 collateralizationRatio
//     );

const eventSignature = "DepositLend(address,address,uint256)";
const eventTopic = ethers.keccak256(ethers.toUtf8Bytes(eventSignature));
console.log("DepositLend eventTopic:", eventTopic);

const eventSignature2 = "DepositLendWithdraw(address,address,uint256)";
const eventTopic2 = ethers.keccak256(ethers.toUtf8Bytes(eventSignature2));
console.log("DepositLendWithdraw eventTopic:", eventTopic2);

const eventSignature3 = "DepositBorrow(address,address,uint256)";
const eventTopic3 = ethers.keccak256(ethers.toUtf8Bytes(eventSignature3));
console.log("DepositBorrow eventTopic:", eventTopic3);

const eventSignature4 = "DepositBorrowWithdraw(address,address,uint256)";
const eventTopic4 = ethers.keccak256(ethers.toUtf8Bytes(eventSignature4));
console.log("DepositBorrowWithdraw eventTopic:", eventTopic4);

const eventSignature5 = "Liquidate(address,address,address,uint256)";
const eventTopic5 = ethers.keccak256(ethers.toUtf8Bytes(eventSignature5));
console.log("Liquidate eventTopic:", eventTopic5);

const eventSignature6 = "CalculateBorrowable(address,uint256)";
const eventTopic6 = ethers.keccak256(ethers.toUtf8Bytes(eventSignature6));
console.log("CalculateBorrowable eventTopic:", eventTopic6);

const eventSignature7 = "StatusChanged(uint256,uint256,uint256,uint256)";
const eventTopic7 = ethers.keccak256(ethers.toUtf8Bytes(eventSignature7));
console.log("StatusChanged eventTopic:", eventTopic7);

const eventSignature8 = "CollateralChanged(address,uint256,uint256,uint256,uint256,uint256,uint256,uint256)";
const eventTopic8 = ethers.keccak256(ethers.toUtf8Bytes(eventSignature8));
console.log("CollateralChanged eventTopic:", eventTopic8);