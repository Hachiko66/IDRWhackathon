// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract AggregatorV3Mock is AggregatorV3Interface {
    uint8 public override decimals;
    string public override description;
    uint256 public override version;
    int256 private _latestPrice;

    constructor(uint8 _decimals, int256 initialPrice) {
        decimals = _decimals;
        description = "Mock Price Feed";
        version = 1;
        _latestPrice = initialPrice;
    }

    function setLatestPrice(int256 newPrice) external {
        _latestPrice = newPrice;
    }

    function getRoundData(uint80 /*roundId*/ )
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        revert("Not implemented in mock");
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, _latestPrice, block.timestamp, block.timestamp, 1);
    }
}
