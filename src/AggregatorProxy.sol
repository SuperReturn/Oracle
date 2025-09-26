// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {IsSuperUSDOracle} from "./interfaces/IsSuperUSDOracle.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";

/// @title AggregatorProxy
/// @author SuperReturn
/// @notice Oracle contract for sSuperUSD
/// @dev This oracle gets the exchange rate from an external sSuperUSD oracle and converts it to Morpho format
contract AggregatorProxy is AggregatorV3Interface, ReentrancyGuard {
    using FixedPointMathLib for uint256;

    /**
     *
     * STATE VARIABLES
     *
     */

    /// @notice Maximum age of price feed in seconds before considering it stale
    uint256 public maxPriceAge = 24 hours;

    /// @notice The collateral token address
    address public immutable collateralToken;

    /// @notice The loan token address
    address public immutable loanToken;

    /// @notice The collateral token decimals
    uint8 public immutable collateralDecimals;

    /// @notice The loan token decimals
    uint8 public immutable loanDecimals;

    /// @notice The primary sSuperUSD oracle address that provides exchange rate
    address public sSuperUSDOracleAddress;

    /// @notice The fallback sSuperUSD oracle address used when primary fails
    address public sSuperUSDFallbackOracleAddress;

    /// @notice The owner of the contract who can update oracle addresses
    address public owner;

    /// @notice The base upper bound for calculating exchange rate limits (scaled by 1e4)
    uint256 public baseUpperBound = 10500; // 105% default

    /// @notice The base lower bound for calculating exchange rate limits (scaled by 1e4)
    uint256 public baseLowerBound = 9500; // 95% default

    /// @notice The EMA upper bound, same decimals as latestAnswer
    uint256 public EMAUpperBound;

    /// @notice The EMA lower bound, same decimals as latestAnswer
    uint256 public EMALowerBound;

    /// @notice The multiplier for EMA calculation (scaled by 1e4)
    /// @dev Calculated as: 2/(N+1) where N=10 (days)
    /// 2/(10+1) ≈ 0.2 = 20% = 2000 (scaled by 1e4)
    uint256 public multiplier = 2000; // 0.2 or 20% weight for new price

    /// @notice The latest EMA value
    int256 public latestEMA;

    /// @notice The latest answer
    int256 public latestAnswer;

    /// @notice Price of the most recent update from the primary oracle
    int256 public latestPrimaryPrice;

    /// @notice Price of the most recent update from the fallback oracle
    int256 public latestFallbackPrice;

    /// @notice Mapping of addresses that are allowed to execute updatePrice
    mapping(address => bool) public executors;

    /// @notice Minimum delay between EMA updates
    uint256 public minEMADelay = 1 hours;

    /// @notice The timestamp of the last EMA update
    uint256 public latestEMATime;

    /// @notice The timestamp of the last primary oracle update
    uint256 public latestPrimaryTime;

    /// @notice The timestamp of the last fallback oracle update
    uint256 public latestFallbackTime;

    /// @notice The timestamp of the latestAnswer update
    uint256 public latestUpdateTime;

    /// @notice Whether the primary oracle has reverted
    bool public isPrimaryReverted;

    /**
     *
     * EVENTS
     *
     */
    event PrimaryOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event FallbackOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event MaxPriceAgeUpdated(uint256 oldMaxAge, uint256 newMaxAge);
    event BoundsUpdated(uint256 newUpper, uint256 newLower);
    event MovingAverageUpdated(uint256 oldMA, uint256 newMA);
    event MultiplierUpdated(uint256 oldMultiplier, uint256 newMultiplier);
    event PrimaryPriceUsed(uint256 price);
    event FallbackPriceUsed(uint256 price, string reason);
    event BaseBoundsUpdated(uint256 oldUpperBound, uint256 oldLowerBound, uint256 newUpperBound, uint256 newLowerBound);
    event NoPriceUpdate(string reason, uint256 primaryPrice, uint256 fallbackPrice);
    event ExecutorUpdated(address indexed executor, bool isExecutor);
    event MinEMADelayUpdated(uint256 oldDelay, uint256 newDelay);
    event EMAUpdateSkipped(uint256 timeSinceLastUpdate, uint256 requiredDelay);
    event PrimaryOracleReverted();
    event FallbackOracleReverted();
    /**
     *
     * ERRORS
     *
     */

    error AddressZero();
    error NotOwner();
    error InvalidBounds();
    error InvalidMultiplier();
    error NotExecutor();

    /**
     *
     * MODIFIERS
     *
     */
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyExecutor() {
        if (!executors[msg.sender]) revert NotExecutor();
        _;
    }

    /**
     *
     * CONSTRUCTOR
     *
     */

    /// @notice Constructs the sSuperUSDOracle contract
    /// @param _collateralToken The address of the collateral token
    /// @param _loanToken The address of the loan token
    /// @param _sSuperUSDOracleAddress The address of the primary sSuperUSD oracle
    /// @param _sSuperUSDFallbackOracleAddress The address of the fallback sSuperUSD oracle
    constructor(
        address _collateralToken,
        address _loanToken,
        address _sSuperUSDOracleAddress,
        address _sSuperUSDFallbackOracleAddress
    ) {
        if (
            _collateralToken == address(0) || _loanToken == address(0) || _sSuperUSDOracleAddress == address(0)
                || _sSuperUSDFallbackOracleAddress == address(0)
        ) {
            revert AddressZero();
        }

        collateralToken = _collateralToken;
        loanToken = _loanToken;
        sSuperUSDOracleAddress = _sSuperUSDOracleAddress;
        sSuperUSDFallbackOracleAddress = _sSuperUSDFallbackOracleAddress;
        owner = msg.sender;

        // Get decimals from token contracts
        collateralDecimals = IERC20Metadata(_collateralToken).decimals();
        loanDecimals = IERC20Metadata(_loanToken).decimals();

        // Initialize latestEMA with first price
        ( /* roundId */ , latestPrimaryPrice, /* startedAt */, latestPrimaryTime, /* answeredInRound */ ) =
            IsSuperUSDOracle(_sSuperUSDOracleAddress).latestRoundData();
        latestEMA = latestPrimaryPrice;
        latestAnswer = latestPrimaryPrice;
        latestUpdateTime = latestPrimaryTime;
        isPrimaryReverted = false;

        latestEMATime = 0;

        ( /* roundId */ , latestFallbackPrice, /* startedAt */, latestFallbackTime, /* answeredInRound */ ) =
            IsSuperUSDOracle(_sSuperUSDFallbackOracleAddress).latestRoundData();

        // Convert latestEMA to uint256 for bounds calculation
        EMAUpperBound = uint256(latestEMA).mulDivDown(baseUpperBound, 1e4);
        EMALowerBound = uint256(latestEMA).mulDivDown(baseLowerBound, 1e4);
    }

    /**
     *
     * ORACLE FUNCTIONS
     *
     */

    /// @notice Computes and updates the exchange rate using EMA
    function updatePrice() public nonReentrant onlyExecutor {
        bool isPrimaryFresh = false;
        bool isFallbackFresh = false;
        bool isPrimaryPriceOutOfRange = false;
        bool isFallbackPriceOutOfRange = false;
        int256 newPriceForEMA;
        int256 oldEMA = latestEMA;
        uint256 newEMATime;

        // primary oracle check
        try IsSuperUSDOracle(sSuperUSDOracleAddress).latestRoundData() returns (
            uint80 /* roundId */,
            int256 price,
            uint256 /* startedAt */,
            uint256 timestamp,
            uint80 /* answeredInRound */
        ) {
            isPrimaryReverted = false;
            latestPrimaryPrice = price;
            latestPrimaryTime = timestamp;
        } catch {
            isPrimaryReverted = true;
            emit PrimaryOracleReverted();
            return;
        }

        // fallback oracle check
         try IsSuperUSDOracle(sSuperUSDFallbackOracleAddress).latestRoundData() returns (
            uint80 /* roundId */,
            int256 price,
            uint256 /* startedAt */,
            uint256 timestamp,
            uint80 /* answeredInRound */
        ) {
            latestFallbackPrice = price;
            latestFallbackTime = timestamp;
        }catch {
            emit FallbackOracleReverted();
        }

        // Fresh check
        if (block.timestamp - latestPrimaryTime <= maxPriceAge) {
            isPrimaryFresh = true;
        }

        if (block.timestamp - latestFallbackTime <= maxPriceAge) {
            isFallbackFresh = true;
        }

        // bound check
        if (uint256(latestPrimaryPrice) > EMAUpperBound || uint256(latestPrimaryPrice) < EMALowerBound) {
            isPrimaryPriceOutOfRange = true;
        }

        if (uint256(latestFallbackPrice) > EMAUpperBound || uint256(latestFallbackPrice) < EMALowerBound) {
            isFallbackPriceOutOfRange = true;
        }

        if (isPrimaryFresh && !isPrimaryPriceOutOfRange) {
            latestAnswer = latestPrimaryPrice;
            latestUpdateTime = latestPrimaryTime;
            newPriceForEMA = latestAnswer;
            newEMATime = latestPrimaryTime;
            emit PrimaryPriceUsed(uint256(latestAnswer));
        } else if (isFallbackFresh && !isFallbackPriceOutOfRange) {
            latestAnswer = latestFallbackPrice;
            latestUpdateTime = latestFallbackTime;
            newPriceForEMA = latestAnswer;
            newEMATime = latestFallbackTime;
            emit FallbackPriceUsed(uint256(latestAnswer), "price_out_of_bounds");
        } else {
            string memory reason;
            if (isPrimaryFresh) {
                newPriceForEMA = latestPrimaryPrice;
                newEMATime = latestPrimaryTime;
                reason = "primary_price_used_but_no_update";
            } else if (isFallbackFresh) {
                newPriceForEMA = latestFallbackPrice;
                newEMATime = latestFallbackTime;
                reason = "fallback_price_used_but_no_update";
            } else {
                reason = "both_price_are_not_fresh";
                emit NoPriceUpdate(reason, uint256(latestPrimaryPrice), uint256(latestFallbackPrice));
                return;
            }
            emit NoPriceUpdate(reason, uint256(latestPrimaryPrice), uint256(latestFallbackPrice));
        }

        // Only update EMA if enough time has passed since latest update
        if (newEMATime > latestEMATime + minEMADelay) {
            // Calculate new EMA
            // EMA = α * currentPrice + (1 - α) * previousEMA
            // where α is the multiplier = 2/(N+1), N=10 days
            // 2/(10+1) ≈ 0.2 = 20% = 2000 (scaled by 1e4)
            latestEMA = (newPriceForEMA * int256(multiplier) + oldEMA * int256(10000 - multiplier)) / int256(10000);

            // Update bounds based on new EMA
            EMAUpperBound = uint256(latestEMA).mulDivDown(baseUpperBound, 1e4);
            EMALowerBound = uint256(latestEMA).mulDivDown(baseLowerBound, 1e4);

            // Update latestEMATime
            latestEMATime = newEMATime;

            // Emit events
            emit MovingAverageUpdated(uint256(oldEMA), uint256(latestEMA));
            emit BoundsUpdated(EMAUpperBound, EMALowerBound);
        } else {
            emit EMAUpdateSkipped(newEMATime - latestEMATime, minEMADelay);
        }
    }

    /// @notice Implementation of AggregatorV3Interface functions
    /// @dev These functions provide Chainlink-compatible price feed interface

    /// @notice Get the number of decimals for the output price
    function decimals() external pure returns (uint8) {
        return 8;
    }

    /// @notice Get a description of this price feed
    function description() external pure returns (string memory) {
        return "sSuperUSD / USDC";
    }

    /// @notice Get the version number of this oracle
    function version() external pure returns (uint256) {
        return 1;
    }

    /// @notice Get data from a specific round
    /// @param _roundId The round ID to get data for
    function getRoundData(uint80 _roundId) external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        // Since we don't maintain historical rounds, return latest data
        return (
            0,
            latestAnswer,
            latestUpdateTime,
            latestUpdateTime,
            0
        );
    }

    /// @notice Get the latest round data
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        require(!isPrimaryReverted, "Primary oracle has reverted");
        return (
            0,
            latestAnswer,
            latestUpdateTime,
            latestUpdateTime,
            0
        );
    }

    /**
     *
     * ADMIN FUNCTIONS
     *
     */

    /// @notice Updates the primary oracle address
    /// @param _newOracle The new oracle address
    function updatePrimaryOracle(address _newOracle) external onlyOwner {
        if (_newOracle == address(0)) revert AddressZero();

        // Get latest price from new oracle to validate it's not zero
        ( /* roundId */ , int256 newPrice, /* startedAt */, /* updatedAt */, /* answeredInRound */ ) =
            IsSuperUSDOracle(_newOracle).latestRoundData();
        if (newPrice == 0) revert("Zero price not allowed");

        address oldOracle = sSuperUSDOracleAddress;
        sSuperUSDOracleAddress = _newOracle;
        emit PrimaryOracleUpdated(oldOracle, _newOracle);
    }

    /// @notice Updates the fallback oracle address
    /// @param _newOracle The new oracle address
    function updateFallbackOracle(address _newOracle) external onlyOwner {
        if (_newOracle == address(0)) revert AddressZero();

        // Get latest price from new oracle to validate it's not zero
        ( /* roundId */ , int256 newPrice, /* startedAt */, /* updatedAt */, /* answeredInRound */ ) =
            IsSuperUSDOracle(_newOracle).latestRoundData();
        if (newPrice == 0) revert("Zero price not allowed");

        address oldOracle = sSuperUSDFallbackOracleAddress;
        sSuperUSDFallbackOracleAddress = _newOracle;
        emit FallbackOracleUpdated(oldOracle, _newOracle);
    }

    /// @notice Updates the maximum allowed age for price feeds
    /// @param _newMaxAge The new maximum age in seconds
    function updateMaxPriceAge(uint256 _newMaxAge) external onlyOwner {
        if (_newMaxAge == 0) revert AddressZero();
        uint256 oldMaxAge = maxPriceAge;
        maxPriceAge = _newMaxAge;
        emit MaxPriceAgeUpdated(oldMaxAge, _newMaxAge);
    }

    /// @notice Transfers ownership of the contract
    /// @param _newOwner The address of the new owner
    function transferOwnership(address _newOwner) external onlyOwner {
        if (_newOwner == address(0)) revert AddressZero();
        address oldOwner = owner;
        owner = _newOwner;
        emit OwnershipTransferred(oldOwner, _newOwner);
    }

    /// @notice Updates the multiplier for EMA calculation
    /// @param _newMultiplier The new multiplier (scaled by 1e4)
    /// @dev The multiplier is calculated as 2/(N+1) where N is the number of days
    /// For N=10 days: 2/(10+1) ≈ 0.2 = 20% = 2000 (scaled by 1e4)
    function updateMultiplier(uint256 _newMultiplier) external onlyOwner {
        if (_newMultiplier == 0 || _newMultiplier > 10000) revert InvalidMultiplier();
        uint256 oldMultiplier = multiplier;
        multiplier = _newMultiplier;
        emit MultiplierUpdated(uint16(oldMultiplier), uint16(_newMultiplier));
    }

    /**
     * @notice Updates the base bounds used for calculating exchange rate limits
     * @param _newUpperBound The new base upper bound (scaled by 1e4)
     * @param _newLowerBound The new base lower bound (scaled by 1e4)
     */
    function updateBaseBounds(uint256 _newUpperBound, uint256 _newLowerBound) external onlyOwner {
        if (_newUpperBound <= 10000 || _newLowerBound >= 10000 || _newLowerBound >= _newUpperBound) {
            revert InvalidBounds();
        }

        uint256 oldUpper = baseUpperBound;
        uint256 oldLower = baseLowerBound;

        baseUpperBound = _newUpperBound;
        baseLowerBound = _newLowerBound;

        emit BaseBoundsUpdated(oldUpper, oldLower, _newUpperBound, _newLowerBound);
    }

    /// @notice Updates the executor status of an address
    /// @param _executor The address to update
    /// @param _isExecutor Whether the address should be an executor
    function updateExecutor(address _executor, bool _isExecutor) external onlyOwner {
        if (_executor == address(0)) revert AddressZero();
        executors[_executor] = _isExecutor;
        emit ExecutorUpdated(_executor, _isExecutor);
    }

    /**
     * @notice Updates the minimum delay required between EMA updates
     * @param _newDelay The new minimum delay in seconds
     */
    function updateMinEMADelay(uint256 _newDelay) external onlyOwner {
        uint256 oldDelay = minEMADelay;
        minEMADelay = _newDelay;
        emit MinEMADelayUpdated(oldDelay, _newDelay);
    }
}
