// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.21;

import {Script} from "forge-std/Script.sol";
import {sSuperUSDMorphoOracle} from "../src/sSuperUSDMorphoOracle.sol";

contract DeploySSuperUSDOracle is Script {
    function run() external {
        // Begin recording transactions for deployment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy sSuperUSDOracle contract
        // Arbitrum Mainnet Addresses
        address collateralToken = 0x139450C2dCeF827C9A2a0Bb1CB5506260940c9fd;  // sSuperUSD
        address loanToken = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;        // USDC
        address oracleAddress = 0xdF206c6Ebb600365A47889DF1A0C691a83fa58b0;    // sSuperUSD Oracle

        sSuperUSDMorphoOracle oracle = new sSuperUSDMorphoOracle(
            collateralToken,
            loanToken,
            oracleAddress
        );

        // Stop recording transactions
        vm.stopBroadcast();

        // Log the deployed contract address
        // console.log("sSuperUSDOracle deployed to:", address(oracle));
    }
}
