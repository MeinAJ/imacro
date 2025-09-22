// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {

    constructor(string memory _name, string memory _symbol) public ERC20(_name, _symbol) {
    }

    function mint(address _to, uint256 _amount) public returns (bool) {
        _mint(_to, _amount);
        return true;
    }

    function burn(address _from, uint256 _amount) public returns (bool) {
        _burn(_from, _amount);
        return true;
    }

}
