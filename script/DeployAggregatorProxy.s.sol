/*
forge script script/DeployAggregatorProxy.s.sol --rpc-url arbitrum --broadcast --verify
*/

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.21;

import {Script} from "forge-std/Script.sol";
import {AggregatorProxy} from "../src/AggregatorProxy.sol";

contract DeployAggregatorProxy is Script {
    function run() external {
        // Begin recording transactions for deployment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy sSuperUSDOracle contract
        // Arbitrum Mainnet Addresses
        address collateralToken = 0x139450C2dCeF827C9A2a0Bb1CB5506260940c9fd; // sSuperUSD
        address loanToken = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // USDC
        address oracleAddress = 0xeE5c880eE6022FA6f1b790c4F212DdE148c14A3b; // sSuperUSD Oracle
        address fallbackOracleAddress = 0xcCBdd9968eF307cB7A27f0F9f389862cdb9685e2; // sSuperUSD Fallback Oracle

        AggregatorProxy oracle =
            new AggregatorProxy(collateralToken, loanToken, oracleAddress, fallbackOracleAddress);

        // Stop recording transactions
        vm.stopBroadcast();
    }
}
