/*
forge script script/DeployMockAccountant.s.sol --rpc-url arbitrum --broadcast --verify
*/

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.21;

import {Script} from "forge-std/Script.sol";
import {MockAccountant} from "../src/mockAccountant.sol";

contract DeploySSuperUSDOracle is Script {
    function run() external {
        // Begin recording transactions for deployment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MockAccountant oracle = new MockAccountant();

        // Stop recording transactions
        vm.stopBroadcast();

        // Log the deployed contract address
        // console.log("sSuperUSDOracle deployed to:", address(oracle));
    }
}
