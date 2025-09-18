// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IMorphoOracle} from "./interfaces/IMorphoOracle.sol";
import {IsSuperUSDOracle} from "./interfaces/IsSuperUSDOracle.sol";
import {IAccountant} from "./interfaces/IAccountant.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";

/// @title sSuperUSDOracle
/// @author SuperReturn
/// @notice Oracle contract for sSuperUSD that implements IMorphoOracle interface
/// @dev This oracle gets the exchange rate from an external sSuperUSD oracle and converts it to Morpho format
contract sSuperUSDMorphoOracle is IMorphoOracle, ReentrancyGuard {
    using FixedPointMathLib for uint256;

    /**
     *
     * STATE VARIABLES
     *
     */

    /// @notice Maximum age of price feed in seconds before considering it stale
    uint256 public maxPriceAge = 48 hours;

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

    /// @notice The timestamp of the last price update
    uint256 public lastUpdateTimestamp;

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

    /**
     *
     * ERRORS
     *
     */
    error AddressZero();
    error NotOwner();
    error InvalidBounds();
    error InvalidMultiplier();

    /**
     *
     * MODIFIERS
     *
     */
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
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
        ( /* roundId */ , int256 initialPrice, /* startedAt */, /* updatedAt */, /* answeredInRound */ ) =
            IsSuperUSDOracle(_sSuperUSDOracleAddress).latestRoundData();
        latestEMA = initialPrice;
        latestAnswer = initialPrice;

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
    function updatePrice() public {
        address primaryAccountant = IsSuperUSDOracle(sSuperUSDOracleAddress).sSuperUSDAccountant();
        IAccountant.AccountantState memory state = IAccountant(primaryAccountant).accountantState();

        if (state.lastUpdateTimestamp == lastUpdateTimestamp) {
            emit PrimaryPriceUsed(uint256(latestAnswer));
            return;
        }

        bool isPrimaryFresh = false;
        bool isPrimaryPriceOutOfRange = false;
        bool isFallbackPriceOutOfRange = false;
        int256 primaryOraclePrice;
        int256 fallbackOraclePrice;
        int256 newPriceForEMA;
        int256 oldEMA = latestEMA;

        // Fresh check
        if (block.timestamp - state.lastUpdateTimestamp <= maxPriceAge) {
            isPrimaryFresh = true;
        }
        // Fallback oracle always fresh

        // bound check
        ( /* roundId */ , primaryOraclePrice, /* startedAt */, /* updatedAt */, /* answeredInRound */ ) =
            IsSuperUSDOracle(sSuperUSDOracleAddress).latestRoundData();
        if (uint256(primaryOraclePrice) > EMAUpperBound || uint256(primaryOraclePrice) < EMALowerBound) {
            isPrimaryPriceOutOfRange = true;
        }

        ( /* roundId */ , fallbackOraclePrice, /* startedAt */, /* updatedAt */, /* answeredInRound */ ) =
            IsSuperUSDOracle(sSuperUSDFallbackOracleAddress).latestRoundData();
        if (uint256(fallbackOraclePrice) > EMAUpperBound || uint256(fallbackOraclePrice) < EMALowerBound) {
            isFallbackPriceOutOfRange = true;
        }

        if (isPrimaryFresh && !isPrimaryPriceOutOfRange) {
            //    update global price with price
            latestAnswer = primaryOraclePrice;
            //    update EMA with global price
            newPriceForEMA = latestAnswer;
            emit PrimaryPriceUsed(uint256(latestAnswer));
        } else if (!isFallbackPriceOutOfRange) {
            //     update global price with fallback price
            latestAnswer = fallbackOraclePrice;
            //     update EMA with global price
            newPriceForEMA = latestAnswer;
            emit FallbackPriceUsed(uint256(latestAnswer), "price_out_of_bounds");
        } else {
            // no global price update
            string memory reason;
            if (isPrimaryFresh) {
                // update EMA with primary
                newPriceForEMA = primaryOraclePrice;
                reason = "primary_price_used_but_no_update";
            } else {
                // update EMA with fallback
                newPriceForEMA = fallbackOraclePrice;
                reason = "fallback_price_used_but_no_update";
            }
            emit NoPriceUpdate(reason, uint256(primaryOraclePrice), uint256(fallbackOraclePrice));
        }

        // Calculate new EMA
        // EMA = α * currentPrice + (1 - α) * previousEMA
        // where α is the multiplier = 2/(N+1), N=10 days
        // 2/(10+1) ≈ 0.2 = 20% = 2000 (scaled by 1e4)
        uint256 multiplierValue = uint256(multiplier);
        latestEMA =
            (newPriceForEMA * int256(multiplierValue) + oldEMA * int256(10000 - multiplierValue)) / int256(10000);

        // Update bounds based on new EMA
        EMAUpperBound = uint256(latestEMA).mulDivDown(baseUpperBound, 1e4);
        EMALowerBound = uint256(latestEMA).mulDivDown(baseLowerBound, 1e4);

        // Emit events
        emit MovingAverageUpdated(uint256(oldEMA), uint256(latestEMA));
        emit BoundsUpdated(EMAUpperBound, EMALowerBound);

        // Update lastUpdateTimestamp
        lastUpdateTimestamp = state.lastUpdateTimestamp;
    }

    /// @notice Returns the latest price without updating it
    /// @dev Calculates the price by scaling the stored answer to the correct precision
    /// @return The exchange rate of 1 unit of collateral token in terms of 1 unit of loan token (scaled by 1e36)
    function price() external view override returns (uint256) {
        uint256 targetPrecision = 36 + loanDecimals - collateralDecimals;
        return uint256(latestAnswer) * (10 ** (targetPrecision - 8));
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

    /**
     *
     * VIEW FUNCTIONS
     *
     */

    /// @notice Get the precision used by this oracle
    /// @return The number of decimals in the price returned by this oracle
    function getPrecision() external view returns (uint256) {
        return 36 + loanDecimals - collateralDecimals;
    }
}
