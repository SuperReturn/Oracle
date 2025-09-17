// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {sSuperUSDOracle, IsSuperUSDOracle, IAccountant} from "../src/sSuperUSDOracle.sol";
import {console} from "forge-std/console.sol";

contract sSuperUSDOracleTest is Test {
    // Test contract state variables
    sSuperUSDOracle public oracle;
    address public owner;
    address public accountant;

    // Fork configuration
    uint256 public forkBlock = 379760000;
    uint256 public arbitrumFork;

    // Events to test
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RateUpdated(uint256 indexed roundId, uint256 rate, uint256 timestamp);

    function setUp() public {
        // Create and select fork
        arbitrumFork = vm.createFork(
            vm.envString("ARBITRUM_RPC_URL"),
            forkBlock
        );
        vm.selectFork(arbitrumFork);
        
        // Set up test addresses
        owner = address(this);
        accountant = makeAddr("accountant"); // Create a mock accountant address
        
        // Deploy oracle
        oracle = new sSuperUSDOracle(accountant);
        
        // Verify initial state
        assertEq(oracle.owner(), address(this));
        assertEq(oracle.sSuperUSDAccountant(), accountant);
    }

    // Test constructor
    function test_Constructor() public view{
        assertEq(oracle.owner(), address(this));
        assertEq(oracle.sSuperUSDAccountant(), accountant);
        assertEq(oracle.lastUpdateTimestamp(), block.timestamp);
    }

    // Test constructor with zero address
    function test_Constructor_RevertZeroAddress() public {
        vm.expectRevert("Accountant cannot be zero address");
        new sSuperUSDOracle(address(0));
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
        // Create mock accountant contract that returns a rate
        // MockAccountant mockAccountant = new MockAccountant();
        address accountantAddress = 0xFec60259f315287252c495C5921A30209Dd1FA4e;
        oracle = new sSuperUSDOracle(accountantAddress);

        // Get latest round data
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = oracle.latestRoundData();

        // Verify the returned values
        assertEq(roundId, 0);
        // assertEq(answer, 1_000_000_00); // 1.0 with 8 decimals (converted from 6)
        assertEq(answer, int256(IAccountant(accountantAddress).getRate() * 100));
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 0);
    }
}

// Mock Accountant contract for testing
contract MockAccountant {
    function getRate() external pure returns (uint256) {
        return 1_000_000; // Return 1.0 with 6 decimals
    }
}
