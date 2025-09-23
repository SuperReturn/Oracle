// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IsSuperUSDOracle} from "./interfaces/IsSuperUSDOracle.sol";
import {IAccountant} from "./interfaces/IAccountant.sol";


contract sSuperUSDOracle is IsSuperUSDOracle {
    address public owner;
    address public immutable sSuperUSDAccountant;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address _sSuperUSDAccountant) {
        require(_sSuperUSDAccountant != address(0), "Accountant cannot be zero address");
        owner = msg.sender;
        sSuperUSDAccountant = _sSuperUSDAccountant;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner cannot be zero address");
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    function latestRoundData()
        public
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        // revert if accountant is paused
        uint256 rate = IAccountant(sSuperUSDAccountant).getRateSafe();
        uint256 timestamp = IAccountant(sSuperUSDAccountant).accountantState().lastUpdateTimestamp;

        // Convert from 6 decimals to 8 decimals
        uint256 adjustedRate = rate * 100;

        return (0, int256(adjustedRate), timestamp, timestamp, 0);
    }
}
