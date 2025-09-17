// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;


/// @title IsSuperUSDOracle
/// @notice Interface for sSuperUSD Oracle that provides exchange rate data
interface IsSuperUSDOracle {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    
    // Add accountant getter
    function sSuperUSDAccountant() external view returns (address);
}