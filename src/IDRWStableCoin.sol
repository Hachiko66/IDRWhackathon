// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract IDRWStableCoin is ERC20Burnable, Ownable {
    error IDRWStableCoin__MustBeMoreThanZero();
    error IDRWStableCoin__BurnAmountExceedsBalance();
    error IDRWStableCoin__NotZeroAddress();
    error IDRWStableCoin__NotAuthorized();

    address public idrwEngine;

    constructor(address initialOwner) ERC20("IDRWStableCoin", "IDRW") Ownable(initialOwner) {}

    function setIDRWEngine(address _idrwEngine) external onlyOwner {
        if (_idrwEngine == address(0)) {
            revert IDRWStableCoin__NotZeroAddress();
        }
        idrwEngine = _idrwEngine;
    }

    function mint(address _to, uint256 _amount) external returns (bool) {
        if (_to == address(0)) {
            revert IDRWStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert IDRWStableCoin__MustBeMoreThanZero();
        }
        if (msg.sender != owner() && msg.sender != idrwEngine) {
            revert IDRWStableCoin__NotAuthorized();
        }
        _mint(_to, _amount);
        return true;
    }

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
}