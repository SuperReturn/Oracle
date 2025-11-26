// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.21;

import {Script} from "forge-std/Script.sol";
import {sSuperUSDOracle} from "../src/sake/sSuperUSDOracle.sol";

contract DeploySakesSuperUSDOracle is Script {
    function run() external {
        // Begin recording transactions for deployment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address sSuperUSDAccountantAddress = 0x2B570475489e55b63bC5121EEe75f5D22C9C17C0; //v1

        sSuperUSDOracle oracle = new sSuperUSDOracle();
        oracle.setsSuperUSDOracle(sSuperUSDAccountantAddress);


        // Stop recording transactions
        vm.stopBroadcast();

        // Log the deployed contract address
        // console.log("sSuperUSDOracle deployed to:", address(oracle));
    }
}
