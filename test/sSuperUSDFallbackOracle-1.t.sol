// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {sSuperUSDFallbackOracle} from "../src/sSuperUSDFallbackOracle.sol";
import {console} from "forge-std/console.sol";

// test against the Kyo sSuperUSD-USDC 0.05% pool on Soneium
contract sSuperUSDFallbackOracleTest is Test {
    // Test contract state variables
    sSuperUSDFallbackOracle public oracle01;
    sSuperUSDFallbackOracle public oracle10;
    address public owner;
    address public uniV3Pool = 0x61006E81DAebd52Bb757b07a26Cb1d459076D5D6;

    // Fork configuration
    uint256 public forkBlock = 12471000;
    uint256 public soneiumFork;

    // Events to test
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TwapIntervalSet(uint32 twapInterval);

    function setUp() public {
        // Create and select fork
        soneiumFork = vm.createFork(
            vm.envString("SONEIUM_RPC_URL"),
            forkBlock
        );
        vm.selectFork(soneiumFork);
        
        // Set up test addresses
        owner = address(this);
        
        // Deploy oracle - 1 sSuperUSD = x USDC
        oracle01 = new sSuperUSDFallbackOracle(uniV3Pool, true, 6, 6, 60);
        // Deploy oracle in other direction - x sSuperUSD = 1 USDC
        oracle10 = new sSuperUSDFallbackOracle(uniV3Pool, false, 6, 6, 60);
        
        // Verify initial state
        assertEq(oracle01.owner(), address(this));
        assertEq(oracle01.uniV3Pool(), uniV3Pool);
    }

    // Test constructor
    function test_Constructor() public view{
        assertEq(oracle01.owner(), address(this));
        assertEq(oracle01.uniV3Pool(), uniV3Pool);
        assertEq(oracle01.zeroForOne(), true);
        assertEq(oracle01.decimals0(), 6);
        assertEq(oracle01.decimals1(), 6);
        assertEq(oracle01.twapInterval(), 60);
    }
    
    // Test constructor with zero address
    function test_Constructor_RevertZeroAddress() public {
        vm.expectRevert("Pool cannot be zero address");
        new sSuperUSDFallbackOracle(address(0), true, 6, 6, 60);
    }
    
    // Test constructor with zero twap interval
    function test_Constructor_RevertZeroTwapInterval() public {
        vm.expectRevert("Twap interval cannot be 0");
        new sSuperUSDFallbackOracle(uniV3Pool, true, 6, 6, 0);
    }

    // Test ownership transfer
    function test_TransferOwnership() public {
        address newOwner = makeAddr("newOwner");
        
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(address(this), newOwner);
        
        oracle01.transferOwnership(newOwner);
        assertEq(oracle01.owner(), newOwner);
    }

    // Test ownership transfer to zero address
    function test_TransferOwnership_RevertZeroAddress() public {
        vm.expectRevert("New owner cannot be zero address");
        oracle01.transferOwnership(address(0));
    }

    // Test ownership transfer from non-owner
    function test_TransferOwnership_RevertNonOwner() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert("Only owner can call this function");
        oracle01.transferOwnership(makeAddr("newOwner"));
        oracle10.transferOwnership(makeAddr("newOwner"));
    }

    function test_LatestAnswer01() public {
        int256 latestAnswer = oracle01.latestAnswer();
        //console.log("Latest Answer :", latestAnswer);
        //console.log("One           :", uint256(100000000));
        // current price is 1.03
        assertEq(latestAnswer, 103065908);
        // Get latest round data
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracle01.latestRoundData();
        // Verify the returned values
        assertEq(roundId, 0);
        assertEq(answer, 103065908);
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 0);
    }

    function test_LatestAnswer10() public {
        int256 latestAnswer = oracle10.latestAnswer();
        //console.log("Latest Answer :", latestAnswer);
        //console.log("One           :", uint256(100000000));
        // 1 / 1.03
        assertEq(latestAnswer, 97025292);
        // Get latest round data
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracle10.latestRoundData();
        // Verify the returned values
        assertEq(roundId, 0);
        assertEq(answer, 97025292);
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 0);
    }

    // test set twap interval by non owner
    function test_RevertSetTwapIntervalByNonOwner() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert("Only owner can call this function");
        oracle01.setTwapInterval(60);
    }

    // test set twap interval to zero
    function test_RevertSetTwapIntervalToZero() public {
        vm.expectRevert("Twap interval cannot be 0");
        oracle01.setTwapInterval(0);
    }

    // test set twap interval
    function test_SetTwapInterval() public {
        vm.expectEmit(true, false, false, false);
        emit TwapIntervalSet(86400);
        oracle01.setTwapInterval(86400);
        assertEq(oracle01.twapInterval(), 86400);

        oracle10.setTwapInterval(86400);
        assertEq(oracle10.twapInterval(), 86400);
    }

    function test_NewLatestAnswer() public {
        oracle01.setTwapInterval(86400);
        oracle10.setTwapInterval(86400);
        assertEq(oracle01.twapInterval(), 86400);
        assertEq(oracle10.twapInterval(), 86400);
        int256 latestAnswer01 = oracle01.latestAnswer();
        int256 latestAnswer10 = oracle10.latestAnswer();
        //console.log("Latest Answer 01 :", latestAnswer01);
        //console.log("Latest Answer 10 :", latestAnswer10);
        assertEq(latestAnswer01, 103055603);
        assertEq(latestAnswer10, 97034995);
    }
}