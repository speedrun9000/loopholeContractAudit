// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PresaleFactory} from "../src/PresaleFactory.sol";
import {PresaleImplementation} from "../src/PresaleImplementation.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BFactory} from "../src/interfaces/IBFactory.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployPresaleFactory
 * @notice Deployment script for the PresaleFactory system
 * @dev Deploys the implementation, beacon, and factory
 */
contract DeployPresaleFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address bFactoryAddress = vm.envAddress("BFACTORY_ADDRESS");
        address multisigAdminAddress = vm.envAddress("MULTISIG_ADMIN");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the implementation contract
        console.log("Deploying PresaleImplementation...");
        PresaleImplementation implementation = new PresaleImplementation();
        console.log("PresaleImplementation deployed at:", address(implementation));

        // Deploy the UpgradeableBeacon
        console.log("\nDeploying UpgradeableBeacon...");
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), multisigAdminAddress);
        console.log("UpgradeableBeacon deployed at:", address(beacon));

        // Deploy the factory implementation and proxy
        console.log("\nDeploying PresaleFactory...");
        PresaleFactory factoryImpl = new PresaleFactory();
        console.log("PresaleFactory implementation deployed at:", address(factoryImpl));
        ERC1967Proxy factoryProxy = new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeCall(factoryImpl.initialize, (beacon, BFactory(bFactoryAddress), multisigAdminAddress))
        );
        PresaleFactory factory = PresaleFactory(address(factoryProxy));
        console.log("PresaleFactory proxy deployed at:", address(factory));

        vm.stopBroadcast();

        // Log deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("Presale Implementation:", address(implementation));
        console.log("Beacon:", address(beacon));
        console.log("Beacon Owner:", multisigAdminAddress);
        console.log("Factory Implementation:", address(factoryImpl));
        console.log("Factory Proxy:", address(factory));
        console.log("Factory Owner:", multisigAdminAddress);
        console.log("BFactory:", bFactoryAddress);
        console.log("Current Implementation:", factory.getImplementation());

        console.log("\n=== Verification Commands ===");
        console.log("Implementation:");
        console.log(
            "  forge verify-contract", address(implementation), "src/PresaleImplementation.sol:PresaleImplementation"
        );
        console.log("\nBeacon:");
        //console.log("  forge verify-contract", address(beacon), "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol:UpgradeableBeacon --constructor-args $(cast abi-encode 'constructor(address,address)' ", address(implementation), multisigAdminAddress, ")");
        console.log("\nFactory:");
        // console.log("  forge verify-contract", address(factory), "src/PresaleFactory.sol:PresaleFactory --constructor-args $(cast abi-encode 'constructor(address,address,address)' ", address(beacon), bFactoryAddress, multisigAdminAddress, ")");
        string memory factoryAddressString = string(abi.encodePacked(address(factory)));
        vm.setEnv("FACTORY_ADDRESS", factoryAddressString);
    }
}
