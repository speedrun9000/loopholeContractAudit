// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PresaleImplementation} from "../src/PresaleImplementation.sol";
import {IPresale} from "../src/interfaces/IPresale.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title FinalizeSpotSale
 * @notice Finalizes a spot presale: creates token + pool, users can then call claimSpot()
 * @dev Single transaction — spot sales finalize immediately.
 *
 * Required env vars:
 *   PRIVATE_KEY              — Admin private key
 *   PRESALE_ADDRESS          — Deployed presale proxy address
 *   TOKEN_NAME               — bToken name (e.g. "Loophole Token")
 *   TOKEN_SYMBOL             — bToken symbol (e.g. "LOOP")
 *   INITIAL_ACTIVE_PRICE     — Initial active price in wei
 *   INITIAL_COLLATERAL       — bTokens locked as pool collateral (wei)
 *   INITIAL_DEBT             — Debt paired with collateral (wei)
 *   CLAIM_MERKLE_ROOT        — Merkle root for credit claims (bytes32, usually 0x0 for spot)
 *   ACQUISITION_TREASURY     — Treasury address (address(0) if no treasury split)
 *   BPS_TO_TREASURY          — Basis points of raised funds to treasury (0-10000)
 *   FEE_ROUTER               — ProjectFeeRouter address (address(0) if none)
 *   BASELINE                 — Baseline relay address (required if FEE_ROUTER is set)
 *   SALT                     — Salt for deterministic bToken creation (bytes32)
 */
contract FinalizeSpotSale is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address presaleAddress = vm.envAddress("PRESALE_ADDRESS");

        PresaleImplementation presale = PresaleImplementation(payable(presaleAddress));

        // Validate presale state
        require(!presale.isFinalized(), "Presale already finalized");
        require(!presale.isCancelled(), "Presale is cancelled");
        require(presale.getSaleType() == IPresale.SaleType.Spot, "Not a spot sale");

        uint256 totalRaised = presale.getTotalRaised();

        console.log("=== Spot Sale Finalization ===");
        console.log("Presale:", presaleAddress);
        console.log("Total Raised:", totalRaised);
        console.log("Circulating Supply Bps:", presale.circulatingSupplyBps());

        IPresale.FinalizeParams memory params = IPresale.FinalizeParams({
            name: vm.envString("TOKEN_NAME"),
            symbol: vm.envString("TOKEN_SYMBOL"),
            initialActivePrice: vm.envUint("INITIAL_ACTIVE_PRICE"),
            initialBlvPrice: 0,
            claimMerkleRoot: vm.envBytes32("CLAIM_MERKLE_ROOT"),
            initialCollateral: vm.envUint("INITIAL_COLLATERAL"),
            initialDebt: vm.envUint("INITIAL_DEBT"),
            acquisitionTreasury: vm.envAddress("ACQUISITION_TREASURY"),
            bpsToTreasury: uint16(vm.envUint("BPS_TO_TREASURY")),
            feeRouter: vm.envAddress("FEE_ROUTER"),
            baseline: vm.envAddress("BASELINE"),
            salt: vm.envBytes32("SALT"),
            circulatingSupplyRecipient: address(0) // ignored for spot sales
        });

        vm.startBroadcast(deployerPrivateKey);
        presale.finalizeSale(params);
        vm.stopBroadcast();

        // Verify
        require(presale.isFinalized(), "Finalization failed");

        address bToken = presale.getCreatedToken();
        uint256 totalClaimable = presale.getTotalClaimableTokens();

        console.log("\n=== Finalization Complete ===");
        console.log("bToken:", bToken);
        console.log("Pool ID:", vm.toString(presale.getCreatedPool()));
        console.log("Total Claimable bTokens:", totalClaimable);
        console.log("bTokens held by presale:", IERC20(bToken).balanceOf(presaleAddress));
        console.log("\nUsers can now call claimSpot() to receive their bTokens pro-rata.");
    }
}
