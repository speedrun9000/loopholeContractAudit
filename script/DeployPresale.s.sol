// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {PresaleFactory} from "../src/PresaleFactory.sol";
import {PresaleImplementation} from "../src/PresaleImplementation.sol";
import {IPresale} from "../src/interfaces/IPresale.sol";

/**
 * @title DeployPresale
 * @notice Deployment script for deploying a new presale instance
 * @dev Deploys a presale through the factory using beacon proxy pattern.
 *      All parameters are read from environment variables.
 *      Supports any number of phases via NUM_PHASES. Phase env vars are
 *      indexed: PHASE0_*, PHASE1_*, PHASE2_*, etc.
 */
contract DeployPresale is Script {
    using Strings for uint256;

    function _readPhase(uint256 i) internal view returns (IPresale.PresalePhaseConfig memory) {
        string memory idx = i.toString();
        return IPresale.PresalePhaseConfig({
            startTime: block.timestamp + vm.envUint(string.concat("PHASE", idx, "_START_OFFSET")),
            endTime: block.timestamp + vm.envUint(string.concat("PHASE", idx, "_END_OFFSET")),
            totalPhaseCap: vm.envUint(string.concat("PHASE", idx, "_CAP")),
            userAllocationCap: vm.envUint(string.concat("PHASE", idx, "_USER_CAP")),
            merkleRoot: vm.envBytes32(string.concat("PHASE", idx, "_MERKLE_ROOT"))
        });
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address factoryAddress = vm.envAddress("FACTORY_ADDRESS");
        address adminAddress = vm.envAddress("ADMIN_ADDRESS");
        address presaleTokenAddress = vm.envAddress("PRESALE_TOKEN_ADDRESS");

        uint256 numPhases = vm.envUint("NUM_PHASES");
        require(numPhases >= 1, "NUM_PHASES must be >= 1");

        uint256 softCap = vm.envUint("SOFT_CAP");
        uint256 hardCap = vm.envUint("HARD_CAP");
        uint256 saleTypeRaw = vm.envUint("SALE_TYPE");
        uint16 circulatingSupplyBps = uint16(vm.envUint("CIRCULATING_SUPPLY_BPS"));
        uint256 initialPoolBTokens = vm.envUint("INITIAL_POOL_BTOKENS");
        uint256 creatorFeePct = vm.envUint("CREATOR_FEE_PCT");

        PresaleFactory factory = PresaleFactory(factoryAddress);

        console.log("=== Presale Deployment Configuration ===");
        console.log("Factory:", factoryAddress);
        console.log("Admin:", adminAddress);
        console.log("Presale Token:", presaleTokenAddress);
        console.log("Current Implementation:", factory.getImplementation());

        vm.startBroadcast(deployerPrivateKey);

        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](numPhases);
        for (uint256 i = 0; i < numPhases; i++) {
            phases[i] = _readPhase(i);
        }

        IPresale.SaleType saleType =
            saleTypeRaw == 0 ? IPresale.SaleType.Credit : IPresale.SaleType.Spot;

        IPresale.PresaleConfig memory config = IPresale.PresaleConfig({
            admin: adminAddress,
            softCap: softCap,
            hardCap: hardCap,
            saleType: saleType,
            circulatingSupplyBps: circulatingSupplyBps
        });

        IPresale.BFactoryParams memory bFactoryParams = IPresale.BFactoryParams({
            bToken: address(0),
            initialPoolBTokens: initialPoolBTokens,
            creator: adminAddress,
            creatorFeePct: creatorFeePct,
            createHook: false,
            claimMerkleRoot: bytes32(0),
            initialCollateral: 0,
            initialDebt: 0
        });

        console.log("\n=== Deploying Presale ===");
        address presale = factory.deployPresale(phases, config, bFactoryParams, presaleTokenAddress);
        console.log("Presale deployed at:", presale);

        vm.stopBroadcast();

        // Verify deployment
        PresaleImplementation presaleImpl = PresaleImplementation(payable(presale));

        console.log("\n=== Presale Summary ===");
        console.log("Presale Address:", presale);
        console.log("Admin:", adminAddress);
        console.log("Number of Phases:", presaleImpl.getPhaseCount());
        console.log("Soft Cap:", config.softCap);
        console.log("Hard Cap:", config.hardCap);
        console.log("Sale Type:", saleTypeRaw == 0 ? "Credit" : "Spot");
        console.log("Circulating Supply Bps:", circulatingSupplyBps);
        console.log("BFactory Address:", factory.getBFactoryAddress());

        console.log("\n=== Phase Details ===");
        for (uint8 i = 0; i < phases.length; i++) {
            IPresale.PresalePhaseConfig memory phase = presaleImpl.getPhaseInfo(i);
            console.log("\nPhase", i, ":");
            console.log("  Start Time:", phase.startTime);
            console.log("  End Time:", phase.endTime);
            console.log("  Total Phase Cap:", phase.totalPhaseCap);
            console.log("  User Allocation Cap:", phase.userAllocationCap);
            console.log("  Has Whitelist:", phase.merkleRoot != bytes32(0));
        }

        console.log("\n=== BFactory Parameters ===");
        IPresale.BFactoryParams memory storedParams = presaleImpl.getBFactoryParams();
        console.log("Initial Pool BTokens:", storedParams.initialPoolBTokens);
        console.log("Creator:", storedParams.creator);
        console.log("Creator Fee Pct:", storedParams.creatorFeePct);

        console.log("\n=== Next Steps ===");
        console.log("1. Users can deposit ERC20 tokens during active phases");
        console.log("2. Admin finalizes with: finalizeSale(...)");
        console.log("3. Or admin can cancel with: cancelSale()");

        console.log("\n=== Verification Command ===");
        console.log("forge verify-contract", presale, "src/PresaleImplementation.sol:PresaleImplementation --via-ir");
    }
}
