// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IsSuperUSDOracle} from "./interfaces/IsSuperUSDOracle.sol";
import {IAccountant} from "./interfaces/IAccountant.sol";

contract sSuperUSDOracle is IsSuperUSDOracle {
    address public owner;
    address public immutable superUSDAccountant;
    address public immutable sSuperUSDAccountant;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address _superUSDAccountant, address _sSuperUSDAccountant) {
        require(_sSuperUSDAccountant != address(0), "Accountant cannot be zero address");
        require(_superUSDAccountant != address(0), "Accountant cannot be zero address");
        owner = msg.sender;
        superUSDAccountant = _superUSDAccountant;
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
        uint256 superUSDRate = IAccountant(superUSDAccountant).getRateSafe(); // 6 decimals
        uint256 sSuperUSDRate = IAccountant(sSuperUSDAccountant).getRateSafe(); // 6 decimals

        uint256 superUSDTimestamp = IAccountant(superUSDAccountant).accountantState().lastUpdateTimestamp;
        uint256 sSuperUSDTimestamp = IAccountant(sSuperUSDAccountant).accountantState().lastUpdateTimestamp;

        uint256 timestamp = superUSDTimestamp > sSuperUSDTimestamp ? sSuperUSDTimestamp : superUSDTimestamp;

        // Convert from 6 decimals to 8 decimals
        uint256 adjustedRate = sSuperUSDRate * superUSDRate / 1e4; // 6 + 6 - 8 decimals

        return (0, int256(adjustedRate), timestamp, timestamp, 0);
    }
}
