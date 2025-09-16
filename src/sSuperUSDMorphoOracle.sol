// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";

/// @title IOracle
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Interface that oracles used by Morpho must implement.
/// @dev It is the user's responsibility to select markets with safe oracles.
interface IOracle {
    /// @notice Returns the price of 1 asset of collateral token quoted in 1 asset of loan token, scaled by 1e36.
    /// @dev It corresponds to the price of 10**(collateral token decimals) assets of collateral token quoted in
    /// 10**(loan token decimals) assets of loan token with `36 + loan token decimals - collateral token decimals`
    /// decimals of precision.
    function price() external view returns (uint256);
}

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

// Add interface for accountant state
interface IAccountant {
    struct AccountantState {
        address payoutAddress;
        uint96 highwaterMark;
        uint128 feesOwedInBase;
        uint128 totalSharesLastUpdate;
        uint96 exchangeRate;
        uint16 allowedExchangeRateChangeUpper;
        uint16 allowedExchangeRateChangeLower;
        uint64 lastUpdateTimestamp;
        bool isPaused;
        uint24 minimumUpdateDelayInSeconds;
        uint16 platformFee;
        uint16 performanceFee;
    }

    function accountantState() external view returns (AccountantState memory);
}

/// @title sSuperUSDOracle
/// @author SuperReturn
/// @notice Oracle contract for sSuperUSD that implements IOracle interface
/// @dev This oracle gets the exchange rate from an external sSuperUSD oracle and converts it to Morpho format
contract sSuperUSDMorphoOracle is IOracle, ReentrancyGuard {
    using FixedPointMathLib for uint256;

    /***************************************
    STATE VARIABLES
    ***************************************/
    
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
    
    /// @notice The upper bound multiplier for price changes (scaled by 1e4)
    uint16 public allowedExchangeRateChangeUpper = 10050; // 100.5% default

    /// @notice The lower bound multiplier for price changes (scaled by 1e4)
    uint16 public allowedExchangeRateChangeLower = 9500;  // 95% default

    /// @notice Last valid answer
    int256 private _latestAnswer;  // Changed from uint256 to int256

    /// @notice Size of the moving average window
    uint256 public constant WINDOW_SIZE = 24; 

    /// @notice Array to store historical prices
    int256[WINDOW_SIZE] private priceHistory;
    
    /// @notice Current index in the circular buffer
    uint256 private currentIndex;
    
    /// @notice Number of prices recorded
    uint256 private numPrices;


    /***************************************
    EVENTS
    ***************************************/
    
    event PrimaryOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event FallbackOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event MaxPriceAgeUpdated(uint256 oldMaxAge, uint256 newMaxAge);
    event BoundsUpdated(uint16 newUpper, uint16 newLower);
    event PriceUpdated(uint256 oldPrice, uint256 newPrice);
    event MovingAverageUpdated(uint256 oldMA, uint256 newMA);

    /***************************************
    ERRORS
    ***************************************/
    
    error AddressZero();
    error NotOwner();
    error InvalidBounds();
    error InsufficientPriceHistory();
    
    /***************************************
    MODIFIERS
    ***************************************/

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /***************************************
    CONSTRUCTOR
    ***************************************/
    
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
        if (_collateralToken == address(0) || 
            _loanToken == address(0) || 
            _sSuperUSDOracleAddress == address(0) ||
            _sSuperUSDFallbackOracleAddress == address(0)
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
    }
    
    /***************************************
    ORACLE FUNCTIONS
    ***************************************/
    
    /// @notice Computes and updates the exchange rate of the collateral token in terms of the loan token, scaled by 1e36
    /// @dev Attempts to retrieve the rate from the primary oracle first; if unsuccessful, it uses the fallback oracle
    function updatePrice() public {
        bool isPrimaryFresh = false;
        bool isPriceOutOfRange = false;
        int256 answer;
        int256 oldMA = calculateMovingAverage();

        // Fresh check
        address primaryAccountant = IsSuperUSDOracle(sSuperUSDOracleAddress).sSuperUSDAccountant();
        IAccountant.AccountantState memory state = IAccountant(primaryAccountant).accountantState();

        if (block.timestamp - state.lastUpdateTimestamp <= maxPriceAge) {
            isPrimaryFresh = true;
        }

        // Bound check
        if (isPrimaryFresh) {
            if(oldMA != 0) {
                (/* roundId */, answer, /* startedAt */, /* updatedAt */, /* answeredInRound */) = IsSuperUSDOracle(sSuperUSDOracleAddress).latestRoundData();
                if (uint256(answer) > uint256(oldMA).mulDivDown(allowedExchangeRateChangeUpper, 1e4) ||
                    uint256(answer) < uint256(oldMA).mulDivDown(allowedExchangeRateChangeLower, 1e4)) {
                    isPriceOutOfRange = true;
                }
            }
        }

        // Use fallback oracle if primary price is invalid
        if (!isPrimaryFresh || isPriceOutOfRange) {
            (/* roundId */, answer, /* startedAt */, /* updatedAt */, /* answeredInRound */) = 
                IsSuperUSDOracle(sSuperUSDFallbackOracleAddress).latestRoundData();
        }

        // Update price history
        priceHistory[currentIndex] = answer;
        currentIndex = (currentIndex + 1) % WINDOW_SIZE;
        if (numPrices < WINDOW_SIZE) {
            numPrices++;
        }

        // Calculate and store new moving average
        int256 newMA = calculateMovingAverage();
        _latestAnswer = newMA;
        
        emit PriceUpdated(uint256(oldMA), uint256(newMA));
        emit MovingAverageUpdated(uint256(oldMA), uint256(newMA));
    }

    /// @notice Calculates the moving average of stored prices
    /// @return The moving average price
    function calculateMovingAverage() public view returns (int256) {
        if (numPrices == 0) return 0;
        
        int256 sum = 0;
        uint256 count = numPrices;
        
        for (uint256 i = 0; i < count; i++) {
            sum += priceHistory[i];
        }
        
        return sum / int256(count);
    }

    /// @notice Returns the latest valid exchange rate without updating it
    /// @dev Calculates the price by scaling the stored answer to the correct precision
    /// @return The exchange rate of 1 unit of collateral token in terms of 1 unit of loan token (scaled by 1e36)
    function price() external view override returns (uint256) {
        uint256 maPrice = uint256(calculateMovingAverage());
        uint256 targetPrecision = 36 + loanDecimals - collateralDecimals;
        return maPrice * (10 ** (targetPrecision - 8));
    }

    /***************************************
    ADMIN FUNCTIONS
    ***************************************/

    /// @notice Updates the primary oracle address
    /// @param _newOracle The new oracle address
    function updatePrimaryOracle(address _newOracle) external onlyOwner {
        if (_newOracle == address(0)) revert AddressZero();
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

    /// @notice Updates the allowed exchange rate change bounds
    /// @param _newUpper The new upper bound multiplier (scaled by 1e4)
    /// @param _newLower The new lower bound multiplier (scaled by 1e4)
    function updateBounds(uint16 _newUpper, uint16 _newLower) external onlyOwner {
        // Upper bound must be > 1e4 (100%) and lower bound must be < 1e4 (100%)
        if (_newUpper <= 1e4 || _newLower >= 1e4 || _newLower == 0) {
            revert InvalidBounds();
        }
        
        allowedExchangeRateChangeUpper = _newUpper;
        allowedExchangeRateChangeLower = _newLower;
        
        emit BoundsUpdated(_newUpper, _newLower);
    }

    /// @notice Transfers ownership of the contract
    /// @param _newOwner The address of the new owner
    function transferOwnership(address _newOwner) external onlyOwner {
        if (_newOwner == address(0)) revert AddressZero();
        address oldOwner = owner;
        owner = _newOwner;
        emit OwnershipTransferred(oldOwner, _newOwner);
    }

    /***************************************
    VIEW FUNCTIONS
    ***************************************/
    
    /// @notice Get the precision used by this oracle
    /// @return The number of decimals in the price returned by this oracle
    function getPrecision() external view returns (uint256) {
        return 36 + loanDecimals - collateralDecimals;
    }
    
    /// @notice Get collateral token info
    /// @return token The collateral token address
    /// @return decimals The collateral token decimals
    function getCollateralInfo() external view returns (address token, uint8 decimals) {
        return (collateralToken, collateralDecimals);
    }
    
    /// @notice Get loan token info  
    /// @return token The loan token address
    /// @return decimals The loan token decimals
    function getLoanInfo() external view returns (address token, uint8 decimals) {
        return (loanToken, loanDecimals);
    }
}