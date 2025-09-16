// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.21;

import {Script} from "forge-std/Script.sol";
import {sSuperUSDOracle} from "../src/sSuperUSDOracle.sol";

contract DeploySSuperUSDOracle is Script {
    function run() external {
        // Begin recording transactions for deployment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address accountantAddress = 0xFec60259f315287252c495C5921A30209Dd1FA4e;

        sSuperUSDOracle oracle = new sSuperUSDOracle(accountantAddress);

        // Stop recording transactions
        vm.stopBroadcast();

        // Log the deployed contract address
        // console.log("sSuperUSDOracle deployed to:", address(oracle));
    }
}
