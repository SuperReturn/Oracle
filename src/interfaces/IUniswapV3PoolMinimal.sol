// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;


interface IUniswapV3PoolMinimal {

    function observe(uint32[] calldata secondsAgos) external view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);
    
}