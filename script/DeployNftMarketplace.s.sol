// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {NftMarketplace} from "../src/NftMarketplace.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title DeployNftMarketplace
 * @notice Deployment script for deploying a new NftMarketplace instance
 */
contract DeployNftMarketplace is Script {
    function run() external {
        // Get configuration from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address adminAddress = vm.envAddress("ADMIN_ADDRESS");
        address loopToken = vm.envAddress("LOOP_TOKEN_ADDRESS");
        address feeRouter = vm.envAddress("FEE_ROUTER_ADDRESS");
        address bswap = vm.envAddress("BSWAP_ADDRESS");

        console.log("=== Presale Deployment Configuration ===");
        console.log("Admin:", adminAddress);
        console.log("Loop Token:", loopToken);
        console.log("Fee Router:", feeRouter);
        console.log("bswap:", bswap);

        vm.startBroadcast(deployerPrivateKey);

        NftMarketplace nftMarketplaceImplementation = new NftMarketplace();
        bytes memory _data = abi.encodeWithSelector(
            NftMarketplace.initialize.selector,
            loopToken, // IERC20 _offerToken,
            feeRouter, // address _feeRouter,
            adminAddress, // address initialOwner,
            bswap, // IBSwap _bSwap,
            adminAddress // address _swapper
        );
        NftMarketplace nftMarketplace = NftMarketplace(
            address(
                new TransparentUpgradeableProxy({
                    _logic: address(nftMarketplaceImplementation), initialOwner: adminAddress, _data: _data
                })
            )
        );

        console.log("nftMarketplaceImplementation deployed at:", address(nftMarketplaceImplementation));
        console.log("nftMarketplace deployed at:", address(nftMarketplace));

        vm.stopBroadcast();

        // Verify deployment
    }
}
