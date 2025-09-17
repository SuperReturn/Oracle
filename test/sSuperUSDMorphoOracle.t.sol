// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {sSuperUSDMorphoOracle, IsSuperUSDOracle, IAccountant} from "../src/sSuperUSDMorphoOracle.sol";
import {console} from "forge-std/console.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";

contract MockToken is IERC20Metadata {
    uint8 private _decimals;

    constructor(uint8 decimals_) {
        _decimals = decimals_;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function name() external pure override returns (string memory) {
        return "";
    }

    function symbol() external pure override returns (string memory) {
        return "";
    }

    function totalSupply() external pure override returns (uint256) {
        return 0;
    }

    function balanceOf(address) external pure override returns (uint256) {
        return 0;
    }

    function transfer(address, uint256) external pure override returns (bool) {
        return false;
    }

    function allowance(address, address) external pure override returns (uint256) {
        return 0;
    }

    function approve(address, uint256) external pure override returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) external pure override returns (bool) {
        return false;
    }
}

contract MockOracle is IsSuperUSDOracle {
    address public immutable accountant;
    int256 private _rate;

    constructor(address _accountant, int256 initialRate) {
        accountant = _accountant;
        _rate = initialRate;
    }

    function setRate(int256 newRate) external {
        _rate = newRate;
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, _rate, block.timestamp, block.timestamp, 0);
    }

    function sSuperUSDAccountant() external view override returns (address) {
        return accountant;
    }
}

contract MockAccountant is IAccountant {
    AccountantState private _state;

    constructor() {
        _state.lastUpdateTimestamp = uint64(block.timestamp);
        _state.exchangeRate = 1e6; // 1.0 with 6 decimals
    }

    function setState(AccountantState memory newState) external {
        _state = newState;
    }

    function accountantState() external view override returns (AccountantState memory) {
        return _state;
    }

    function getRate() external view override returns (uint256) {
        return _state.exchangeRate;
    }
}

contract sSuperUSDMorphoOracleTest is Test {
    using FixedPointMathLib for uint256;

    sSuperUSDMorphoOracle public oracle;
    address public owner;
    MockToken public collateralToken;
    MockToken public loanToken;
    MockOracle public primaryOracle;
    MockOracle public fallbackOracle;
    MockAccountant public accountant;

    // Fork configuration
    uint256 public forkBlock = 379760000;
    uint256 public arbitrumFork;

    // Events to test
    event PrimaryOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event FallbackOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event MaxPriceAgeUpdated(uint256 oldMaxAge, uint256 newMaxAge);
    event BoundsUpdated(uint256 newUpper, uint256 newLower);
    event MovingAverageUpdated(uint256 oldMA, uint256 newMA);
    event MultiplierUpdated(uint256 oldMultiplier, uint256 newMultiplier);
    event PrimaryPriceUsed(uint256 price);
    event FallbackPriceUsed(uint256 price, string reason);

    function setUp() public {
        // Create and select fork
        arbitrumFork = vm.createFork(vm.envString("ARBITRUM_RPC_URL"), forkBlock);
        vm.selectFork(arbitrumFork);

        // Deploy mock tokens with different decimals
        collateralToken = new MockToken(18); // 18 decimals for collateral
        loanToken = new MockToken(6); // 6 decimals for loan

        // Deploy mock accountant and oracles
        accountant = new MockAccountant();
        primaryOracle = new MockOracle(address(accountant), 1e8); // 1.0 with 8 decimals
        fallbackOracle = new MockOracle(address(accountant), 1.3e8); // 1.3 with 8 decimals

        // Deploy oracle
        oracle = new sSuperUSDMorphoOracle(
            address(collateralToken), address(loanToken), address(primaryOracle), address(fallbackOracle)
        );

        // Set initial state
        owner = address(this);
    }

    function test_Constructor() public {
        assertEq(oracle.collateralToken(), address(collateralToken));
        assertEq(oracle.loanToken(), address(loanToken));
        assertEq(oracle.sSuperUSDOracleAddress(), address(primaryOracle));
        assertEq(oracle.sSuperUSDFallbackOracleAddress(), address(fallbackOracle));
        assertEq(oracle.owner(), address(this));
        assertEq(oracle.collateralDecimals(), 18);
        assertEq(oracle.loanDecimals(), 6);
    }

    function test_Constructor_RevertZeroAddress() public {
        vm.expectRevert(sSuperUSDMorphoOracle.AddressZero.selector);
        new sSuperUSDMorphoOracle(address(0), address(loanToken), address(primaryOracle), address(fallbackOracle));
    }

    function test_InitialPrice() public {
        // Get initial price from primary oracle
        (, int256 initialPrice,,,) = primaryOracle.latestRoundData();

        // Get initial moving average
        int256 initialMA = oracle.calculateMovingAverage();

        // Initial MA should equal initial price
        assertEq(initialMA, initialPrice);
    }

    function test_UpdatePrice_ZeroPrice() public {
        // Set primary oracle price to zero
        primaryOracle.setRate(0);

        // Try to update primary oracle - should revert
        vm.expectRevert("Zero price not allowed");
        oracle.updatePrimaryOracle(address(primaryOracle));
    }

    function test_UpdateMultiplier() public {
        uint256 newMultiplier = 1500; // 0.15 or 15%

        vm.expectEmit(true, true, false, true);
        emit MultiplierUpdated(2000, newMultiplier);
        oracle.updateMultiplier(newMultiplier);

        assertEq(oracle.multiplier(), newMultiplier);

        // Test invalid multiplier
        vm.expectRevert(sSuperUSDMorphoOracle.InvalidMultiplier.selector);
        oracle.updateMultiplier(0);

        vm.expectRevert(sSuperUSDMorphoOracle.InvalidMultiplier.selector);
        oracle.updateMultiplier(10001);
    }

    function test_UpdatePrice_Fresh() public {
        // Get initial EMA value
        int256 initialEMA = oracle.calculateMovingAverage();
        console.log("initialEMA", initialEMA);

        // Set a new price in primary oracle that's within bounds
        // Should be within 0.5% up or 5% down of current EMA
        uint256 newPrice = uint256(initialEMA).mulDivDown(10025, 1e4); // 0.25% increase
        primaryOracle.setRate(int256(newPrice));

        // Calculate expected new EMA before events
        uint256 multiplierValue = oracle.multiplier();
        int256 expectedEMA =
            (int256(newPrice) * int256(multiplierValue) + initialEMA * int256(10000 - multiplierValue)) / int256(10000);

        // Update price when primary oracle is fresh
        vm.expectEmit(false, false, false, true);
        emit PrimaryPriceUsed(uint256(newPrice));
        vm.expectEmit(false, false, false, true);
        emit MovingAverageUpdated(uint256(initialEMA), uint256(expectedEMA));
        vm.expectEmit(false, false, false, true);
        emit BoundsUpdated(
            uint256(10050).mulDivDown(uint256(expectedEMA), 1e8), // 100.5%
            uint256(9500).mulDivDown(uint256(expectedEMA), 1e8) // 95%
        );
        oracle.updatePrice();

        // Verify results
        int256 newEMA = oracle.calculateMovingAverage();
        assertEq(newEMA, expectedEMA);
        assertEq(oracle.allowedExchangeRateChangeUpper(), uint256(10050).mulDivDown(uint256(expectedEMA), 1e8));
        assertEq(oracle.allowedExchangeRateChangeLower(), uint256(9500).mulDivDown(uint256(expectedEMA), 1e8));
    }

    function test_UpdatePrice_Stale() public {
        // Get initial EMA
        int256 initialEMA = oracle.calculateMovingAverage();
        console.log("initialEMA", initialEMA);

        // Make primary oracle stale
        IAccountant.AccountantState memory state = accountant.accountantState();
        state.lastUpdateTimestamp = uint64(block.timestamp - oracle.maxPriceAge() - 1);
        accountant.setState(state);

        // Get fallback oracle price
        (, int256 fallbackPrice,,,) = fallbackOracle.latestRoundData();

        // Calculate expected new EMA
        uint256 multiplierValue = oracle.multiplier();
        int256 expectedEMA =
            (fallbackPrice * int256(multiplierValue) + initialEMA * int256(10000 - multiplierValue)) / int256(10000);

        // Update price - should use fallback oracle due to stale primary
        vm.expectEmit(false, false, false, true);
        emit FallbackPriceUsed(uint256(fallbackPrice), "stale_price");
        vm.expectEmit(false, false, false, true);
        emit MovingAverageUpdated(uint256(initialEMA), uint256(expectedEMA));
        vm.expectEmit(false, false, false, true);
        emit BoundsUpdated(
            uint256(10050).mulDivDown(uint256(expectedEMA), 1e8), // 100.5%
            uint256(9500).mulDivDown(uint256(expectedEMA), 1e8) // 95%
        );
        oracle.updatePrice();

        // Verify results
        int256 newEMA = oracle.calculateMovingAverage();
        assertEq(newEMA, expectedEMA);
        assertEq(oracle.allowedExchangeRateChangeUpper(), uint256(10050).mulDivDown(uint256(expectedEMA), 1e8));
        assertEq(oracle.allowedExchangeRateChangeLower(), uint256(9500).mulDivDown(uint256(expectedEMA), 1e8));
    }

    function test_UpdatePrice_OutOfBounds() public {
        // Get initial EMA
        int256 initialEMA = oracle.calculateMovingAverage();
        console.log("initialEMA", initialEMA);

        // Set primary oracle price out of bounds (50% higher)
        primaryOracle.setRate(int256(uint256(initialEMA).mulDivDown(15000, 1e4)));

        // Get fallback oracle price
        (, int256 fallbackPrice,,,) = fallbackOracle.latestRoundData();

        // Calculate expected new EMA
        uint256 multiplierValue = oracle.multiplier();
        int256 expectedEMA =
            (fallbackPrice * int256(multiplierValue) + initialEMA * int256(10000 - multiplierValue)) / int256(10000);

        // Update price - should use fallback oracle due to out of bounds price
        vm.expectEmit(false, false, false, true);
        emit FallbackPriceUsed(uint256(fallbackPrice), "price_out_of_bounds");
        vm.expectEmit(false, false, false, true);
        emit MovingAverageUpdated(uint256(initialEMA), uint256(expectedEMA));
        vm.expectEmit(false, false, false, true);
        emit BoundsUpdated(
            uint256(10050).mulDivDown(uint256(expectedEMA), 1e8), // 100.5%
            uint256(9500).mulDivDown(uint256(expectedEMA), 1e8) // 95%
        );
        oracle.updatePrice();

        // Verify results
        int256 newEMA = oracle.calculateMovingAverage();
        assertEq(newEMA, expectedEMA);
        assertEq(oracle.allowedExchangeRateChangeUpper(), uint256(10050).mulDivDown(uint256(expectedEMA), 1e8));
        assertEq(oracle.allowedExchangeRateChangeLower(), uint256(9500).mulDivDown(uint256(expectedEMA), 1e8));
    }

    function test_MultipleUpdates() public {
        uint256 multiplier = oracle.multiplier();
        int256 currentMA = oracle.calculateMovingAverage();
        console.log("initial MA", currentMA);
        console.log(
            "initial upper and lower", oracle.allowedExchangeRateChangeUpper(), oracle.allowedExchangeRateChangeLower()
        );

        // 1. Test fresh and within bounds (use primary oracle)
        int256 price = int256(uint256(currentMA).mulDivDown(10020, 1e4)); // +0.2%
        primaryOracle.setRate(price);

        // Calculate expected MA and emit events
        int256 expectedMA = (price * int256(multiplier) + currentMA * int256(10000 - multiplier)) / 10000;

        vm.expectEmit(false, false, false, true);
        emit PrimaryPriceUsed(uint256(price));
        vm.expectEmit(false, false, false, true);
        emit MovingAverageUpdated(uint256(currentMA), uint256(expectedMA));
        vm.expectEmit(false, false, false, true);
        emit BoundsUpdated(
            uint256(10050).mulDivDown(uint256(expectedMA), 1e8), // 100.5%
            uint256(9500).mulDivDown(uint256(expectedMA), 1e8) // 95%
        );

        oracle.updatePrice();
        currentMA = oracle.calculateMovingAverage();
        assertEq(currentMA, expectedMA);

        // 2. Test out of bounds (use fallback oracle)
        console.log("second price", currentMA);
        console.log(
            "second upper and lower", oracle.allowedExchangeRateChangeUpper(), oracle.allowedExchangeRateChangeLower()
        );

        primaryOracle.setRate(int256(uint256(currentMA).mulDivDown(10200, 1e4))); // +2%
        (, price,,,) = fallbackOracle.latestRoundData();

        expectedMA = (price * int256(multiplier) + currentMA * int256(10000 - multiplier)) / 10000;

        vm.expectEmit(false, false, false, true);
        emit FallbackPriceUsed(uint256(price), "price_out_of_bounds");
        vm.expectEmit(false, false, false, true);
        emit MovingAverageUpdated(uint256(currentMA), uint256(expectedMA));
        vm.expectEmit(false, false, false, true);
        emit BoundsUpdated(
            uint256(10050).mulDivDown(uint256(expectedMA), 1e8), // 100.5%
            uint256(9500).mulDivDown(uint256(expectedMA), 1e8) // 95%
        );

        oracle.updatePrice();
        currentMA = oracle.calculateMovingAverage();
        assertEq(currentMA, expectedMA);

        // 3. Test fresh and within bounds again (use primary oracle)
        console.log("third price", currentMA);
        console.log(
            "third upper and lower", oracle.allowedExchangeRateChangeUpper(), oracle.allowedExchangeRateChangeLower()
        );

        price = int256(uint256(currentMA).mulDivDown(10100, 1e4));
        primaryOracle.setRate(price);

        expectedMA = (price * int256(multiplier) + currentMA * int256(10000 - multiplier)) / 10000;

        vm.expectEmit(false, false, false, true);
        emit PrimaryPriceUsed(uint256(price));
        vm.expectEmit(false, false, false, true);
        emit MovingAverageUpdated(uint256(currentMA), uint256(expectedMA));
        vm.expectEmit(false, false, false, true);
        emit BoundsUpdated(
            uint256(10050).mulDivDown(uint256(expectedMA), 1e8), // 100.5%
            uint256(9500).mulDivDown(uint256(expectedMA), 1e8) // 95%
        );

        oracle.updatePrice();
        currentMA = oracle.calculateMovingAverage();
        assertEq(currentMA, expectedMA);

        // 4. Test stale price (use fallback oracle)
        console.log("fourth price", currentMA);
        console.log(
            "fourth upper and lower", oracle.allowedExchangeRateChangeUpper(), oracle.allowedExchangeRateChangeLower()
        );

        IAccountant.AccountantState memory state = accountant.accountantState();
        state.lastUpdateTimestamp = uint64(block.timestamp - oracle.maxPriceAge() - 1);
        accountant.setState(state);

        (, price,,,) = fallbackOracle.latestRoundData();
        expectedMA = (price * int256(multiplier) + currentMA * int256(10000 - multiplier)) / 10000;

        vm.expectEmit(false, false, false, true);
        emit FallbackPriceUsed(uint256(price), "stale_price");
        vm.expectEmit(false, false, false, true);
        emit MovingAverageUpdated(uint256(currentMA), uint256(expectedMA));
        vm.expectEmit(false, false, false, true);
        emit BoundsUpdated(
            uint256(10050).mulDivDown(uint256(expectedMA), 1e8), // 100.5%
            uint256(9500).mulDivDown(uint256(expectedMA), 1e8) // 95%
        );

        oracle.updatePrice();
        currentMA = oracle.calculateMovingAverage();
        assertEq(currentMA, expectedMA);
    }

    function test_AdminFunctions() public {
        // Test updateMaxPriceAge
        uint256 newMaxAge = 48 hours;
        vm.expectEmit(true, true, false, true);
        emit MaxPriceAgeUpdated(24 hours, newMaxAge);
        oracle.updateMaxPriceAge(newMaxAge);
        assertEq(oracle.maxPriceAge(), newMaxAge);

        // Test updatePrimaryOracle
        MockOracle newPrimaryOracle = new MockOracle(address(accountant), 1e8); // Create new mock oracle with initial rate
        vm.expectEmit(true, true, false, true);
        emit PrimaryOracleUpdated(address(primaryOracle), address(newPrimaryOracle));
        oracle.updatePrimaryOracle(address(newPrimaryOracle));
        assertEq(oracle.sSuperUSDOracleAddress(), address(newPrimaryOracle));

        // Test updateFallbackOracle
        address newFallbackOracle = makeAddr("newFallbackOracle");
        vm.expectEmit(true, true, false, true);
        emit FallbackOracleUpdated(address(fallbackOracle), newFallbackOracle);
        oracle.updateFallbackOracle(newFallbackOracle);
        assertEq(oracle.sSuperUSDFallbackOracleAddress(), newFallbackOracle);

        // Test transferOwnership
        address newOwner = makeAddr("newOwner");
        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(address(this), newOwner);
        oracle.transferOwnership(newOwner);
        assertEq(oracle.owner(), newOwner);
    }

    function test_AdminFunctions_OnlyOwner() public {
        address nonOwner = makeAddr("nonOwner");
        vm.startPrank(nonOwner);

        vm.expectRevert(sSuperUSDMorphoOracle.NotOwner.selector);
        oracle.updateMaxPriceAge(48 hours);

        vm.expectRevert(sSuperUSDMorphoOracle.NotOwner.selector);
        oracle.updatePrimaryOracle(address(0x1));

        vm.expectRevert(sSuperUSDMorphoOracle.NotOwner.selector);
        oracle.updateFallbackOracle(address(0x1));

        vm.expectRevert(sSuperUSDMorphoOracle.NotOwner.selector);
        oracle.transferOwnership(address(0x1));

        vm.stopPrank();
    }

    function test_ViewFunctions() public {
        // Test getPrecision
        assertEq(oracle.getPrecision(), 36 + 6 - 18); // 36 + loanDecimals - collateralDecimals

        // Test getCollateralInfo
        (address token, uint8 decimals) = oracle.getCollateralInfo();
        assertEq(token, address(collateralToken));
        assertEq(decimals, 18);

        // Test getLoanInfo
        (token, decimals) = oracle.getLoanInfo();
        assertEq(token, address(loanToken));
        assertEq(decimals, 6);
    }
}
