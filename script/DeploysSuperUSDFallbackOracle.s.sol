// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.21;

import {Script} from "forge-std/Script.sol";
import {sSuperUSDFallbackOracle} from "../src/sSuperUSDFallbackOracle.sol";

contract DeploySSuperUSDFallbackOracle is Script {
    function run() external {
        // Begin recording transactions for deployment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address uniV3Pool = 0xE4BDd6902F56eF4e2DEF0223949dF1c4038Bea4a; // sSuperUSD/USDC 0.05% pool
        bool zeroForOne = true; // 1 sSuperUSD = x USDC
        uint8 decimals0 = 6; // sSuperUSD
        uint8 decimals1 = 6; // USDC
        uint32 twapInterval = 3600; // one hour

        sSuperUSDFallbackOracle oracle = new sSuperUSDFallbackOracle(uniV3Pool, zeroForOne, decimals0, decimals1, twapInterval);

        // Stop recording transactions
        vm.stopBroadcast();

        // Log the deployed contract address
        // console.log("sSuperUSDFallbackOracle deployed to:", address(oracle));
    }
}
