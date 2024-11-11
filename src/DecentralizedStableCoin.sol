// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

/*
* @title Decentralized Stable Coin
* @dev This contract is a decentralized stable coin contract
* that is used to create a stable coin that is pegged to:
* Collateral: Exogenous (ETH & BTC)
* Relative Stability: Pegged to USD

* This contract is meant to be governed by DSCEngine.
* DSCEngine is a contract that is used to govern the stable coin
* and to ensure that the stable coin is pegged to the USD.
* This contract is just the ERC20 implementation of our stable coin system.
*/

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DecentralizedStableCoin is ERC20Burnable, Ownable {

    error DSC__MustBeMoreThanZero();
    error DSC__BurnAmountExceedsBalance();
    error DSC__NotZeroAddress();
    constructor() ERC20("DecentralizedStableCoin", "DSC"){

    }

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if(_amount <= 0) {
            revert DSC__MustBeMoreThanZero();
        }
        if(balance <= _amount) {
            revert DSC__BurnAmountExceedsBalance();
        }

        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns(bool) {
        if(_to == address(0)) {
            revert DSC__NotZeroAddress();
        }
        if(_amount <= 0) {
            revert DSC__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}