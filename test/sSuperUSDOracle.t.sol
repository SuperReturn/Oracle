// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {sSuperUSDOracle, IsSuperUSDOracle, IAccountant} from "../src/sSuperUSDOracle.sol";
import {console} from "forge-std/console.sol";

contract sSuperUSDOracleTest is Test {
    // Test contract state variables
    sSuperUSDOracle public oracle;
    address public owner;
    address public superUSDAccountant;
    address public sSuperUSDAccountant;

    // Fork configuration
    uint256 public forkBlock = 379760000;
    uint256 public arbitrumFork;

    // Events to test
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setUp() public {
        // Create and select fork
        arbitrumFork = vm.createFork(vm.envString("ARBITRUM_RPC_URL"), forkBlock);
        vm.selectFork(arbitrumFork);

        // Set up test addresses
        owner = address(this);
        superUSDAccountant = makeAddr("superUSDAccountant");
        sSuperUSDAccountant = makeAddr("sSuperUSDAccountant");

        // Deploy oracle
        oracle = new sSuperUSDOracle(superUSDAccountant, sSuperUSDAccountant);

        // Verify initial state
        assertEq(oracle.owner(), address(this));
        assertEq(oracle.superUSDAccountant(), superUSDAccountant);
        assertEq(oracle.sSuperUSDAccountant(), sSuperUSDAccountant);
    }

    // Test constructor
    function test_Constructor() public {
        assertEq(oracle.owner(), address(this));
        assertEq(oracle.superUSDAccountant(), superUSDAccountant);
        assertEq(oracle.sSuperUSDAccountant(), sSuperUSDAccountant);
    }

    function test_Constructor_RevertZeroAddress_sSuperUSDAccountant() public {
        vm.expectRevert("Accountant cannot be zero address");
        new sSuperUSDOracle(superUSDAccountant, address(0));
    }

    // Test ownership transfer
    function test_TransferOwnership() public {
        address newOwner = makeAddr("newOwner");

        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(address(this), newOwner);

        oracle.transferOwnership(newOwner);
        assertEq(oracle.owner(), newOwner);
    }

    // Test ownership transfer to zero address
    function test_TransferOwnership_RevertZeroAddress() public {
        vm.expectRevert("New owner cannot be zero address");
        oracle.transferOwnership(address(0));
    }

    // Test ownership transfer from non-owner
    function test_TransferOwnership_RevertNonOwner() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert("Only owner can call this function");
        oracle.transferOwnership(makeAddr("newOwner"));
    }

    // Test latestRoundData
    function test_LatestRoundData() public {
        // Deploy mock accountants
        MockAccountant mockSuperUSDAccountant = new MockAccountant(1_000_000); // 1.0 with 6 decimals
        MockAccountant mockSSuperUSDAccountant = new MockAccountant(1_100_000); // 1.1 with 6 decimals

        // Deploy oracle with mock accountants
        oracle = new sSuperUSDOracle(
            address(mockSuperUSDAccountant),
            address(mockSSuperUSDAccountant)
        );

        // Get latest round data
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracle.latestRoundData();

        // Calculate expected rate: (1.0 * 1.1) with proper decimal adjustment
        // 1_000_000 * 1_100_000 / 1e4 = 110_000_000 (1.1 with 8 decimals)
        uint256 expectedRate = (1_000_000 * 1_100_000) / 1e4;

        // Verify the returned values
        assertEq(roundId, 0);
        assertEq(answer, int256(expectedRate));
        assertEq(startedAt, mockSSuperUSDAccountant.accountantState().lastUpdateTimestamp);
        assertEq(updatedAt, mockSSuperUSDAccountant.accountantState().lastUpdateTimestamp);
        assertEq(answeredInRound, 0);
    }
}

// Enhanced Mock Accountant contract for testing
contract MockAccountant {
    uint256 private rate;
    uint64 private constant MOCK_TIMESTAMP = 1695744000; // Changed to uint64 for proper type matching

    constructor(uint256 _rate) {
        rate = _rate;
    }

    function getRateSafe() external view returns (uint256) {
        return rate;
    }

    function accountantState() external pure returns (AccountantState memory) {
        return AccountantState(
            address(0),           // payoutAddress
            0,                    // highwaterMark
            0,                    // feesOwedInBase
            0,                    // totalSharesLastUpdate
            0,                    // exchangeRate
            0,                    // allowedExchangeRateChangeUpper
            0,                    // allowedExchangeRateChangeLower
            MOCK_TIMESTAMP,       // lastUpdateTimestamp
            false,               // isPaused
            0,                    // minimumUpdateDelayInSeconds
            0,                    // platformFee
            0                     // performanceFee
        );
    }
}

// Updated AccountantState struct to match IAccountant interface
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
