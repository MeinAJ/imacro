// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {IChainlink} from "./IChainlink.sol";

contract Chainlink is IChainlink {

    // address => token price in USD，value = dollar price，decimal = 2
    mapping(address => uint256) public tokenDollarPrice;

    function setTokenPrice(address token, uint256 price) public override {
        require(price > 0, "Price should be greater than 0");
        require(token != address(0), "Token address should not be 0x0");
        tokenDollarPrice[token] = price;
    }

    function getTokenPrice(address token) public override view returns (uint256) {
        require(tokenDollarPrice[token] > 0, "Token price should be set");
        return tokenDollarPrice[token];
    }

}
