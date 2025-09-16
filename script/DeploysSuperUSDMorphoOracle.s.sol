// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {sSuperUSDOracle} from "../src/sSuperUSDOracle.sol";

contract DeploySSuperUSDOracle is Script {
    function run() external {
        // Begin recording transactions for deployment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        sSuperUSDOracle oracle = new sSuperUSDOracle();

        // Stop recording transactions
        vm.stopBroadcast();

        // Log the deployed contract address
        // console.log("sSuperUSDOracle deployed to:", address(oracle));
    }
}
