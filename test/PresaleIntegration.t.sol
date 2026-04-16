// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {PresaleFactory} from "../src/PresaleFactory.sol";
import {PresaleImplementation} from "../src/PresaleImplementation.sol";
import {IPresale} from "../src/interfaces/IPresale.sol";
import {MockBFactory} from "./mocks/MockBFactory.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Merkle} from "murky/Merkle.sol";

contract PresaleIntegrationTest is Test {
    PresaleFactory public factory;
    PresaleImplementation public implementation;
    MockBFactory public bFactory;
    UpgradeableBeacon public beacon;
    Merkle public merkle;
    MockERC20 public presaleToken;

    address public admin = address(0x3);

    function setUp() public {
        bFactory = new MockBFactory();
        implementation = new PresaleImplementation();
        beacon = new UpgradeableBeacon(address(implementation), admin);
        PresaleFactory factoryImpl = new PresaleFactory();
        ERC1967Proxy factoryProxy = new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeCall(factoryImpl.initialize, (beacon, bFactory, admin))
        );
        factory = PresaleFactory(address(factoryProxy));
        merkle = new Merkle();
        presaleToken = new MockERC20("Presale Token", "PRESALE", 18);
    }

    function _hashLeaf(address account) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(account));
    }

    function _createMerkleRoot(address[] memory accounts) internal view returns (bytes32) {
        bytes32[] memory leaves = new bytes32[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            leaves[i] = _hashLeaf(accounts[i]);
        }
        return merkle.getRoot(leaves);
    }

    function _getProof(address[] memory accounts, uint256 index) internal view returns (bytes32[] memory) {
        bytes32[] memory leaves = new bytes32[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            leaves[i] = _hashLeaf(accounts[i]);
        }
        return merkle.getProof(leaves, index);
    }

    function _defaultFinalizeParams() internal pure returns (IPresale.FinalizeParams memory) {
        return IPresale.FinalizeParams({
            name: "Test Token",
            symbol: "TEST",
            initialActivePrice: 1 ether,
            initialBlvPrice: 1 ether,
            claimMerkleRoot: bytes32(0),
            initialCollateral: 0,
            initialDebt: 0,
            acquisitionTreasury: address(0),
            bpsToTreasury: 0,
            feeRouter: address(0),
            baseline: address(0),
            salt: bytes32(0),
            circulatingSupplyRecipient: address(0)
        });
    }

    function test_EndToEnd_SuccessfulPresale() public {
        // Create 10 users
        address[] memory users = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            users[i] = address(uint160(0x100 + i));
            presaleToken.mint(users[i], 100 ether);
            vm.prank(users[i]);
            presaleToken.approve(address(factory), type(uint256).max);
        }

        // Create whitelists for each phase
        // Phase 0: First 5 users
        address[] memory whitelist0 = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            whitelist0[i] = users[i];
        }
        bytes32 merkleRoot0 = _createMerkleRoot(whitelist0);

        // Phase 1: Users 5-9
        address[] memory whitelist1 = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            whitelist1[i] = users[i + 5];
        }
        bytes32 merkleRoot1 = _createMerkleRoot(whitelist1);

        // Phase 2: All users
        bytes32 merkleRoot2 = bytes32(0);

        // Deploy presale with 3 phases
        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](3);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp,
            endTime: block.timestamp + 2 days,
            totalPhaseCap: 50 ether,
            userAllocationCap: 5 ether,
            merkleRoot: merkleRoot0
        });
        phases[1] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp + 2 days,
            endTime: block.timestamp + 5 days,
            totalPhaseCap: 100 ether,
            userAllocationCap: 10 ether,
            merkleRoot: merkleRoot1
        });
        phases[2] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp + 5 days,
            endTime: block.timestamp + 10 days,
            totalPhaseCap: 150 ether,
            userAllocationCap: 15 ether,
            merkleRoot: merkleRoot2
        });

        IPresale.PresaleConfig memory config = IPresale.PresaleConfig({
            admin: admin,
            softCap: 100 ether,
            hardCap: 300 ether,
            saleType: IPresale.SaleType.Credit,
            circulatingSupplyBps: 500
        });

        IPresale.BFactoryParams memory bFactoryParams = IPresale.BFactoryParams({
            bToken: address(0),
            initialPoolBTokens: 1000000 ether,
            creator: admin,
            creatorFeePct: 100,
            createHook: false,
            claimMerkleRoot: bytes32(0),
            initialCollateral: 0,
            initialDebt: 0,
            initialBLV: 0,
            swapFeePct: 0.01 ether
        });

        vm.prank(admin);
        address presaleAddr = factory.deployPresale(phases, config, bFactoryParams, address(presaleToken));
        PresaleImplementation presale = PresaleImplementation(payable(presaleAddr));

        // Approve presale contract for all users
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(users[i]);
            presaleToken.approve(address(presale), type(uint256).max);
        }

        // Phase 0: First 5 users deposit with proofs
        for (uint256 i = 0; i < 5; i++) {
            bytes32[] memory proof = _getProof(whitelist0, i);
            vm.prank(users[i]);
            presale.deposit(0, 5 ether, proof);
        }
        assertEq(presale.getTotalRaised(), 25 ether);

        // Warp to phase 1
        vm.warp(block.timestamp + 2 days);

        // Phase 1: Next 5 users deposit with proofs, some make multiple deposits
        for (uint256 i = 5; i < 10; i++) {
            bytes32[] memory proof = _getProof(whitelist1, i - 5);

            vm.prank(users[i]);
            presale.deposit(1, 6 ether, proof);

            vm.prank(users[i]);
            presale.deposit(1, 4 ether, proof);
        }
        assertEq(presale.getTotalRaised(), 75 ether);

        // Warp to phase 2
        vm.warp(block.timestamp + 3 days);

        // Phase 2: All users deposit more with empty proof
        for (uint256 i = 0; i < 10; i++) {
            bytes32[] memory proof = new bytes32[](0);
            vm.prank(users[i]);
            presale.deposit(2, 10 ether, proof);
        }
        assertEq(presale.getTotalRaised(), 175 ether);

        // Verify user deposits across phases
        assertEq(presale.getUserDepositedAmount(users[0], 0), 5 ether);
        assertEq(presale.getUserDepositedAmount(users[0], 1), 0 ether);
        assertEq(presale.getUserDepositedAmount(users[0], 2), 10 ether);

        assertEq(presale.getUserDepositedAmount(users[5], 0), 0 ether);
        assertEq(presale.getUserDepositedAmount(users[5], 1), 10 ether);
        assertEq(presale.getUserDepositedAmount(users[5], 2), 10 ether);

        // Finalize presale (credit path: creates pool, enters intermediate state)
        vm.prank(admin);
        presale.finalizeSale(_defaultFinalizeParams());

        // Verify intermediate state
        assertTrue(presale.poolCreated(), "pool should be created");
        assertFalse(presale.isFinalized(), "should not be finalized yet (credit sale)");
        assertTrue(presale.getCreatedToken() != address(0), "bToken should exist");
        assertTrue(presale.getCreatedPool() != bytes32(0), "poolId should exist");

        // Credit sale: complete finalization
        vm.prank(admin);
        presale.completeFinalization();

        // Verify fully finalized
        assertTrue(presale.isFinalized());
    }

    function test_EndToEnd_FailedPresale_Refunds() public {
        // Create 3 users
        address[] memory users = new address[](3);
        for (uint256 i = 0; i < 3; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            users[i] = address(uint160(0x100 + i));
            presaleToken.mint(users[i], 100 ether);
            vm.prank(users[i]);
            presaleToken.approve(address(factory), type(uint256).max);
        }

        // Create whitelist for all users
        bytes32 merkleRoot = _createMerkleRoot(users);

        // Deploy presale
        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](2);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp,
            endTime: block.timestamp + 7 days,
            totalPhaseCap: 50 ether,
            userAllocationCap: 20 ether,
            merkleRoot: merkleRoot
        });
        phases[1] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp + 7 days,
            endTime: block.timestamp + 14 days,
            totalPhaseCap: 50 ether,
            userAllocationCap: 20 ether,
            merkleRoot: merkleRoot
        });

        IPresale.PresaleConfig memory config = IPresale.PresaleConfig({
            admin: admin,
            softCap: 100 ether,
            hardCap: 100 ether,
            saleType: IPresale.SaleType.Credit,
            circulatingSupplyBps: 500
        });

        IPresale.BFactoryParams memory bFactoryParams = IPresale.BFactoryParams({
            bToken: address(0),
            initialPoolBTokens: 1000000 ether,
            creator: admin,
            creatorFeePct: 100,
            createHook: false,
            claimMerkleRoot: bytes32(0),
            initialCollateral: 0,
            initialDebt: 0,
            initialBLV: 0,
            swapFeePct: 0.01 ether
        });

        vm.prank(admin);
        address presaleAddr = factory.deployPresale(phases, config, bFactoryParams, address(presaleToken));
        PresaleImplementation presale = PresaleImplementation(payable(presaleAddr));

        // Approve presale contract for all users
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(users[i]);
            presaleToken.approve(address(presale), type(uint256).max);
        }

        // Users deposit in phase 0 with proofs
        uint256[] memory deposits = new uint256[](3);
        deposits[0] = 15 ether;
        deposits[1] = 10 ether;
        deposits[2] = 8 ether;

        for (uint256 i = 0; i < 3; i++) {
            bytes32[] memory proof = _getProof(users, i);
            vm.prank(users[i]);
            presale.deposit(0, deposits[i], proof);
        }

        assertEq(presale.getTotalRaised(), 33 ether);

        // Warp past all phases
        vm.warp(block.timestamp + 15 days);
        assertTrue(presale.allPhasesEnded());

        // user0 cancels presale (didn't reach soft cap)
        vm.prank(users[0]);
        presale.cancelSale();

        // Users claim refunds
        uint256[] memory balancesBefore = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            balancesBefore[i] = presaleToken.balanceOf(users[i]);
        }

        for (uint256 i = 0; i < 3; i++) {
            vm.prank(users[i]);
            presale.refund(0);
        }

        // Verify refunds
        for (uint256 i = 0; i < 3; i++) {
            assertEq(presaleToken.balanceOf(users[i]), balancesBefore[i] + deposits[i]);
        }
    }

    function test_EndToEnd_MultiPhaseRefunds() public {
        // Create 5 users
        address[] memory users = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            users[i] = address(uint160(0x200 + i));
            presaleToken.mint(users[i], 100 ether);
            vm.prank(users[i]);
            presaleToken.approve(address(factory), type(uint256).max);
        }

        // Create whitelists for each phase
        bytes32 merkleRoot0 = _createMerkleRoot(users);

        address[] memory whitelist1 = new address[](3);
        for (uint256 i = 0; i < 3; i++) {
            whitelist1[i] = users[i];
        }
        bytes32 merkleRoot1 = _createMerkleRoot(whitelist1);

        address[] memory whitelist2 = new address[](3);
        for (uint256 i = 0; i < 3; i++) {
            whitelist2[i] = users[i + 2];
        }
        bytes32 merkleRoot2 = _createMerkleRoot(whitelist2);

        // Deploy presale with 3 phases
        uint256 startTime = block.timestamp;
        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](3);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: startTime,
            endTime: startTime + 3 days,
            totalPhaseCap: 50 ether,
            userAllocationCap: 10 ether,
            merkleRoot: merkleRoot0
        });
        phases[1] = IPresale.PresalePhaseConfig({
            startTime: startTime + 3 days,
            endTime: startTime + 6 days,
            totalPhaseCap: 50 ether,
            userAllocationCap: 15 ether,
            merkleRoot: merkleRoot1
        });
        phases[2] = IPresale.PresalePhaseConfig({
            startTime: startTime + 6 days,
            endTime: startTime + 10 days,
            totalPhaseCap: 100 ether,
            userAllocationCap: 20 ether,
            merkleRoot: merkleRoot2
        });

        IPresale.PresaleConfig memory config = IPresale.PresaleConfig({
            admin: admin,
            softCap: 150 ether,
            hardCap: 200 ether,
            saleType: IPresale.SaleType.Credit,
            circulatingSupplyBps: 500
        });

        IPresale.BFactoryParams memory bFactoryParams = IPresale.BFactoryParams({
            bToken: address(0),
            initialPoolBTokens: 1000000 ether,
            creator: admin,
            creatorFeePct: 100,
            createHook: false,
            claimMerkleRoot: bytes32(0),
            initialCollateral: 0,
            initialDebt: 0,
            initialBLV: 0,
            swapFeePct: 0.01 ether
        });

        vm.prank(admin);
        address presaleAddr = factory.deployPresale(phases, config, bFactoryParams, address(presaleToken));
        PresaleImplementation presale = PresaleImplementation(payable(presaleAddr));

        // Approve presale contract for all users
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(users[i]);
            presaleToken.approve(address(presale), type(uint256).max);
        }

        // Track deposits per user per phase
        uint256[5][3] memory userPhaseDeposits;

        // Phase 0: All users deposit different amounts
        userPhaseDeposits[0][0] = 8 ether;
        userPhaseDeposits[0][1] = 6 ether;
        userPhaseDeposits[0][2] = 7 ether;
        userPhaseDeposits[0][3] = 5 ether;
        userPhaseDeposits[0][4] = 9 ether;

        for (uint256 i = 0; i < 5; i++) {
            if (userPhaseDeposits[0][i] > 0) {
                bytes32[] memory proof = _getProof(users, i);
                vm.prank(users[i]);
                presale.deposit(0, userPhaseDeposits[0][i], proof);
            }
        }
        assertEq(presale.getTotalRaised(), 35 ether);

        // Warp to phase 1
        vm.warp(startTime + 3 days);

        // Phase 1: Users 0-2 deposit (multiple deposits for some)
        userPhaseDeposits[1][0] = 12 ether;
        userPhaseDeposits[1][1] = 8 ether;
        userPhaseDeposits[1][2] = 10 ether;

        for (uint256 i = 0; i < 3; i++) {
            bytes32[] memory proof = _getProof(whitelist1, i);
            vm.prank(users[i]);
            presale.deposit(1, userPhaseDeposits[1][i] / 2, proof);
            vm.prank(users[i]);
            presale.deposit(1, userPhaseDeposits[1][i] / 2, proof);
        }
        assertEq(presale.getTotalRaised(), 65 ether);

        // Warp to phase 2
        vm.warp(startTime + 6 days);

        // Phase 2: Users 2-4 start depositing
        userPhaseDeposits[2][2] = 15 ether;
        userPhaseDeposits[2][3] = 12 ether;

        for (uint256 i = 2; i < 4; i++) {
            bytes32[] memory proof = _getProof(whitelist2, i - 2);
            vm.prank(users[i]);
            presale.deposit(2, userPhaseDeposits[2][i], proof);
        }
        assertEq(presale.getTotalRaised(), 92 ether);

        // Warp past all phases
        vm.warp(startTime + 11 days);
        assertTrue(presale.allPhasesEnded());

        // user0 cancels presale (didn't reach soft cap of 150 ether)
        vm.prank(users[0]);
        presale.cancelSale();
        assertTrue(presale.isCancelled());

        // Record balances before refunds
        uint256[5] memory balancesBefore;
        for (uint256 i = 0; i < 5; i++) {
            balancesBefore[i] = presaleToken.balanceOf(users[i]);
        }

        // Users claim refunds for all phases they participated in
        vm.prank(users[0]);
        presale.refund(0);
        vm.prank(users[0]);
        presale.refund(1);
        assertEq(
            presaleToken.balanceOf(users[0]), balancesBefore[0] + userPhaseDeposits[0][0] + userPhaseDeposits[1][0]
        );

        vm.prank(users[1]);
        presale.refund(0);
        vm.prank(users[1]);
        presale.refund(1);
        assertEq(
            presaleToken.balanceOf(users[1]), balancesBefore[1] + userPhaseDeposits[0][1] + userPhaseDeposits[1][1]
        );

        vm.prank(users[2]);
        presale.refund(0);
        vm.prank(users[2]);
        presale.refund(1);
        vm.prank(users[2]);
        presale.refund(2);
        assertEq(
            presaleToken.balanceOf(users[2]),
            balancesBefore[2] + userPhaseDeposits[0][2] + userPhaseDeposits[1][2] + userPhaseDeposits[2][2]
        );

        vm.prank(users[3]);
        presale.refund(0);
        vm.prank(users[3]);
        presale.refund(2);
        assertEq(
            presaleToken.balanceOf(users[3]), balancesBefore[3] + userPhaseDeposits[0][3] + userPhaseDeposits[2][3]
        );

        vm.prank(users[4]);
        presale.refund(0);
        assertEq(presaleToken.balanceOf(users[4]), balancesBefore[4] + userPhaseDeposits[0][4]);

        // Test double-claim prevention
        vm.prank(users[0]);
        vm.expectRevert(IPresale.NoRefundAvailable.selector);
        presale.refund(0);

        // Test non-depositor claim
        vm.prank(users[4]);
        vm.expectRevert(IPresale.NoRefundAvailable.selector);
        presale.refund(1);

        // Verify presale still has 0 balance
        assertEq(presaleToken.balanceOf(address(presale)), 0);
    }

    function test_UpgradeAndDeploy() public {
        address[] memory whitelist = new address[](3);
        whitelist[0] = address(0x100);
        whitelist[1] = address(0x101);
        whitelist[2] = address(0x102);
        bytes32 merkleRoot = _createMerkleRoot(whitelist);

        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](1);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp,
            endTime: block.timestamp + 7 days,
            totalPhaseCap: 100 ether,
            userAllocationCap: 10 ether,
            merkleRoot: merkleRoot
        });

        IPresale.PresaleConfig memory config = IPresale.PresaleConfig({
            admin: admin,
            softCap: 50 ether,
            hardCap: 100 ether,
            saleType: IPresale.SaleType.Credit,
            circulatingSupplyBps: 500
        });

        IPresale.BFactoryParams memory bFactoryParams = IPresale.BFactoryParams({
            bToken: address(0),
            initialPoolBTokens: 1000000 ether,
            creator: admin,
            creatorFeePct: 100,
            createHook: false,
            claimMerkleRoot: bytes32(0),
            initialCollateral: 0,
            initialDebt: 0,
            initialBLV: 0,
            swapFeePct: 0.01 ether
        });

        vm.prank(admin);
        address presale1 = factory.deployPresale(phases, config, bFactoryParams, address(presaleToken));

        // Upgrade implementation
        PresaleImplementation newImplementation = new PresaleImplementation();
        vm.prank(admin);
        beacon.upgradeTo(address(newImplementation));

        // Deploy new presale with upgraded implementation
        vm.prank(admin);
        address presale2 = factory.deployPresale(phases, config, bFactoryParams, address(presaleToken));

        assertTrue(presale1 != presale2);
        assertEq(factory.getImplementation(), address(newImplementation));
    }

    function test_PermissionlessCancelAfterPhasesEnd() public {
        address[] memory users = new address[](3);
        for (uint256 i = 0; i < 3; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            users[i] = address(uint160(0x300 + i));
            presaleToken.mint(users[i], 100 ether);
            vm.prank(users[i]);
            presaleToken.approve(address(factory), type(uint256).max);
        }

        bytes32 merkleRoot = _createMerkleRoot(users);

        uint256 startTime = block.timestamp;
        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](2);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: startTime,
            endTime: startTime + 3 days,
            totalPhaseCap: 50 ether,
            userAllocationCap: 20 ether,
            merkleRoot: merkleRoot
        });
        phases[1] = IPresale.PresalePhaseConfig({
            startTime: startTime + 3 days,
            endTime: startTime + 7 days,
            totalPhaseCap: 50 ether,
            userAllocationCap: 20 ether,
            merkleRoot: merkleRoot
        });

        IPresale.PresaleConfig memory config = IPresale.PresaleConfig({
            admin: admin,
            softCap: 100 ether,
            hardCap: 100 ether,
            saleType: IPresale.SaleType.Credit,
            circulatingSupplyBps: 500
        });

        IPresale.BFactoryParams memory bFactoryParams = IPresale.BFactoryParams({
            bToken: address(0),
            initialPoolBTokens: 1000000 ether,
            creator: admin,
            creatorFeePct: 100,
            createHook: false,
            claimMerkleRoot: bytes32(0),
            initialCollateral: 0,
            initialDebt: 0,
            initialBLV: 0,
            swapFeePct: 0.01 ether
        });

        vm.prank(admin);
        address presaleAddr = factory.deployPresale(phases, config, bFactoryParams, address(presaleToken));
        PresaleImplementation presale = PresaleImplementation(payable(presaleAddr));

        for (uint256 i = 0; i < 3; i++) {
            vm.prank(users[i]);
            presaleToken.approve(address(presale), type(uint256).max);
        }

        // Users deposit (only 30 ether, under soft cap of 100)
        bytes32[] memory proof = _getProof(users, 0);
        vm.prank(users[0]);
        presale.deposit(0, 15 ether, proof);

        proof = _getProof(users, 1);
        vm.prank(users[1]);
        presale.deposit(0, 10 ether, proof);

        proof = _getProof(users, 2);
        vm.prank(users[2]);
        presale.deposit(0, 5 ether, proof);

        assertEq(presale.getTotalRaised(), 30 ether);

        // Try to cancel before phases end
        vm.prank(users[0]);
        vm.expectRevert(IPresale.Unauthorized.selector);
        presale.cancelSale();

        // Warp during last phase
        vm.warp(startTime + 6 days);
        vm.prank(users[1]);
        vm.expectRevert(IPresale.Unauthorized.selector);
        presale.cancelSale();

        // Warp past all phases
        vm.warp(startTime + 8 days);
        assertTrue(presale.allPhasesEnded());

        // Now anyone can cancel
        vm.prank(users[0]);
        presale.cancelSale();
        assertTrue(presale.isCancelled());

        // Users can claim refunds
        vm.prank(users[0]);
        presale.refund(0);
        assertEq(presaleToken.balanceOf(users[0]), 100 ether);

        vm.prank(users[1]);
        presale.refund(0);
        assertEq(presaleToken.balanceOf(users[1]), 100 ether);

        vm.prank(users[2]);
        presale.refund(0);
        assertEq(presaleToken.balanceOf(users[2]), 100 ether);
    }

    function test_PermissionlessCancel_FailsIfSoftCapMet() public {
        address[] memory users = new address[](3);
        for (uint256 i = 0; i < 3; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            users[i] = address(uint160(0x400 + i));
            presaleToken.mint(users[i], 100 ether);
        }

        bytes32 merkleRoot = _createMerkleRoot(users);

        uint256 startTime = block.timestamp;
        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](1);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: startTime,
            endTime: startTime + 3 days,
            totalPhaseCap: 150 ether,
            userAllocationCap: 50 ether,
            merkleRoot: merkleRoot
        });

        IPresale.PresaleConfig memory config = IPresale.PresaleConfig({
            admin: admin,
            softCap: 100 ether,
            hardCap: 150 ether,
            saleType: IPresale.SaleType.Credit,
            circulatingSupplyBps: 500
        });

        IPresale.BFactoryParams memory bFactoryParams = IPresale.BFactoryParams({
            bToken: address(0),
            initialPoolBTokens: 1000000 ether,
            creator: admin,
            creatorFeePct: 100,
            createHook: false,
            claimMerkleRoot: bytes32(0),
            initialCollateral: 0,
            initialDebt: 0,
            initialBLV: 0,
            swapFeePct: 0.01 ether
        });

        vm.prank(admin);
        address presaleAddr = factory.deployPresale(phases, config, bFactoryParams, address(presaleToken));
        PresaleImplementation presale = PresaleImplementation(payable(presaleAddr));

        for (uint256 i = 0; i < 3; i++) {
            vm.prank(users[i]);
            presaleToken.approve(address(presale), type(uint256).max);
        }

        bytes32[] memory proof = _getProof(users, 0);
        vm.prank(users[0]);
        presale.deposit(0, 50 ether, proof);

        proof = _getProof(users, 1);
        vm.prank(users[1]);
        presale.deposit(0, 50 ether, proof);

        assertEq(presale.getTotalRaised(), 100 ether);

        // Warp past all phases
        vm.warp(startTime + 4 days);
        assertTrue(presale.allPhasesEnded());

        // Non-admin can't cancel if soft cap met
        vm.prank(users[0]);
        vm.expectRevert(IPresale.Unauthorized.selector);
        presale.cancelSale();

        // Admin can still cancel
        vm.prank(admin);
        presale.cancelSale();
        assertTrue(presale.isCancelled());
    }

    function test_MultiplePresales_Independent() public {
        address user = address(0x999);

        address[] memory whitelist1 = new address[](2);
        whitelist1[0] = user;
        whitelist1[1] = address(0x888);
        bytes32 merkleRoot1 = _createMerkleRoot(whitelist1);

        address[] memory whitelist2Phase0 = new address[](3);
        whitelist2Phase0[0] = user;
        whitelist2Phase0[1] = address(0x777);
        whitelist2Phase0[2] = address(0x666);
        bytes32 merkleRoot2Phase0 = _createMerkleRoot(whitelist2Phase0);

        address[] memory whitelist2Phase1 = new address[](2);
        whitelist2Phase1[0] = user;
        whitelist2Phase1[1] = address(0x555);
        bytes32 merkleRoot2Phase1 = _createMerkleRoot(whitelist2Phase1);

        IPresale.PresalePhaseConfig[] memory phases1 = new IPresale.PresalePhaseConfig[](1);
        phases1[0] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp,
            endTime: block.timestamp + 7 days,
            totalPhaseCap: 50 ether,
            userAllocationCap: 5 ether,
            merkleRoot: merkleRoot1
        });

        IPresale.PresalePhaseConfig[] memory phases2 = new IPresale.PresalePhaseConfig[](2);
        phases2[0] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp,
            endTime: block.timestamp + 3 days,
            totalPhaseCap: 30 ether,
            userAllocationCap: 3 ether,
            merkleRoot: merkleRoot2Phase0
        });
        phases2[1] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp + 3 days,
            endTime: block.timestamp + 7 days,
            totalPhaseCap: 70 ether,
            userAllocationCap: 7 ether,
            merkleRoot: merkleRoot2Phase1
        });

        IPresale.PresaleConfig memory config1 = IPresale.PresaleConfig({
            admin: admin,
            softCap: 25 ether,
            hardCap: 50 ether,
            saleType: IPresale.SaleType.Credit,
            circulatingSupplyBps: 500
        });

        IPresale.PresaleConfig memory config2 = IPresale.PresaleConfig({
            admin: admin,
            softCap: 50 ether,
            hardCap: 100 ether,
            saleType: IPresale.SaleType.Credit,
            circulatingSupplyBps: 500
        });

        IPresale.BFactoryParams memory bFactoryParams = IPresale.BFactoryParams({
            bToken: address(0),
            initialPoolBTokens: 1000000 ether,
            creator: admin,
            creatorFeePct: 100,
            createHook: false,
            claimMerkleRoot: bytes32(0),
            initialCollateral: 0,
            initialDebt: 0,
            initialBLV: 0,
            swapFeePct: 0.01 ether
        });

        vm.startPrank(admin);
        address presale1Addr = factory.deployPresale(phases1, config1, bFactoryParams, address(presaleToken));
        address presale2Addr = factory.deployPresale(phases2, config2, bFactoryParams, address(presaleToken));
        vm.stopPrank();

        PresaleImplementation presale1 = PresaleImplementation(payable(presale1Addr));
        PresaleImplementation presale2 = PresaleImplementation(payable(presale2Addr));

        presaleToken.mint(user, 100 ether);
        vm.prank(user);
        presaleToken.approve(address(presale1), type(uint256).max);
        vm.prank(user);
        presaleToken.approve(address(presale2), type(uint256).max);

        bytes32[] memory proof1 = _getProof(whitelist1, 0);
        vm.prank(user);
        presale1.deposit(0, 5 ether, proof1);

        bytes32[] memory proof2 = _getProof(whitelist2Phase0, 0);
        vm.prank(user);
        presale2.deposit(0, 3 ether, proof2);

        assertEq(presale1.getTotalRaised(), 5 ether);
        assertEq(presale2.getTotalRaised(), 3 ether);
        assertEq(presale1.getPhaseCount(), 1);
        assertEq(presale2.getPhaseCount(), 2);
    }
}
