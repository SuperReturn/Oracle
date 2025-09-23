// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {sSuperUSDFallbackOracle} from "../src/sSuperUSDFallbackOracle.sol";
import {console} from "forge-std/console.sol";

// test against the Kyo SolvBTC-SolvBTCJUP 0.05% pool on Soneium
contract sSuperUSDFallbackOracleTest is Test {
    // Test contract state variables
    sSuperUSDFallbackOracle public oracle01;
    sSuperUSDFallbackOracle public oracle10;
    address public owner;
    address public uniV3Pool = 0x3fe298aa69EC9A033896119172e01a6FF530e4b8;

    // Fork configuration
    uint256 public forkBlock = 12736900;
    uint256 public soneiumFork;

    // Events to test
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TwapIntervalSet(uint32 twapInterval);

    // error from uni v3 pool
    error OLD();

    function setUp() public {
        // Create and select fork
        soneiumFork = vm.createFork(
            vm.envString("SONEIUM_RPC_URL"),
            forkBlock
        );
        vm.selectFork(soneiumFork);
        
        // Set up test addresses
        owner = address(this);
        
        // Deploy oracle - 1 SolvBTC = x SolvBTCJUP
        oracle01 = new sSuperUSDFallbackOracle(uniV3Pool, true, 18, 18, 60);
        // Deploy oracle in other direction - x SolvBTC = 1 SolvBTCJUP
        oracle10 = new sSuperUSDFallbackOracle(uniV3Pool, false, 18, 18, 60);
        
        // Verify initial state
        assertEq(oracle01.owner(), address(this));
        assertEq(oracle01.uniV3Pool(), uniV3Pool);
    }

    // Test constructor
    function test_Constructor() public view{
        assertEq(oracle01.owner(), address(this));
        assertEq(oracle01.uniV3Pool(), uniV3Pool);
        assertEq(oracle01.zeroForOne(), true);
        assertEq(oracle01.decimals0(), 18);
        assertEq(oracle01.decimals1(), 18);
        assertEq(oracle01.twapInterval(), 60);
    }
    
    // Test constructor with zero address
    function test_Constructor_RevertZeroAddress() public {
        vm.expectRevert("Pool cannot be zero address");
        new sSuperUSDFallbackOracle(address(0), true, 18, 18, 60);
    }
    
    // Test constructor with zero twap interval
    function test_Constructor_RevertZeroTwapInterval() public {
        vm.expectRevert("Twap interval cannot be 0");
        new sSuperUSDFallbackOracle(uniV3Pool, true, 18, 18, 0);
    }
    
    // Test constructor with too long twap interval
    function test_Constructor_RevertTooLongTwapInterval() public {
        vm.expectRevert("Twap interval too long");
        new sSuperUSDFallbackOracle(uniV3Pool, true, 18, 18, 604801);
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
        assertEq(latestAnswer, 94129661);
        // Get latest round data
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracle01.latestRoundData();
        // Verify the returned values
        assertEq(roundId, 0);
        assertEq(answer, 94129661);
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 0);
    }

    function test_LatestAnswer10() public {
        int256 latestAnswer = oracle10.latestAnswer();
        //console.log("Latest Answer :", latestAnswer);
        //console.log("One           :", uint256(100000000));
        // 1 / 1.03
        assertEq(latestAnswer, 106236438);
        // Get latest round data
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracle10.latestRoundData();
        // Verify the returned values
        assertEq(roundId, 0);
        assertEq(answer, 106236438);
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

    // test set twap interval too long
    function test_RevertSetTwapIntervalTooLong() public {
        vm.expectRevert("Twap interval too long");
        oracle01.setTwapInterval(604801);
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

        // observation cardinality of this pool is too low, will revert with UniswapV3Pool.OLD()

        vm.expectRevert(OLD.selector);
        int256 latestAnswer01 = oracle01.latestAnswer();

        vm.expectRevert(OLD.selector);
        int256 latestAnswer10 = oracle10.latestAnswer();

        /*
        console.log("getting latest answer 01");
        int256 latestAnswer01 = oracle01.latestAnswer();
        console.log("Latest Answer 01 :", latestAnswer01);

        console.log("getting latest answer 10");
        int256 latestAnswer10 = oracle10.latestAnswer();
        console.log("Latest Answer 10 :", latestAnswer10);

        assertEq(latestAnswer01, 103055603);
        assertEq(latestAnswer10, 97034995);
        */

        //console.log("max int24", type(int24).max);
        //console.log("min int24", type(int24).min);
    }
}