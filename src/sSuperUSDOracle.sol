// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { IAccountant } from "./interfaces/IAccountant.sol";
import { IsSuperUSDOracle } from "./interfaces/IsSuperUSDOracle.sol";


error AccountantWithRateProviders__Paused();
error sSuperUSDOracle__StalePrice();

contract sSuperUSDOracle is IsSuperUSDOracle {
    address public owner;
    address public immutable sSuperUSDAccountant;
    
    // Last successful update timestamp
    uint256 public lastUpdateTimestamp;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RateUpdated(uint256 indexed roundId, uint256 rate, uint256 timestamp);

    constructor(address _sSuperUSDAccountant) {
        require(_sSuperUSDAccountant != address(0), "Accountant cannot be zero address");
        owner = msg.sender;
        sSuperUSDAccountant = _sSuperUSDAccountant;
        lastUpdateTimestamp = block.timestamp;
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
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        uint256 rate = IAccountant(sSuperUSDAccountant).getRate();
        
        // Convert from 6 decimals to 8 decimals
        uint256 adjustedRate = rate * 100;
        
        return (
            0,
            int256(adjustedRate),
            lastUpdateTimestamp,
            lastUpdateTimestamp,
            0
        );
    }
}
