// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {AfterburnerUpgradeable} from "../src/AfterburnerUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployAfterburner
 * @notice Deploys AfterburnerUpgradeable behind a UUPS proxy
 *
 * Required env vars:
 *   PRIVATE_KEY       - deployer private key
 *   ADMIN_ADDRESS     - owner of the afterburner (multisig)
 *   BTOKEN_ADDRESS    - the bToken to buy back
 *   RESERVE_ADDRESS   - the reserve token (e.g. WETH)
 *   BASELINE_ADDRESS  - the Baseline relay address
 */
contract DeployAfterburner is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address bToken = vm.envAddress("BTOKEN_ADDRESS");
        address reserve = vm.envAddress("RESERVE_ADDRESS");
        address baseline = vm.envAddress("BASELINE_ADDRESS");

        console.log("=== Afterburner Deployment Configuration ===");
        console.log("Admin:", admin);
        console.log("bToken:", bToken);
        console.log("Reserve:", reserve);
        console.log("Baseline:", baseline);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        AfterburnerUpgradeable implementation = new AfterburnerUpgradeable();
        console.log("Implementation deployed at:", address(implementation));

        // Deploy UUPS proxy
        bytes memory initData = abi.encodeCall(implementation.initialize, (admin, bToken, reserve, baseline));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        AfterburnerUpgradeable afterburner = AfterburnerUpgradeable(address(proxy));

        console.log("Afterburner proxy deployed at:", address(afterburner));

        vm.stopBroadcast();

        // Verify deployment
        console.log("\n=== Deployment Summary ===");
        console.log("Implementation:", address(implementation));
        console.log("Proxy:", address(afterburner));
        console.log("Owner:", afterburner.owner());
        console.log("bToken:", afterburner.bToken());
        console.log("Reserve:", afterburner.reserveToken());
        console.log("Baseline:", afterburner.baseline());
    }
}
