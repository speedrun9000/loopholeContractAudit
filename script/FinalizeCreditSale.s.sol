// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PresaleImplementation} from "../src/PresaleImplementation.sol";
import {IPresale} from "../src/interfaces/IPresale.sol";

/**
 * @title FinalizeCreditSale
 * @notice Automated credit sale finalization with batched credit claims.
 *
 * Reads a single positions file, automatically splits into batches, and runs all
 * three steps (createPool -> claimCreditBatch x N -> completeFinalization).
 * Resumes from where it left off if re-run after a partial failure.
 *
 * Usage:
 *   forge script FinalizeCreditSale --sig "run(string)" path/to/positions.json --broadcast
 *
 * Required env vars:
 *   PRIVATE_KEY              - Admin private key
 *   PRESALE_ADDRESS          - Deployed presale proxy address
 *   BATCH_SIZE               - Max users per claimCreditBatch tx (e.g. 50)
 *
 * Required env vars (only if pool not yet created):
 *   TOKEN_NAME, TOKEN_SYMBOL, INITIAL_ACTIVE_PRICE, INITIAL_COLLATERAL, INITIAL_DEBT,
 *   CLAIM_MERKLE_ROOT, ACQUISITION_TREASURY, BPS_TO_TREASURY, FEE_ROUTER, BASELINE,
 *   SALT, CIRCULATING_SUPPLY_RECIPIENT
 *
 * Positions file format (JSON):
 *   {
 *     "users": ["0x...", "0x...", ...],
 *     "collaterals": [1000000000000000000, ...],
 *     "debts": [100000000000000000, ...],
 *     "proofs": [["0x...", "0x..."], ["0x..."], ...]
 *   }
 *
 * Progress tracking:
 *   Writes a progress file at <positionsPath>.progress containing the index of
 *   the next user to claim. On re-run, skips already-claimed batches.
 *   Delete the progress file to restart from scratch.
 */
contract FinalizeCreditSale is Script {
    function run(string calldata positionsPath) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        PresaleImplementation presale = PresaleImplementation(payable(vm.envAddress("PRESALE_ADDRESS")));
        uint256 batchSize = vm.envUint("BATCH_SIZE");

        require(!presale.isCancelled(), "Presale is cancelled");
        require(!presale.isFinalized(), "Presale already finalized");
        require(presale.getSaleType() == IPresale.SaleType.Credit, "Not a credit sale");
        require(batchSize > 0, "BATCH_SIZE must be > 0");

        // --- Step 1: Create pool if needed ---
        if (!presale.poolCreated()) {
            console.log("=== Step 1: Create Pool ===");
            console.log("Presale:", address(presale));
            console.log("Total Raised:", presale.getTotalRaised());

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
                circulatingSupplyRecipient: vm.envAddress("CIRCULATING_SUPPLY_RECIPIENT")
            });

            vm.broadcast(deployerPrivateKey);
            presale.finalizeSale(params);

            console.log("Pool created. bToken:", presale.getCreatedToken());
            console.log("Pool ID:", vm.toString(presale.getCreatedPool()));
        } else {
            console.log("=== Pool already created, resuming claims ===");
            console.log("bToken:", presale.getCreatedToken());
        }

        // --- Step 2: Parse positions and batch claim ---
        string memory json = vm.readFile(positionsPath);

        address[] memory allUsers = abi.decode(vm.parseJson(json, ".users"), (address[]));
        uint128[] memory allCollaterals = abi.decode(vm.parseJson(json, ".collaterals"), (uint128[]));
        uint128[] memory allDebts = abi.decode(vm.parseJson(json, ".debts"), (uint128[]));
        bytes32[][] memory allProofs = abi.decode(vm.parseJson(json, ".proofs"), (bytes32[][]));

        uint256 totalUsers = allUsers.length;
        require(allCollaterals.length == totalUsers, "collaterals length mismatch");
        require(allDebts.length == totalUsers, "debts length mismatch");
        require(allProofs.length == totalUsers, "proofs length mismatch");

        // Read progress (index of next user to process)
        string memory progressPath = string.concat(positionsPath, ".progress");
        uint256 startIndex = _readProgress(progressPath);

        if (startIndex >= totalUsers) {
            console.log("All", totalUsers, "positions already claimed.");
        } else {
            console.log("\n=== Step 2: Claim Credit Batches ===");
            console.log("Total positions:", totalUsers);
            console.log("Already claimed:", startIndex);
            console.log("Remaining:", totalUsers - startIndex);
            console.log("Batch size:", batchSize);

            uint256 batchCount = 0;
            for (uint256 i = startIndex; i < totalUsers; i += batchSize) {
                uint256 end = i + batchSize;
                if (end > totalUsers) end = totalUsers;
                uint256 size = end - i;

                // Build batch arrays
                address[] memory batchUsers = new address[](size);
                uint128[] memory batchCollaterals = new uint128[](size);
                uint128[] memory batchDebts = new uint128[](size);
                bytes32[][] memory batchProofs = new bytes32[][](size);

                for (uint256 j = 0; j < size; j++) {
                    batchUsers[j] = allUsers[i + j];
                    batchCollaterals[j] = allCollaterals[i + j];
                    batchDebts[j] = allDebts[i + j];
                    batchProofs[j] = allProofs[i + j];
                }

                console.log("  Batch %d: users %d to %d", batchCount, i, end - 1);

                vm.broadcast(deployerPrivateKey);
                presale.claimCreditBatch(batchUsers, batchCollaterals, batchDebts, batchProofs);

                // Write progress after each successful batch
                _writeProgress(progressPath, end);
                batchCount++;
            }

            console.log("Claimed", batchCount, "batches.");
        }

        // --- Step 3: Complete finalization ---
        console.log("\n=== Step 3: Complete Finalization ===");

        vm.broadcast(deployerPrivateKey);
        presale.completeFinalization();

        require(presale.isFinalized(), "Finalization failed");

        // Clean up progress file
        _writeProgress(progressPath, totalUsers);

        console.log("Presale fully finalized.");
        console.log("bToken:", presale.getCreatedToken());
        console.log("Total positions claimed:", totalUsers);
    }

    /// @dev Read the progress index from file. Returns 0 if file doesn't exist or is empty.
    function _readProgress(string memory path) internal view returns (uint256) {
        try vm.readFile(path) returns (string memory content) {
            if (bytes(content).length == 0) return 0;
            return vm.parseUint(vm.trim(content));
        } catch {
            return 0;
        }
    }

    /// @dev Write the progress index to file.
    function _writeProgress(string memory path, uint256 index) internal {
        vm.writeFile(path, vm.toString(index));
    }
}
