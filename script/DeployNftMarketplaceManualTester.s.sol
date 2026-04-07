// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {NftMarketplaceManualTester} from "../test/NftMarketplaceManualTester.sol";

contract DeployNftMarketplaceManualTester is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        NftMarketplaceManualTester nftMarketplaceManualTester = new NftMarketplaceManualTester();
        nftMarketplaceManualTester.setUp();

        vm.stopBroadcast();

        console.log("nftMarketplaceManualTester deployed at:", address(nftMarketplaceManualTester));
    }
}
