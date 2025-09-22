// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface IChainlink {

    function setTokenPrice(address token, uint256 price) external;

    function getTokenPrice(address token) external view returns (uint256);

}
