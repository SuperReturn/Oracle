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
error sSuperUSDOracle__RateExceedsMaximum();
error sSuperUSDOracle__InvalidMaxRate();
error sSuperUSDOracle__InvalidMinRate();
error sSuperUSDOracle__StalePrice();

contract sSuperUSDOracle is IsSuperUSDOracle {
    address public owner;
    address public sSuperUSDOracleAddress;
    
    // Max rate with 6 decimals (1.20 = 1_200_000)
    uint256 public maxRate = 1_200_000;
    // Min rate with 6 decimals (1.00 = 1_000_000)
    uint256 public minRate = 1_000_000;
    // Last successful update timestamp
    uint256 public lastUpdateTimestamp;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event sSuperUSDOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event MaxRateUpdated(uint256 oldMaxRate, uint256 newMaxRate);
    event MinRateUpdated(uint256 oldMinRate, uint256 newMinRate);
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

    function setMaxRate(uint256 _maxRate) external onlyOwner {
        if (_maxRate <= minRate) revert sSuperUSDOracle__InvalidMaxRate();
        uint256 oldMaxRate = maxRate;
        maxRate = _maxRate;
        emit MaxRateUpdated(oldMaxRate, _maxRate);
    }

    function setMinRate(uint256 _minRate) external onlyOwner {
        if (_minRate >= maxRate) revert sSuperUSDOracle__InvalidMinRate();
        uint256 oldMinRate = minRate;
        minRate = _minRate;
        emit MinRateUpdated(oldMinRate, _minRate);
    }

    function latestRoundData()
    public
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        uint256 rate;

        rate = IAccountant(sSuperUSDOracleAddress).getRate();
        
        // Enforce min rate of 1.0
        if (rate < minRate) {
            rate = minRate;
        }

        // Enforce max rate
        if (rate > maxRate) {
            rate = maxRate;
        }

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
