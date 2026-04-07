// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ProjectFeeRouterUpgradeable} from "../src/ProjectFeeRouterUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployProjectFeeRouter
 * @notice Deploys ProjectFeeRouterUpgradeable behind a UUPS proxy
 *
 * Required env vars:
 *   PRIVATE_KEY    - deployer private key
 *   ADMIN_ADDRESS  - owner of the fee router (multisig)
 */
contract DeployProjectFeeRouter is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.envAddress("ADMIN_ADDRESS");

        console.log("=== ProjectFeeRouter Deployment Configuration ===");
        console.log("Admin:", admin);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        ProjectFeeRouterUpgradeable implementation = new ProjectFeeRouterUpgradeable();
        console.log("Implementation deployed at:", address(implementation));

        // Deploy UUPS proxy
        bytes memory initData = abi.encodeCall(implementation.initialize, (admin));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        ProjectFeeRouterUpgradeable router = ProjectFeeRouterUpgradeable(address(proxy));

        console.log("ProjectFeeRouter proxy deployed at:", address(router));

        vm.stopBroadcast();

        // Verify deployment
        console.log("\n=== Deployment Summary ===");
        console.log("Implementation:", address(implementation));
        console.log("Proxy:", address(router));
        console.log("Owner:", router.owner());
    }
}
