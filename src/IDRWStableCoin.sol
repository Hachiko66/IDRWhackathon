//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
 * @title: IDRW Stable Coin
 * @author: Goenawan Yuyun Manta Hackathon
 * Collateral: Exogenous (ETH & BTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to Collateral
 *
 * This is the contract meant to be governed by IDRWEngine. This contract is just the ERC20 implementation of our stablecoin system.
 */

contract IDRWStableCoin is ERC20Burnable, Ownable {
    error IDRWStableCoin__MustBeMoreThanZero();
    error IDRWStableCoin__BurnAmountExceedsBalance();
    error IDRWStableCoin__NotZeroAddress();

    constructor(address initialOwner) ERC20("IDRWStableCoin", "IDRW") Ownable(initialOwner) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert IDRWStableCoin__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert IDRWStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert IDRWStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert IDRWStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
