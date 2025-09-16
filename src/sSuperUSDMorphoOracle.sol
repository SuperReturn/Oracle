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
    
    /// @notice The sSuperUSD oracle address that provides exchange rate
    address public immutable sSuperUSDOracleAddress;
    
    /***************************************
    ERRORS
    ***************************************/
    
    error AddressZero();
    error InvalidAnswer();
    
    /***************************************
    CONSTRUCTOR
    ***************************************/
    
    /// @notice Constructs the sSuperUSDOracle contract
    /// @param _collateralToken The address of the collateral token
    /// @param _loanToken The address of the loan token
    /// @param _sSuperUSDOracleAddress The address of the sSuperUSD oracle
    constructor(address _collateralToken, address _loanToken, address _sSuperUSDOracleAddress) {
        if (_collateralToken == address(0) || _loanToken == address(0) || _sSuperUSDOracleAddress == address(0)) {
            revert AddressZero();
        }
        
        collateralToken = _collateralToken;
        loanToken = _loanToken;
        sSuperUSDOracleAddress = _sSuperUSDOracleAddress;
        
        // Get decimals from token contracts
        collateralDecimals = IERC20Metadata(_collateralToken).decimals();
        loanDecimals = IERC20Metadata(_loanToken).decimals();
    }
    
    /***************************************
    ORACLE FUNCTIONS
    ***************************************/
    
    /// @notice Returns the price of 1 asset of collateral token quoted in 1 asset of loan token, scaled by 1e36
    /// @dev Gets the exchange rate from sSuperUSD oracle and converts it to Morpho format
    /// @return The price rate of 1 asset of collateral token quoted in 1 asset of loan token (scaled by 1e36)
    function price() external view override returns (uint256) {
        // Get the exchange rate from sSuperUSD oracle
        (, int256 answer, , , ) = IsSuperUSDOracle(sSuperUSDOracleAddress).latestRoundData();
        
        // Ensure answer is positive
        if (answer <= 0) revert InvalidAnswer();
        
        // Convert answer from int256 to uint256
        uint256 exchangeRate = uint256(answer);
        
        // Answer has 8 decimals (1e8), we need to convert to our precision
        // Calculate the target precision: 36 + loanDecimals - collateralDecimals
        uint256 targetPrecision = 36 + loanDecimals - collateralDecimals;
        
        // Convert from 8 decimals to target precision
        // exchangeRate is in 1e8 format, we need it in 10^targetPrecision format
        return exchangeRate * (10 ** (targetPrecision - 8));
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