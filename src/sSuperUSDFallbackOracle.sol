// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;


//import { IsSuperUSDOracle } from "./interfaces/IsSuperUSDOracle.sol";
import { IUniswapV3PoolMinimal } from "./interfaces/IUniswapV3PoolMinimal.sol";
import { TickMath } from "./libraries/TickMath.sol";
import { FullMath } from "./libraries/FullMath.sol";
import { FixedPoint96 } from "./libraries/FixedPoint96.sol";


contract sSuperUSDFallbackOracle /*is IsSuperUSDOracle*/ {

    address public owner;
    uint32 public twapInterval;

    address public immutable uniV3Pool;
    bool public immutable zeroForOne;
    uint8 public immutable decimals0;
    uint8 public immutable decimals1;

    event TwapIntervalSet(uint32 twapInterval);

    constructor(
        address _uniV3Pool,
        bool _zeroForOne,
        uint8 _decimals0,
        uint8 _decimals1,
        uint32 _twapInterval
    ) {
        if(_uniV3Pool == address(0)) revert ("Pool cannot be zero address");
        uniV3Pool = _uniV3Pool;
        zeroForOne = _zeroForOne;
        decimals0 = _decimals0;
        decimals1 = _decimals1;
        _setTwapInterval(_twapInterval);
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    function latestAnswer() external view returns (int256) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapInterval; // from (before)
        secondsAgos[1] = 0; // to (now)

        (int56[] memory tickCumulatives, ) = IUniswapV3PoolMinimal(uniV3Pool).observe(secondsAgos);
        
        // tick(imprecise as it's an integer) to price
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
            toInt24((tickCumulatives[1] - tickCumulatives[0]) / int56(uint56(twapInterval)))
        );

        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);
        
        
        if(zeroForOne) {
            return int256(FullMath.mulDiv(priceX96, 10**decimals1, 10**decimals0));
        } else {
            return int256(FullMath.mulDiv(10**decimals0, 10**decimals1, priceX96));
        }
        
    }

    function toInt24(int56 x) internal pure returns (int24) {
        // todo: should this just truncate?
        if(x > type(int24).max) revert ("Overflow cast to int24");
        return int24(x);
    }

    /*
    function getPriceX96FromSqrtPriceX96(uint160 sqrtPriceX96) public pure returns(uint256 priceX96) {
        return FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);
    }
    */

    function setTwapInterval(uint32 _twapInterval) external onlyOwner {
        _setTwapInterval(_twapInterval);
    }

    function _setTwapInterval(uint32 _twapInterval) internal {
        if(_twapInterval == 0) revert ("Twap interval cannot be 0");
        twapInterval = _twapInterval;
    }
}