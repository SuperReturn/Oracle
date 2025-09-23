// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;


import { IUniswapV3PoolMinimal } from "./interfaces/IUniswapV3PoolMinimal.sol";
import { TickMath } from "./libraries/TickMath.sol";
import { FullMath } from "./libraries/FullMath.sol";
import { FixedPoint96 } from "./libraries/FixedPoint96.sol";


/// @title sSuperUSDFallbackOracle
/// @author SuperReturn
/// @notice An oracle contract that reads the TWAP from a Uniswap V3 pool.
contract sSuperUSDFallbackOracle {

    address public owner;
    uint32 public twapInterval;

    uint32 internal constant MAX_TWAP_INTERVAL = 604800; // one week

    address public immutable uniV3Pool;
    bool public immutable zeroForOne;
    uint8 public immutable decimals0;
    uint8 public immutable decimals1;
    uint256 internal immutable scale0;
    uint256 internal immutable scale1;
    uint256 internal constant scalePrice = 10**8; // 8 decimals

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TwapIntervalSet(uint32 twapInterval);

    /// @notice Construct the sSuperUSDFallbackOracle contract.
    /// @param _uniV3Pool The address of the Uniswap V3 pool.
    /// @param _zeroForOne The direction of the price measurement. True to return the price of token1 in terms of token0, false to return the price of token0 in terms of token1.
    /// @param _decimals0 The number of decimals of token0.
    /// @param _decimals1 The number of decimals of token1.
    /// @param _twapInterval The interval in seconds to look back in pool observations.
    constructor(
        address _uniV3Pool,
        bool _zeroForOne,
        uint8 _decimals0,
        uint8 _decimals1,
        uint32 _twapInterval
    ) {
        if(_uniV3Pool == address(0)) revert ("Pool cannot be zero address");
        _setTwapInterval(_twapInterval);
        uniV3Pool = _uniV3Pool;
        zeroForOne = _zeroForOne;
        decimals0 = _decimals0;
        decimals1 = _decimals1;
        scale0 = 10**_decimals0;
        scale1 = 10**_decimals1;
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
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

    function latestRoundData() external view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (0, _latestAnswer(), block.timestamp, block.timestamp, 0);
    }

    function latestAnswer() external view returns (int256) {
        return _latestAnswer();
    }

    function _latestAnswer() internal view returns (int256) {
        // create params for observations
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapInterval; // from (before)
        secondsAgos[1] = 0; // to (now)

        // read observations from pool
        (int56[] memory tickCumulatives, ) = IUniswapV3PoolMinimal(uniV3Pool).observe(secondsAgos);

        // calculate the difference in tickCumulatives
        int56 tickCumulativesDiff;
        // overflow of tickCumulative is desired per uni v3
        // dev: unchecked block only required in solidity 0.8.x
        unchecked {
            tickCumulativesDiff = tickCumulatives[1] - tickCumulatives[0];
        }

        // calculate average tick over interval
        int24 averageTick = toInt24(tickCumulativesDiff / int56(uint56(twapInterval)));

        // convert tick to sqrt price
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(averageTick);        

        // convert sqrt price to price at tick
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);
        
        // convert price to a useable format
        if(zeroForOne) {
            return int256(priceX96 * scale0 * scalePrice / (FixedPoint96.Q96 * scale1));
        } else {
            return int256(FixedPoint96.Q96 * scale1 * scalePrice / (priceX96 * scale0));
        }
    }

    function toInt24(int56 x) internal pure returns (int24) {
        if(x > type(int24).max || x < type(int24).min) revert ("Overflow cast to int24");
        return int24(x);
    }

    function setTwapInterval(uint32 _twapInterval) external onlyOwner {
        _setTwapInterval(_twapInterval);
    }

    function _setTwapInterval(uint32 _twapInterval) internal {
        if(_twapInterval == 0) revert ("Twap interval cannot be 0");
        if(_twapInterval > MAX_TWAP_INTERVAL) revert ("Twap interval too long");
        twapInterval = _twapInterval;
        emit TwapIntervalSet(_twapInterval);
    }
}