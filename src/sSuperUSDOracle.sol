// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IsSuperUSDOracle {
    function latestRoundData()
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

interface IAccountant {
    function getRate() external view returns (uint256);
}

error AccountantWithRateProviders__Paused();
error sSuperUSDOracle__StalePrice();

contract sSuperUSDOracle is IsSuperUSDOracle {
    address public owner;
    address public sSuperUSDOracleAddress;
    
    // Last successful update timestamp
    uint256 public lastUpdateTimestamp;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event sSuperUSDOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event RateUpdated(uint256 indexed roundId, uint256 rate, uint256 timestamp);

    constructor() {
        owner = msg.sender;
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

    function setsSuperUSDOracle(address _sSuperUSDOracleAddress) external onlyOwner {
        address oldOracle = sSuperUSDOracleAddress;
        sSuperUSDOracleAddress = _sSuperUSDOracleAddress;
        emit sSuperUSDOracleUpdated(oldOracle, _sSuperUSDOracleAddress);
    }

    function latestRoundData()
    public
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        uint256 rate = IAccountant(sSuperUSDOracleAddress).getRate();
        
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
