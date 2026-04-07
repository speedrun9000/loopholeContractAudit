// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PresaleFactory} from "../src/PresaleFactory.sol";
import {PresaleImplementation} from "../src/PresaleImplementation.sol";
import {IPresale} from "../src/interfaces/IPresale.sol";
import {Addresses} from "./Addresses.sol";

interface ITestWETH {
    function mint(address user, uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title TestLoopE2E
 * @notice End-to-end test script for a LOOP spot sale on Base Sepolia.
 *         Deploys a presale, funds users from mnemonic, deposits, finalizes, and claims.
 *
 * Required env vars:
 *   PRIVATE_KEY         - admin private key (deploys presale, finalizes)
 *   MNEMONIC            - HD wallet mnemonic for test users (indices 0-2)
 *   RPC_URL             - Base Sepolia RPC
 *
 * Prerequisites:
 *   - Admin must have ETH on Base Sepolia
 *   - Factory must be approved on Baseline (setApprovedCreditDeployer)
 */
contract TestLoopE2E is Script {
    ITestWETH constant weth = ITestWETH(Addresses.BASELINE_WETH);
    PresaleFactory constant factory = PresaleFactory(Addresses.FACTORY_PROXY);

    uint256 constant NUM_USERS = 3;
    uint256 constant DEPOSIT_AMOUNT = 1 ether;
    uint256 constant GAS_FUND = 0.001 ether;

    function run() external {
        uint256 adminKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(adminKey);
        string memory mnemonic = vm.envString("MNEMONIC");

        // Derive user keys from mnemonic
        uint256[] memory userKeys = new uint256[](NUM_USERS);
        address[] memory users = new address[](NUM_USERS);
        for (uint256 i = 0; i < NUM_USERS; i++) {
            userKeys[i] = vm.deriveKey(mnemonic, uint32(i));
            users[i] = vm.addr(userKeys[i]);
        }

        console.log("=== Accounts ===");
        console.log("Admin:", admin);
        for (uint256 i = 0; i < NUM_USERS; i++) {
            console.log("User", i + 1, ":", users[i]);
        }

        // ── Step 1: Fund users with ETH and wrap to WETH ────────────
        console.log("\n=== Step 1: Fund users and wrap ETH ===");
        for (uint256 i = 0; i < NUM_USERS; i++) {
            // Admin sends ETH for gas and mints test WETH to user
            vm.broadcast(adminKey);
            (bool sent,) = users[i].call{value: GAS_FUND}("");
            require(sent, "ETH transfer failed");

            vm.broadcast(adminKey);
            weth.mint(users[i], DEPOSIT_AMOUNT);
            console.log("User", i + 1, "WETH balance:", weth.balanceOf(users[i]));
        }

        // ── Step 2: Deploy spot presale ──────────────────────────────
        console.log("\n=== Step 2: Deploy spot presale ===");

        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](1);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp,
            endTime: block.timestamp + 7 days,
            totalPhaseCap: 10 ether,
            userAllocationCap: 2 ether,
            merkleRoot: bytes32(0)
        });

        IPresale.PresaleConfig memory config = IPresale.PresaleConfig({
            admin: admin,
            softCap: 0.5 ether,
            hardCap: 10 ether,
            saleType: IPresale.SaleType.Spot,
            circulatingSupplyBps: 500
        });

        IPresale.BFactoryParams memory bFactoryParams = IPresale.BFactoryParams({
            bToken: address(0),
            initialPoolBTokens: 1_000_000 ether,
            creator: admin,
            creatorFeePct: 100,
            createHook: false,
            claimMerkleRoot: bytes32(0),
            initialCollateral: 0,
            initialDebt: 0
        });

        vm.broadcast(adminKey);
        address presaleAddr = factory.deployPresale(phases, config, bFactoryParams, address(weth));
        PresaleImplementation presale = PresaleImplementation(payable(presaleAddr));
        console.log("Presale deployed at:", presaleAddr);

        // ── Step 3: Users deposit ────────────────────────────────────
        console.log("\n=== Step 3: Users deposit ===");
        for (uint256 i = 0; i < NUM_USERS; i++) {
            vm.broadcast(userKeys[i]);
            IERC20(address(weth)).approve(presaleAddr, DEPOSIT_AMOUNT);

            vm.broadcast(userKeys[i]);
            presale.deposit(0, DEPOSIT_AMOUNT, new bytes32[](0));
            console.log("User", i + 1, "deposited:", DEPOSIT_AMOUNT);
        }

        uint256 totalRaised = presale.getTotalRaised();
        console.log("Total raised:", totalRaised);

        // ── Step 4: Finalize ─────────────────────────────────────────
        console.log("\n=== Step 4: Finalize spot sale ===");

        uint256 initialPoolBTokens = presale.getBFactoryParams().initialPoolBTokens;
        uint256 totalSupply = (initialPoolBTokens * (10_000 + 500)) / 10_000;
        uint256 circulatingSupply = totalSupply - initialPoolBTokens;
        uint256 reserveBalance = IERC20(address(weth)).balanceOf(presaleAddr);
        uint256 bookPrice = (reserveBalance * 1e18) / circulatingSupply;
        uint256 initialActivePrice = (bookPrice * 105) / 100;

        vm.broadcast(adminKey);
        presale.finalizeSale(
            IPresale.FinalizeParams({
                name: "Loophole",
                symbol: "LOOP",
                initialActivePrice: initialActivePrice,
                initialBlvPrice: 0,
                claimMerkleRoot: bytes32(0),
                initialCollateral: 0,
                initialDebt: 0,
                acquisitionTreasury: address(0),
                bpsToTreasury: 0,
                feeRouter: Addresses.FEE_ROUTER_PROXY,
                baseline: Addresses.BASELINE,
                salt: bytes32(block.timestamp),
                circulatingSupplyRecipient: address(0)
            })
        );

        address bToken = presale.getCreatedToken();
        console.log("LOOP bToken:", bToken);
        console.log("Total claimable:", presale.getTotalClaimableTokens());

        // ── Step 5: Users claim ──────────────────────────────────────
        console.log("\n=== Step 5: Users claim spot tokens ===");
        for (uint256 i = 0; i < NUM_USERS; i++) {
            uint256 claimable = presale.getClaimableAmount(users[i]);
            console.log("User", i + 1, "claimable:", claimable);

            vm.broadcast(userKeys[i]);
            presale.claimSpot();

            uint256 balance = IERC20(bToken).balanceOf(users[i]);
            console.log("User", i + 1, "LOOP balance:", balance);
        }

        // ── Summary ──────────────────────────────────────────────────
        console.log("\n=== Summary ===");
        console.log("Presale:", presaleAddr);
        console.log("LOOP bToken:", bToken);
        console.log("Pool ID:", vm.toString(presale.getCreatedPool()));
        console.log("Total raised:", totalRaised);
        console.log("Total supply:", totalSupply);
        console.log("Circulating supply:", circulatingSupply);

        console.log("\n=== Final Balances ===");
        for (uint256 i = 0; i < NUM_USERS; i++) {
            console.log("User", i + 1, users[i]);
            console.log("  LOOP:", IERC20(bToken).balanceOf(users[i]));
            console.log("  WETH:", weth.balanceOf(users[i]));
            console.log("  ETH:", users[i].balance);
        }
    }
}
