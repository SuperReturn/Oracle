// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

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
}

/// @title sSuperUSDOracle
/// @author SuperReturn
/// @notice Oracle contract for sSuperUSD that implements IOracle interface
/// @dev This oracle gets the exchange rate from an external sSuperUSD oracle and converts it to Morpho format
contract sSuperUSDMorphoOracle is IOracle {
    
    /***************************************
    STATE VARIABLES
    ***************************************/
    
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
    
    /***************************************
    EVENTS
    ***************************************/
    
    event PrimaryOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event FallbackOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /***************************************
    ERRORS
    ***************************************/
    
    error AddressZero();
    error InvalidAnswer();
    error NotOwner();
    error BothOraclesFailed();
    
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
    
    /// @notice Returns the price of 1 asset of collateral token quoted in 1 asset of loan token, scaled by 1e36
    /// @dev Tries primary oracle first, falls back to secondary oracle if primary fails
    /// @return The price rate of 1 asset of collateral token quoted in 1 asset of loan token (scaled by 1e36)
    function price() external view override returns (uint256) {
        // Try primary oracle first
        try IsSuperUSDOracle(sSuperUSDOracleAddress).latestRoundData() returns (
            uint80 /* roundId */, 
            int256 answer, 
            uint256 /* startedAt */, 
            uint256 /* updatedAt */, 
            uint80 /* answeredInRound */
        ) {
            if (answer > 0) {
                return _calculatePrice(answer);
            }
        } catch {}

        // If primary oracle fails or returns invalid price, try fallback oracle
        try IsSuperUSDOracle(sSuperUSDFallbackOracleAddress).latestRoundData() returns (
            uint80 /* roundId */, 
            int256 answer, 
            uint256 /* startedAt */, 
            uint256 /* updatedAt */, 
            uint80 /* answeredInRound */
        ) {
            if (answer > 0) {
                return _calculatePrice(answer);
            }
        } catch {}

        // If both oracles fail, revert
        revert BothOraclesFailed();
    }

    /// @dev Internal function to calculate price with proper scaling
    function _calculatePrice(int256 answer) internal view returns (uint256) {
        uint256 exchangeRate = uint256(answer);
        uint256 targetPrecision = 36 + loanDecimals - collateralDecimals;
        return exchangeRate * (10 ** (targetPrecision - 8));
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