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
    uint256 private _lastUpdateTimestamp;

    constructor(address _accountant, int256 initialRate) {
        accountant = _accountant;
        _rate = initialRate;
        _lastUpdateTimestamp = block.timestamp;
    }

    function setRate(int256 newRate) external {
        _rate = newRate;
    }

    function setLastUpdateTimestamp(uint256 newLastUpdateTimestamp) external {
        _lastUpdateTimestamp = newLastUpdateTimestamp;
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, _rate, _lastUpdateTimestamp, _lastUpdateTimestamp, 0);
    }

    function sSuperUSDAccountant() external view override returns (address) {
        return accountant;
    }
}

contract MockAccountant is IAccountant {
    AccountantState private _state;

    error AccountantWithRateProviders__Paused();

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

    function getRateSafe() external view override returns (uint256) {
        if (_state.isPaused) revert AccountantWithRateProviders__Paused();
        return _state.exchangeRate;
    }
}

contract sSuperUSDMorphoOracleTest is Test {
    using FixedPointMathLib for uint256;

    sSuperUSDMorphoOracle public oracle;
    address public owner;
    address public executor; // Add executor
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
    event NoPriceUpdate(string reason, uint256 primaryPrice, uint256 fallbackPrice);

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

        // Setup executor
        executor = makeAddr("executor");
        oracle.updateExecutor(executor, true);
    }

    function test_Constructor() public {
        assertEq(oracle.collateralToken(), address(collateralToken));
        assertEq(oracle.loanToken(), address(loanToken));
        assertEq(oracle.sSuperUSDOracleAddress(), address(primaryOracle));
        assertEq(oracle.sSuperUSDFallbackOracleAddress(), address(fallbackOracle));
        assertEq(oracle.owner(), address(this));
        assertEq(oracle.collateralDecimals(), 18);
        assertEq(oracle.loanDecimals(), 6);
        assertEq(oracle.latestEMA(), 1e8);
        assertEq(oracle.latestAnswer(), 1e8);
        assertEq(oracle.maxPriceAge(), 48 hours);
        assertEq(oracle.baseUpperBound(), 10500);
        assertEq(oracle.baseLowerBound(), 9500);
    }

    function test_Constructor_RevertZeroAddress() public {
        vm.expectRevert(sSuperUSDMorphoOracle.AddressZero.selector);
        new sSuperUSDMorphoOracle(address(0), address(loanToken), address(primaryOracle), address(fallbackOracle));
    }

    function test_InitialPrice() public {
        // Get initial price from primary oracle
        (, int256 initialPrice,,,) = primaryOracle.latestRoundData();

        // Get initial moving average
        int256 initialAnswer = oracle.latestAnswer();

        // Initial MA should equal initial price
        assertEq(initialAnswer, initialPrice);

        int256 initialEMA = oracle.latestEMA();
        assertEq(initialEMA, initialPrice);
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

    function test_UpdatePrice_PrimaryOracleFreshAndInBounds() public {
        // first condition
        // no matter what fallback oracle price is

        // set primary oracle price to 1.001e8
        int256 newPrice = 1.001e8;
        primaryOracle.setRate(newPrice);
        // set accountant timestamp to 1 hour ago
        IAccountant.AccountantState memory state = accountant.accountantState();
        state.lastUpdateTimestamp = uint64(block.timestamp - 1 hours);
        accountant.setState(state);

        int256 newPriceForEMA = newPrice;
        int256 oldEMA = oracle.latestEMA();
        uint256 multiplierValue = oracle.multiplier();
        int256 expectedEMA =
            (newPriceForEMA * int256(multiplierValue) + oldEMA * int256(10000 - multiplierValue)) / int256(10000);

        uint256 expectedEMAUpperBound = uint256(expectedEMA).mulDivDown(10500, 1e4);
        uint256 expectedEMALowerBound = uint256(expectedEMA).mulDivDown(9500, 1e4);

        // check event
        vm.expectEmit(true, true, false, true);
        emit PrimaryPriceUsed(uint256(newPrice));
        vm.expectEmit(true, true, false, true);
        emit MovingAverageUpdated(uint256(oldEMA), uint256(expectedEMA));
        vm.expectEmit(true, true, false, true);
        emit BoundsUpdated(expectedEMAUpperBound, expectedEMALowerBound);

        // update price with executor
        vm.prank(executor);
        oracle.updatePrice();

        // verify results
        // latestAnswer
        assertEq(oracle.latestAnswer(), newPrice);
        // latestEMA
        assertEq(oracle.latestEMA(), expectedEMA);
        // EMAUpperBound
        assertEq(oracle.EMAUpperBound(), expectedEMAUpperBound);
        // EMALowerBound
        assertEq(oracle.EMALowerBound(), expectedEMALowerBound);
    }

    function test_UpdatePrice_PrimaryOracleFreshAndOutOfBoundsAndFallbackInBounds() public {
        // second condition

        // set primary oracle price to 1.1e8
        int256 newPrice = 1.1e8;
        primaryOracle.setRate(newPrice);
        // set accountant timestamp to 1 hour ago
        IAccountant.AccountantState memory state = accountant.accountantState();
        state.lastUpdateTimestamp = uint64(block.timestamp - 1 hours);
        accountant.setState(state);
        // set fallback oracle price to 1.001e8
        int256 fallbackPrice = 1.001e8;
        fallbackOracle.setRate(fallbackPrice);

        int256 newPriceForEMA = fallbackPrice; // fallback price is used
        int256 oldEMA = oracle.latestEMA();
        uint256 multiplierValue = oracle.multiplier();
        int256 expectedEMA =
            (newPriceForEMA * int256(multiplierValue) + oldEMA * int256(10000 - multiplierValue)) / int256(10000);

        uint256 expectedEMAUpperBound = uint256(expectedEMA).mulDivDown(10500, 1e4);
        uint256 expectedEMALowerBound = uint256(expectedEMA).mulDivDown(9500, 1e4);

        // check event
        vm.expectEmit(true, true, false, true);
        emit FallbackPriceUsed(uint256(fallbackPrice), "price_out_of_bounds");
        vm.expectEmit(true, true, false, true);
        emit MovingAverageUpdated(uint256(oldEMA), uint256(expectedEMA));
        vm.expectEmit(true, true, false, true);
        emit BoundsUpdated(expectedEMAUpperBound, expectedEMALowerBound);

        // update price with executor
        vm.prank(executor);
        oracle.updatePrice();

        // verify results
        // latestAnswer
        assertEq(oracle.latestAnswer(), fallbackPrice);
        // latestEMA
        assertEq(oracle.latestEMA(), expectedEMA);
        // EMAUpperBound
        assertEq(oracle.EMAUpperBound(), expectedEMAUpperBound);
        // EMALowerBound
        assertEq(oracle.EMALowerBound(), expectedEMALowerBound);
    }

    function test_UpdatePrice_PrimaryOracleFreshAndOutOfBoundsAndFallbackOutOfBounds() public {
        // 3-1 condition

        // set primary oracle price to 1.1e8
        int256 newPrice = 1.1e8;
        primaryOracle.setRate(newPrice);
        // set accountant timestamp to 1 hour ago
        IAccountant.AccountantState memory state = accountant.accountantState();
        state.lastUpdateTimestamp = uint64(block.timestamp - 1 hours);
        accountant.setState(state);
        // set fallback oracle price to 1.2e8
        int256 fallbackPrice = 1.2e8;
        fallbackOracle.setRate(fallbackPrice);

        int256 previousAnswer = oracle.latestAnswer();
        int256 newPriceForEMA = newPrice; // primary price is used
        int256 oldEMA = oracle.latestEMA();
        uint256 multiplierValue = oracle.multiplier();
        int256 expectedEMA =
            (newPriceForEMA * int256(multiplierValue) + oldEMA * int256(10000 - multiplierValue)) / int256(10000);

        uint256 expectedEMAUpperBound = uint256(expectedEMA).mulDivDown(10500, 1e4);
        uint256 expectedEMALowerBound = uint256(expectedEMA).mulDivDown(9500, 1e4);

        // check event
        vm.expectEmit(true, true, false, true);
        emit NoPriceUpdate("primary_price_used_but_no_update", uint256(newPrice), uint256(fallbackPrice));
        vm.expectEmit(true, true, false, true);
        emit MovingAverageUpdated(uint256(oldEMA), uint256(expectedEMA));
        vm.expectEmit(true, true, false, true);
        emit BoundsUpdated(expectedEMAUpperBound, expectedEMALowerBound);

        // update price with executor
        vm.prank(executor);
        oracle.updatePrice();

        // verify results
        // latestAnswer
        assertEq(oracle.latestAnswer(), previousAnswer);
        // latestEMA
        assertEq(oracle.latestEMA(), expectedEMA);
        // EMAUpperBound
        assertEq(oracle.EMAUpperBound(), expectedEMAUpperBound);
        // EMALowerBound
        assertEq(oracle.EMALowerBound(), expectedEMALowerBound);
    }

    function test_UpdatePrice_PrimaryOracleStaleAndInBoundsAndFallbackInBounds() public {
        // second condition

        // set primary oracle price to 1.001e8
        int256 newPrice = 1.001e8;
        primaryOracle.setRate(newPrice);
        primaryOracle.setLastUpdateTimestamp(block.timestamp - 5 days);
        // set accountant timestamp to 5 days ago
        IAccountant.AccountantState memory state = accountant.accountantState();
        state.lastUpdateTimestamp = uint64(block.timestamp - 5 days);
        accountant.setState(state);
        // set fallback oracle price to 1.002e8
        int256 fallbackPrice = 1.002e8;
        fallbackOracle.setRate(fallbackPrice);

        int256 newPriceForEMA = fallbackPrice; // fallback price is used
        int256 oldEMA = oracle.latestEMA();
        uint256 multiplierValue = oracle.multiplier();
        int256 expectedEMA =
            (newPriceForEMA * int256(multiplierValue) + oldEMA * int256(10000 - multiplierValue)) / int256(10000);

        uint256 expectedEMAUpperBound = uint256(expectedEMA).mulDivDown(10500, 1e4);
        uint256 expectedEMALowerBound = uint256(expectedEMA).mulDivDown(9500, 1e4);

        // check event
        vm.expectEmit(true, true, false, true);
        emit FallbackPriceUsed(uint256(fallbackPrice), "price_out_of_bounds");
        vm.expectEmit(true, true, false, true);
        emit MovingAverageUpdated(uint256(oldEMA), uint256(expectedEMA));
        vm.expectEmit(true, true, false, true);
        emit BoundsUpdated(expectedEMAUpperBound, expectedEMALowerBound);

        // update price with executor
        vm.prank(executor);
        oracle.updatePrice();

        // verify results
        // latestAnswer
        assertEq(oracle.latestAnswer(), fallbackPrice);
        // latestEMA
        assertEq(oracle.latestEMA(), expectedEMA);
        // EMAUpperBound
        assertEq(oracle.EMAUpperBound(), expectedEMAUpperBound);
        // EMALowerBound
        assertEq(oracle.EMALowerBound(), expectedEMALowerBound);
    }

    function test_UpdatePrice_PrimaryOracleStaleAndInBoundsAndFallbackOutOfBounds() public {
        // 3-2 condition

        // set primary oracle price to 1.001e8
        int256 newPrice = 1.001e8;
        primaryOracle.setRate(newPrice);
        primaryOracle.setLastUpdateTimestamp(block.timestamp - 5 days);
        // set accountant timestamp to 5 days ago
        IAccountant.AccountantState memory state = accountant.accountantState();
        state.lastUpdateTimestamp = uint64(block.timestamp - 5 days);
        accountant.setState(state);
        // set fallback oracle price to 1.2e8
        int256 fallbackPrice = 1.2e8;
        fallbackOracle.setRate(fallbackPrice);

        int256 previousAnswer = oracle.latestAnswer();
        int256 newPriceForEMA = fallbackPrice; // fallback price is used
        int256 oldEMA = oracle.latestEMA();
        uint256 multiplierValue = oracle.multiplier();
        int256 expectedEMA =
            (newPriceForEMA * int256(multiplierValue) + oldEMA * int256(10000 - multiplierValue)) / int256(10000);

        uint256 expectedEMAUpperBound = uint256(expectedEMA).mulDivDown(10500, 1e4);
        uint256 expectedEMALowerBound = uint256(expectedEMA).mulDivDown(9500, 1e4);

        // check event
        vm.expectEmit(true, true, false, true);
        emit NoPriceUpdate("fallback_price_used_but_no_update", uint256(newPrice), uint256(fallbackPrice));
        vm.expectEmit(true, true, false, true);
        emit MovingAverageUpdated(uint256(oldEMA), uint256(expectedEMA));
        vm.expectEmit(true, true, false, true);
        emit BoundsUpdated(expectedEMAUpperBound, expectedEMALowerBound);

        // update price with executor
        vm.prank(executor);
        oracle.updatePrice();

        // verify results
        // latestAnswer
        assertEq(oracle.latestAnswer(), previousAnswer);
        // latestEMA
        assertEq(oracle.latestEMA(), expectedEMA);
        // EMAUpperBound
        assertEq(oracle.EMAUpperBound(), expectedEMAUpperBound);
        // EMALowerBound
        assertEq(oracle.EMALowerBound(), expectedEMALowerBound);
    }

    function test_UpdatePrice_PrimaryOracleStaleAndOutOfBoundsAndFallbackInBounds() public {
        // second condition

        // set primary oracle price to 1.1e8
        int256 newPrice = 1.1e8;
        primaryOracle.setRate(newPrice);
        // set accountant timestamp to 5 days ago
        IAccountant.AccountantState memory state = accountant.accountantState();
        state.lastUpdateTimestamp = uint64(block.timestamp - 5 days);
        accountant.setState(state);
        // set fallback oracle price to 1.002e8
        int256 fallbackPrice = 1.002e8;
        fallbackOracle.setRate(fallbackPrice);

        int256 newPriceForEMA = fallbackPrice; // fallback price is used
        int256 oldEMA = oracle.latestEMA();
        uint256 multiplierValue = oracle.multiplier();
        int256 expectedEMA =
            (newPriceForEMA * int256(multiplierValue) + oldEMA * int256(10000 - multiplierValue)) / int256(10000);

        uint256 expectedEMAUpperBound = uint256(expectedEMA).mulDivDown(10500, 1e4);
        uint256 expectedEMALowerBound = uint256(expectedEMA).mulDivDown(9500, 1e4);

        // check event
        vm.expectEmit(true, true, false, true);
        emit FallbackPriceUsed(uint256(fallbackPrice), "price_out_of_bounds");
        vm.expectEmit(true, true, false, true);
        emit MovingAverageUpdated(uint256(oldEMA), uint256(expectedEMA));
        vm.expectEmit(true, true, false, true);
        emit BoundsUpdated(expectedEMAUpperBound, expectedEMALowerBound);

        // update price with executor
        vm.prank(executor);
        oracle.updatePrice();

        // verify results
        // latestAnswer
        assertEq(oracle.latestAnswer(), fallbackPrice);
        // latestEMA
        assertEq(oracle.latestEMA(), expectedEMA);
        // EMAUpperBound
        assertEq(oracle.EMAUpperBound(), expectedEMAUpperBound);
        // EMALowerBound
        assertEq(oracle.EMALowerBound(), expectedEMALowerBound);
    }

    function test_UpdatePrice_PrimaryOracleStaleAndOutOfBoundsAndFallbackOutOfBounds() public {
        // 3-2 condition

        // set primary oracle price to 1.1e8
        int256 newPrice = 1.1e8;
        primaryOracle.setRate(newPrice);
        primaryOracle.setLastUpdateTimestamp(block.timestamp - 5 days);
        // set accountant timestamp to 5 days ago
        IAccountant.AccountantState memory state = accountant.accountantState();
        state.lastUpdateTimestamp = uint64(block.timestamp - 5 days);
        accountant.setState(state);
        // set fallback oracle price to 1.2e8
        int256 fallbackPrice = 1.2e8;
        fallbackOracle.setRate(fallbackPrice);

        int256 previousAnswer = oracle.latestAnswer();
        int256 newPriceForEMA = fallbackPrice; // fallback price is used
        int256 oldEMA = oracle.latestEMA();
        uint256 multiplierValue = oracle.multiplier();
        int256 expectedEMA =
            (newPriceForEMA * int256(multiplierValue) + oldEMA * int256(10000 - multiplierValue)) / int256(10000);

        uint256 expectedEMAUpperBound = uint256(expectedEMA).mulDivDown(10500, 1e4);
        uint256 expectedEMALowerBound = uint256(expectedEMA).mulDivDown(9500, 1e4);

        // check event
        vm.expectEmit(true, true, false, true);
        emit NoPriceUpdate("fallback_price_used_but_no_update", uint256(newPrice), uint256(fallbackPrice));
        vm.expectEmit(true, true, false, true);
        emit MovingAverageUpdated(uint256(oldEMA), uint256(expectedEMA));
        vm.expectEmit(true, true, false, true);
        emit BoundsUpdated(expectedEMAUpperBound, expectedEMALowerBound);

        // update price with executor
        vm.prank(executor);
        oracle.updatePrice();

        // verify results
        // latestAnswer
        assertEq(oracle.latestAnswer(), previousAnswer);
        // latestEMA
        assertEq(oracle.latestEMA(), expectedEMA);
        // EMAUpperBound
        assertEq(oracle.EMAUpperBound(), expectedEMAUpperBound);
        // EMALowerBound
        assertEq(oracle.EMALowerBound(), expectedEMALowerBound);
    }

    function test_AdminFunctions() public {
        // Test updateMaxPriceAge
        uint256 newMaxAge = 72 hours;
        vm.expectEmit(true, true, false, true);
        emit MaxPriceAgeUpdated(48 hours, newMaxAge);
        oracle.updateMaxPriceAge(newMaxAge);
        assertEq(oracle.maxPriceAge(), newMaxAge);

        // Test updatePrimaryOracle
        MockOracle newPrimaryOracle = new MockOracle(address(accountant), 1e8); // Create new mock oracle with initial rate
        vm.expectEmit(true, true, false, true);
        emit PrimaryOracleUpdated(address(primaryOracle), address(newPrimaryOracle));
        oracle.updatePrimaryOracle(address(newPrimaryOracle));
        assertEq(oracle.sSuperUSDOracleAddress(), address(newPrimaryOracle));

        // Test updateFallbackOracle
        MockOracle newFallbackOracle = new MockOracle(address(accountant), 1e8);
        vm.expectEmit(true, true, false, true);
        emit FallbackOracleUpdated(address(fallbackOracle), address(newFallbackOracle));
        oracle.updateFallbackOracle(address(newFallbackOracle));
        assertEq(oracle.sSuperUSDFallbackOracleAddress(), address(newFallbackOracle));

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
        oracle.updateBaseBounds(10100, 9000); // Add test for updateBaseBounds

        vm.expectRevert(sSuperUSDMorphoOracle.NotOwner.selector);
        oracle.transferOwnership(address(0x1));

        vm.stopPrank();
    }

    function test_ViewFunctions() public {
        // Test getPrecision
        assertEq(oracle.getPrecision(), 36 + 6 - 18); // 36 + loanDecimals - collateralDecimals
    }

    // Test executor functionality
    function test_UpdateExecutor() public {
        address newExecutor = makeAddr("newExecutor");

        // Non-owner cannot add executor
        vm.prank(makeAddr("nonOwner"));
        vm.expectRevert(sSuperUSDMorphoOracle.NotOwner.selector);
        oracle.updateExecutor(newExecutor, true);

        // Owner can add executor
        oracle.updateExecutor(newExecutor, true);
        assertTrue(oracle.executors(newExecutor));

        // Owner can remove executor
        oracle.updateExecutor(newExecutor, false);
        assertFalse(oracle.executors(newExecutor));

        // Non-executor cannot call updatePrice
        vm.prank(makeAddr("nonExecutor"));
        vm.expectRevert(sSuperUSDMorphoOracle.NotExecutor.selector);
        oracle.updatePrice();

        // Executor can call updatePrice
        vm.prank(executor);
        oracle.updatePrice();
    }
}
