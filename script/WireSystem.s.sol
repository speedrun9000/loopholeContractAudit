// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ProjectFeeRouterUpgradeable} from "../src/ProjectFeeRouterUpgradeable.sol";
import {AfterburnerUpgradeable} from "../src/AfterburnerUpgradeable.sol";
import {NftMarketplace} from "../src/NftMarketplace.sol";

/**
 * @title WireSystem
 * @notice Wires together all deployed contracts:
 *         1. Registers bTokens on the ProjectFeeRouter
 *         2. Sets fee split configs on the ProjectFeeRouter
 *         3. Sets collection<>bToken mappings on the NftMarketplace
 *         4. Authorizes the ProjectFeeRouter as a funder on the Afterburner
 *
 * Required env vars:
 *   PRIVATE_KEY              - admin private key (must be owner of all contracts)
 *   FEE_ROUTER_ADDRESS       - deployed ProjectFeeRouter proxy
 *   AFTERBURNER_ADDRESS      - deployed Afterburner proxy
 *   NFT_MARKETPLACE_ADDRESS  - deployed NftMarketplace proxy
 *   LOOP_BTOKEN_ADDRESS      - the LOOP bToken address
 *   LST_BTOKEN_ADDRESS       - the LST bToken address
 *   RESERVE_ADDRESS          - reserve token (e.g. WETH) for the LOOP pool
 *   NFT_COLLECTION_ADDRESS   - NFT collection paired with the LST bToken
 *   TREASURY_ADDRESS         - acquisition treasury recipient
 *   ROYALTIES_ADDRESS        - royalties recipient
 *   TEAM_ADDRESS             - team recipient
 *   BLV_MODULE_ADDRESS       - BLV module address
 */
contract WireSystem is Script {
    // ======================== FEE CONFIG CONSTANTS ========================

    // FeeRouter: LST bToken split (treasury + royalties)
    uint16 constant LST_BPS_TREASURY = 6667;
    uint16 constant LST_BPS_ROYALTIES = 3333;
    uint16 constant LST_BPS_TEAM = 0;
    uint16 constant LST_BPS_AFTERBURNER = 0;
    uint16 constant LST_BPS_BLV = 0;

    // FeeRouter: LOOP bToken split (all to team)
    uint16 constant LOOP_BPS_TREASURY = 0;
    uint16 constant LOOP_BPS_ROYALTIES = 0;
    uint16 constant LOOP_BPS_TEAM = 10000;
    uint16 constant LOOP_BPS_AFTERBURNER = 0;
    uint16 constant LOOP_BPS_BLV = 0;

    // NftMarketplace: bToken sale proceeds split
    uint16 constant MARKETPLACE_BPS_AFTERBURNER = 7000;
    uint16 constant MARKETPLACE_BPS_BLV = 3000;

    // NftMarketplace: auction params
    uint256 constant AUCTION_DURATION = 7 days;
    uint256 constant MAX_OFFER_INCREASE_RATE = 1e15;
    uint256 constant MIN_AUCTION_PRICE = 1e12;

    // =====================================================================

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Deployed contract addresses
        address feeRouterAddr = vm.envAddress("FEE_ROUTER_ADDRESS");
        address afterburnerAddr = vm.envAddress("AFTERBURNER_ADDRESS");
        address nftMarketplaceAddr = vm.envAddress("NFT_MARKETPLACE_ADDRESS");

        // Token addresses
        address loopBToken = vm.envAddress("LOOP_BTOKEN_ADDRESS");
        address lstBToken = vm.envAddress("LST_BTOKEN_ADDRESS");
        address reserve = vm.envAddress("RESERVE_ADDRESS");
        address nftCollection = vm.envAddress("NFT_COLLECTION_ADDRESS");

        // Recipient addresses
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address royalties = vm.envAddress("ROYALTIES_ADDRESS");
        address team = vm.envAddress("TEAM_ADDRESS");
        address blvModule = vm.envAddress("BLV_MODULE_ADDRESS");

        // Contract instances
        ProjectFeeRouterUpgradeable router = ProjectFeeRouterUpgradeable(feeRouterAddr);
        AfterburnerUpgradeable afterburner = AfterburnerUpgradeable(afterburnerAddr);
        NftMarketplace marketplace = NftMarketplace(nftMarketplaceAddr);

        console.log("=== Wire System Configuration ===");
        console.log("FeeRouter:", feeRouterAddr);
        console.log("Afterburner:", afterburnerAddr);
        console.log("NftMarketplace:", nftMarketplaceAddr);
        console.log("LOOP bToken:", loopBToken);
        console.log("LST bToken:", lstBToken);
        console.log("Reserve:", reserve);
        console.log("NFT Collection:", nftCollection);

        vm.startBroadcast(deployerPrivateKey);

        // ============================================================
        // 1. Register bTokens on ProjectFeeRouter
        // ============================================================
        console.log("\n--- Registering bTokens on FeeRouter ---");

        // LOOP bToken uses the reserve token (e.g. WETH) as its reserve
        router.registerBToken(loopBToken, reserve);
        console.log("Registered LOOP bToken with reserve:", reserve);

        // LST bToken uses the LOOP bToken as its reserve
        router.registerBToken(lstBToken, loopBToken);
        console.log("Registered LST bToken with reserve (LOOP):", loopBToken);

        // ============================================================
        // 2. Configure fee splits on ProjectFeeRouter
        // ============================================================
        console.log("\n--- Setting fee configs on FeeRouter ---");

        // LST bToken fee split
        router.setConfig(
            lstBToken,
            ProjectFeeRouterUpgradeable.FeeConfig({
                bpsToAcquisitionTreasury: LST_BPS_TREASURY,
                bpsToRoyalties: LST_BPS_ROYALTIES,
                bpsToTeam: LST_BPS_TEAM,
                bpsToAfterburner: LST_BPS_AFTERBURNER,
                bpsToBLV: LST_BPS_BLV
            }),
            ProjectFeeRouterUpgradeable.Recipients({
                acquisitionTreasury: nftMarketplaceAddr,
                royaltyRecipient: royalties,
                team: team,
                afterburner: afterburnerAddr,
                blvModule: blvModule
            })
        );
        console.log("LST fee config set: 6667 treasury, 3333 royalties");

        // LOOP bToken fee split
        router.setConfig(
            loopBToken,
            ProjectFeeRouterUpgradeable.FeeConfig({
                bpsToAcquisitionTreasury: LOOP_BPS_TREASURY,
                bpsToRoyalties: LOOP_BPS_ROYALTIES,
                bpsToTeam: LOOP_BPS_TEAM,
                bpsToAfterburner: LOOP_BPS_AFTERBURNER,
                bpsToBLV: LOOP_BPS_BLV
            }),
            ProjectFeeRouterUpgradeable.Recipients({
                acquisitionTreasury: address(0),
                royaltyRecipient: address(0),
                team: team,
                afterburner: afterburnerAddr,
                blvModule: blvModule
            })
        );
        console.log("LOOP fee config set: 10000 team");

        // ============================================================
        // 3. Configure NftMarketplace collection<>bToken mapping
        // ============================================================
        console.log("\n--- Configuring NftMarketplace ---");

        NftMarketplace.BTokenFeeConfig memory marketplaceFeeConfig = NftMarketplace.BTokenFeeConfig({
            bpsToAfterburner: MARKETPLACE_BPS_AFTERBURNER, bpsToBLV: MARKETPLACE_BPS_BLV
        });
        NftMarketplace.BTokenRecipients memory marketplaceRecipients =
            NftMarketplace.BTokenRecipients({afterburner: afterburnerAddr, blvModule: blvModule});

        marketplace.setCollectionForBToken({
            bToken: lstBToken,
            nftCollection: nftCollection,
            _auctionDuration: AUCTION_DURATION,
            _maxOfferIncreaseRate: MAX_OFFER_INCREASE_RATE,
            _minAuctionPrice: MIN_AUCTION_PRICE,
            feeConfig: marketplaceFeeConfig,
            recipients: marketplaceRecipients
        });
        console.log("Collection set for LST bToken on marketplace");

        // ============================================================
        // 4. Authorize FeeRouter as funder on Afterburner
        // ============================================================
        console.log("\n--- Authorizing funder on Afterburner ---");

        afterburner.setAuthorizedFunder(feeRouterAddr, true);
        console.log("FeeRouter authorized as funder on Afterburner");

        vm.stopBroadcast();

        // ============================================================
        // Verify wiring
        // ============================================================
        console.log("\n=== Verification ===");
        console.log("FeeRouter LOOP reserve:", router.reserve(loopBToken));
        console.log("FeeRouter LST reserve:", router.reserve(lstBToken));
        console.log("Marketplace collection for LST:", marketplace.collectionForBToken(lstBToken));
        console.log("Marketplace bToken for collection:", marketplace.bTokenForCollection(nftCollection));
        console.log("Afterburner feeRouter authorized:", afterburner.authorizedFunders(feeRouterAddr));

        console.log("\n=== Wiring Complete ===");
    }
}
