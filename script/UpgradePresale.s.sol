// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PresaleFactory} from "../src/PresaleFactory.sol";
import {PresaleImplementation} from "../src/PresaleImplementation.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/**
 * @title UpgradePresale
 * @notice Deployment script for upgrading the presale implementation
 * @dev Upgrades all presales by updating the beacon directly
 */
contract UpgradePresale is Script {
    function run() external {
        // Get deployer private key and factory address from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address factoryAddress = vm.envAddress("FACTORY_ADDRESS");

        PresaleFactory factory = PresaleFactory(factoryAddress);
        address beaconAddress = factory.getBeacon();
        UpgradeableBeacon beacon = UpgradeableBeacon(beaconAddress);

        console.log("=== Current State ===");
        console.log("Factory:", factoryAddress);
        console.log("Beacon:", beaconAddress);
        console.log("Current implementation:", factory.getImplementation());
        console.log("Number of presales:", factory.getPresaleCount());

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation
        console.log("\n=== Deploying New Implementation ===");
        PresaleImplementation newImplementation = new PresaleImplementation();
        console.log("New implementation deployed at:", address(newImplementation));

        // Upgrade the beacon directly
        console.log("\n=== Upgrading Beacon ===");
        beacon.upgradeTo(address(newImplementation));
        console.log("Beacon upgraded successfully");

        vm.stopBroadcast();

        // Verify upgrade
        console.log("\n=== Upgrade Summary ===");
        console.log("Factory:", factoryAddress);
        console.log("Beacon:", beaconAddress);
        console.log("New Implementation:", factory.getImplementation());
        console.log("Number of upgraded presales:", factory.getPresaleCount());

        // Verify the upgrade was successful
        require(factory.getImplementation() == address(newImplementation), "Upgrade verification failed");
        console.log("\nUpgrade verified successfully!");

        // List all presales that were upgraded
        address[] memory presales = factory.getAllPresales();
        console.log("\n=== Upgraded Presales ===");
        console.log("Total presales upgraded:", presales.length);
        for (uint256 i = 0; i < presales.length; i++) {
            console.log("  Presale", i, ":", presales[i]);
        }

        console.log("\n=== Verification Command ===");
        console.log("New Implementation:");
        console.log(
            "  forge verify-contract", address(newImplementation), "src/PresaleImplementation.sol:PresaleImplementation"
        );
    }
}
