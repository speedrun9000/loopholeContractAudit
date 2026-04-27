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

/// @dev Mock baseline that records claimCredit calls for verification
contract MockBaseline {
    address[] public claimCreditUsers;
    uint128[] public claimCreditCollaterals;
    uint128[] public claimCreditDebts;
    uint256 public callCount;

    function setFeeRecipient(address, address) external {}

    function claimCredit(
        address,
        address[] calldata _users,
        uint128[] calldata _collaterals,
        uint128[] calldata _debts,
        bytes32[][] calldata
    ) external {
        callCount++;
        for (uint256 i; i < _users.length; i++) {
            claimCreditUsers.push(_users[i]);
            claimCreditCollaterals.push(_collaterals[i]);
            claimCreditDebts.push(_debts[i]);
        }
    }

    function getTotalClaimedUsers() external view returns (uint256) {
        return claimCreditUsers.length;
    }
}

contract PresaleCreditBatchTest is Test {
    PresaleFactory public factory;
    PresaleImplementation public implementation;
    MockBFactory public bFactory;
    UpgradeableBeacon public beacon;
    MockERC20 public presaleToken;
    MockBaseline public mockBaseline;

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
        presaleToken = new MockERC20("Reserve", "RSV", 18);
        mockBaseline = new MockBaseline();
    }

    function _deployCreditPresale() internal returns (PresaleImplementation presale) {
        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](1);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp,
            endTime: block.timestamp + 7 days,
            totalPhaseCap: 200 ether,
            userAllocationCap: 200 ether,
            merkleRoot: bytes32(0)
        });

        IPresale.PresaleConfig memory config = IPresale.PresaleConfig({
            admin: admin,
            softCap: 50 ether,
            hardCap: 200 ether,
            saleType: IPresale.SaleType.Credit,
            circulatingSupplyBps: 500
        });

        IPresale.BFactoryParams memory bfp = IPresale.BFactoryParams({
            bToken: address(0),
            initialPoolBTokens: 1_000_000 ether,
            creator: admin,
            creatorFeePct: 0.75e18,
            createHook: false,
            claimMerkleRoot: bytes32(0),
            initialCollateral: 0,
            initialDebt: 0,
            initialBLV: 0,
            swapFeePct: 0.01 ether
        });

        vm.prank(admin);
        address presaleAddr = factory.deployPresale(phases, config, bfp, address(presaleToken));
        presale = PresaleImplementation(payable(presaleAddr));

        // Fund and deposit
        address depositor = address(0x100);
        presaleToken.mint(depositor, 100 ether);
        vm.prank(depositor);
        presaleToken.approve(address(presale), 100 ether);
        vm.prank(depositor);
        presale.deposit(0, 100 ether, new bytes32[](0));
    }

    function _defaultFinalizeParams() internal view returns (IPresale.FinalizeParams memory) {
        return IPresale.FinalizeParams({
            name: "Credit Token",
            symbol: "CRED",
            initialActivePrice: 1 ether,
            initialBlvPrice: 1 ether,
            claimMerkleRoot: bytes32(0),
            initialCollateral: 0,
            initialDebt: 0,
            acquisitionTreasury: address(0),
            bpsToTreasury: 0,
            feeRouter: address(0),
            baseline: address(mockBaseline),
            salt: bytes32(0),
            circulatingSupplyRecipient: address(0)
        });
    }

    /*//////////////////////////////////////////////////////////////
                     TWO-STEP FINALIZATION
    //////////////////////////////////////////////////////////////*/

    function test_TwoStepFinalize_BasicFlow() public {
        PresaleImplementation presale = _deployCreditPresale();

        // Step 1: finalizeSale creates pool
        vm.prank(admin);
        presale.finalizeSale(_defaultFinalizeParams());

        assertTrue(presale.poolCreated());
        assertFalse(presale.isFinalized());

        // Step 2: claim credit batch
        address[] memory users = new address[](2);
        users[0] = address(0xA1);
        users[1] = address(0xA2);

        uint128[] memory collaterals = new uint128[](2);
        collaterals[0] = 500e18;
        collaterals[1] = 300e18;

        uint128[] memory debts = new uint128[](2);
        debts[0] = 50e18;
        debts[1] = 30e18;

        bytes32[][] memory proofs = new bytes32[][](2);
        proofs[0] = new bytes32[](0);
        proofs[1] = new bytes32[](0);

        vm.expectEmit(false, false, false, true);
        emit IPresale.CreditBatchClaimed(2);
        vm.prank(admin);
        presale.claimCreditBatch(users, collaterals, debts, proofs);

        assertEq(mockBaseline.getTotalClaimedUsers(), 2);

        // Step 3: complete finalization
        vm.expectEmit(false, false, false, false);
        emit IPresale.FinalizationCompleted();
        vm.prank(admin);
        presale.completeFinalization();

        assertTrue(presale.isFinalized());
    }

    function test_MultipleBatches() public {
        PresaleImplementation presale = _deployCreditPresale();

        vm.prank(admin);
        presale.finalizeSale(_defaultFinalizeParams());

        // Batch 1
        address[] memory batch1Users = new address[](2);
        batch1Users[0] = address(0xA1);
        batch1Users[1] = address(0xA2);
        uint128[] memory batch1Collaterals = new uint128[](2);
        batch1Collaterals[0] = 500e18;
        batch1Collaterals[1] = 300e18;
        uint128[] memory batch1Debts = new uint128[](2);
        batch1Debts[0] = 50e18;
        batch1Debts[1] = 30e18;
        bytes32[][] memory batch1Proofs = new bytes32[][](2);
        batch1Proofs[0] = new bytes32[](0);
        batch1Proofs[1] = new bytes32[](0);

        vm.prank(admin);
        presale.claimCreditBatch(batch1Users, batch1Collaterals, batch1Debts, batch1Proofs);

        // Batch 2
        address[] memory batch2Users = new address[](1);
        batch2Users[0] = address(0xA3);
        uint128[] memory batch2Collaterals = new uint128[](1);
        batch2Collaterals[0] = 200e18;
        uint128[] memory batch2Debts = new uint128[](1);
        batch2Debts[0] = 20e18;
        bytes32[][] memory batch2Proofs = new bytes32[][](1);
        batch2Proofs[0] = new bytes32[](0);

        vm.prank(admin);
        presale.claimCreditBatch(batch2Users, batch2Collaterals, batch2Debts, batch2Proofs);

        // Verify both batches recorded with correct data
        assertEq(mockBaseline.getTotalClaimedUsers(), 3);
        assertEq(mockBaseline.callCount(), 2);

        // Verify batch 1 data
        assertEq(mockBaseline.claimCreditUsers(0), address(0xA1));
        assertEq(mockBaseline.claimCreditUsers(1), address(0xA2));
        assertEq(mockBaseline.claimCreditCollaterals(0), 500e18);
        assertEq(mockBaseline.claimCreditCollaterals(1), 300e18);
        assertEq(mockBaseline.claimCreditDebts(0), 50e18);
        assertEq(mockBaseline.claimCreditDebts(1), 30e18);

        // Verify batch 2 data
        assertEq(mockBaseline.claimCreditUsers(2), address(0xA3));
        assertEq(mockBaseline.claimCreditCollaterals(2), 200e18);
        assertEq(mockBaseline.claimCreditDebts(2), 20e18);

        // Complete
        vm.prank(admin);
        presale.completeFinalization();
        assertTrue(presale.isFinalized());
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSITS BLOCKED DURING INTERMEDIATE STATE
    //////////////////////////////////////////////////////////////*/

    function test_DepositsBlockedAfterPoolCreated() public {
        PresaleImplementation presale = _deployCreditPresale();

        vm.prank(admin);
        presale.finalizeSale(_defaultFinalizeParams());

        // Try to deposit during intermediate state
        address newDepositor = address(0x200);
        presaleToken.mint(newDepositor, 100 ether);
        vm.prank(newDepositor);
        presaleToken.approve(address(presale), 100 ether);

        vm.prank(newDepositor);
        vm.expectRevert(IPresale.PoolAlreadyCreated.selector);
        presale.deposit(0, 50 ether, new bytes32[](0));
    }

    function test_CancelBlockedAfterPoolCreated() public {
        PresaleImplementation presale = _deployCreditPresale();

        vm.prank(admin);
        presale.finalizeSale(_defaultFinalizeParams());

        vm.prank(admin);
        vm.expectRevert(IPresale.PoolAlreadyCreated.selector);
        presale.cancelSale();
    }

    /*//////////////////////////////////////////////////////////////
                     REVERT CASES
    //////////////////////////////////////////////////////////////*/

    function test_ClaimCreditBatch_RevertsBeforePoolCreated() public {
        PresaleImplementation presale = _deployCreditPresale();

        vm.prank(admin);
        vm.expectRevert(IPresale.NotPoolCreated.selector);
        presale.claimCreditBatch(new address[](0), new uint128[](0), new uint128[](0), new bytes32[][](0));
    }

    function test_ClaimCreditBatch_RevertsAfterFinalized() public {
        PresaleImplementation presale = _deployCreditPresale();

        vm.prank(admin);
        presale.finalizeSale(_defaultFinalizeParams());
        vm.prank(admin);
        presale.completeFinalization();

        vm.prank(admin);
        vm.expectRevert(IPresale.PresaleAlreadyFinalized.selector);
        presale.claimCreditBatch(new address[](0), new uint128[](0), new uint128[](0), new bytes32[][](0));
    }

    function test_ClaimCreditBatch_RevertsNonAdmin() public {
        PresaleImplementation presale = _deployCreditPresale();

        vm.prank(admin);
        presale.finalizeSale(_defaultFinalizeParams());

        vm.prank(address(0x999));
        vm.expectRevert(IPresale.Unauthorized.selector);
        presale.claimCreditBatch(new address[](0), new uint128[](0), new uint128[](0), new bytes32[][](0));
    }

    function test_ClaimCreditBatch_RevertsForSpotSale_AlreadyFinalized() public {
        // Spot sales finalize immediately in finalizeSale(), so claimCreditBatch
        // is blocked by the PresaleAlreadyFinalized check before reaching InvalidSaleType
        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](1);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp,
            endTime: block.timestamp + 7 days,
            totalPhaseCap: 200 ether,
            userAllocationCap: 200 ether,
            merkleRoot: bytes32(0)
        });

        IPresale.PresaleConfig memory config = IPresale.PresaleConfig({
            admin: admin,
            softCap: 50 ether,
            hardCap: 200 ether,
            saleType: IPresale.SaleType.Spot,
            circulatingSupplyBps: 500
        });

        IPresale.BFactoryParams memory bfp = IPresale.BFactoryParams({
            bToken: address(0),
            initialPoolBTokens: 1_000_000 ether,
            creator: admin,
            creatorFeePct: 0.75e18,
            createHook: false,
            claimMerkleRoot: bytes32(0),
            initialCollateral: 0,
            initialDebt: 0,
            initialBLV: 0,
            swapFeePct: 0.01 ether
        });

        vm.prank(admin);
        address presaleAddr = factory.deployPresale(phases, config, bfp, address(presaleToken));
        PresaleImplementation presale = PresaleImplementation(payable(presaleAddr));

        address depositor = address(0x100);
        presaleToken.mint(depositor, 100 ether);
        vm.prank(depositor);
        presaleToken.approve(address(presale), 100 ether);
        vm.prank(depositor);
        presale.deposit(0, 100 ether, new bytes32[](0));

        vm.prank(admin);
        presale.finalizeSale(_defaultFinalizeParams());

        // Spot sale already finalized — reverts before reaching InvalidSaleType
        assertTrue(presale.isFinalized());
        vm.prank(admin);
        vm.expectRevert(IPresale.PresaleAlreadyFinalized.selector);
        presale.claimCreditBatch(new address[](0), new uint128[](0), new uint128[](0), new bytes32[][](0));
    }

    function test_CompleteFinalization_RevertsForSpotSale() public {
        // Same as above — spot sales finalize immediately, so completeFinalization
        // is also blocked by PresaleAlreadyFinalized
        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](1);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp,
            endTime: block.timestamp + 7 days,
            totalPhaseCap: 200 ether,
            userAllocationCap: 200 ether,
            merkleRoot: bytes32(0)
        });

        IPresale.PresaleConfig memory config = IPresale.PresaleConfig({
            admin: admin,
            softCap: 50 ether,
            hardCap: 200 ether,
            saleType: IPresale.SaleType.Spot,
            circulatingSupplyBps: 500
        });

        IPresale.BFactoryParams memory bfp = IPresale.BFactoryParams({
            bToken: address(0),
            initialPoolBTokens: 1_000_000 ether,
            creator: admin,
            creatorFeePct: 0.75e18,
            createHook: false,
            claimMerkleRoot: bytes32(0),
            initialCollateral: 0,
            initialDebt: 0,
            initialBLV: 0,
            swapFeePct: 0.01 ether
        });

        vm.prank(admin);
        address presaleAddr = factory.deployPresale(phases, config, bfp, address(presaleToken));
        PresaleImplementation presale = PresaleImplementation(payable(presaleAddr));

        address depositor = address(0x100);
        presaleToken.mint(depositor, 100 ether);
        vm.prank(depositor);
        presaleToken.approve(address(presale), 100 ether);
        vm.prank(depositor);
        presale.deposit(0, 100 ether, new bytes32[](0));

        vm.prank(admin);
        presale.finalizeSale(_defaultFinalizeParams());

        vm.prank(admin);
        vm.expectRevert(IPresale.PresaleAlreadyFinalized.selector);
        presale.completeFinalization();
    }

    function test_CompleteFinalization_RevertsBeforePoolCreated() public {
        PresaleImplementation presale = _deployCreditPresale();

        vm.prank(admin);
        vm.expectRevert(IPresale.NotPoolCreated.selector);
        presale.completeFinalization();
    }

    function test_CompleteFinalization_RevertsNonAdmin() public {
        PresaleImplementation presale = _deployCreditPresale();

        vm.prank(admin);
        presale.finalizeSale(_defaultFinalizeParams());

        vm.prank(address(0x999));
        vm.expectRevert(IPresale.Unauthorized.selector);
        presale.completeFinalization();
    }

    function test_CompleteFinalization_RevertsDoubleComplete() public {
        PresaleImplementation presale = _deployCreditPresale();

        vm.prank(admin);
        presale.finalizeSale(_defaultFinalizeParams());
        vm.prank(admin);
        presale.completeFinalization();

        vm.prank(admin);
        vm.expectRevert(IPresale.PresaleAlreadyFinalized.selector);
        presale.completeFinalization();
    }

    /*//////////////////////////////////////////////////////////////
                     AFTERBURNER TRANSFER
    //////////////////////////////////////////////////////////////*/

    function test_CreditFinalize_TransfersCirculatingToRecipient() public {
        PresaleImplementation presale = _deployCreditPresale();
        address recipient = address(0xBBBB);

        IPresale.FinalizeParams memory params = _defaultFinalizeParams();
        params.circulatingSupplyRecipient = recipient;

        vm.prank(admin);
        presale.finalizeSale(params);

        // The recipient should have received the circulating supply bTokens
        address bToken = presale.getCreatedToken();
        uint256 recipientBalance = MockERC20(bToken).balanceOf(recipient);
        assertTrue(recipientBalance > 0);

        // The circulating supply = totalSupply * 500 / 10500 (approximately 5% of pool tokens)
        uint256 expectedCirculating = (1_000_000 ether * 500) / 10_000;
        assertEq(recipientBalance, expectedCirculating);
    }

    /*//////////////////////////////////////////////////////////////
                     SELF CREDIT CLAIM (ESCAPE HATCH)
    //////////////////////////////////////////////////////////////*/

    function test_SelfCreditClaim_RevertsDuringGracePeriod() public {
        PresaleImplementation presale = _deployCreditPresale();

        vm.prank(admin);
        presale.finalizeSale(_defaultFinalizeParams());

        bytes32[] memory proof = new bytes32[](0);
        vm.prank(address(0xA1));
        vm.expectRevert(IPresale.SelfCreditClaimGracePeriodActive.selector);
        presale.selfCreditClaim(500e18, 50e18, proof);
    }

    function test_SelfCreditClaim_SucceedsAfterGracePeriod() public {
        PresaleImplementation presale = _deployCreditPresale();

        vm.prank(admin);
        presale.finalizeSale(_defaultFinalizeParams());

        // Warp past the 24h grace window.
        vm.warp(block.timestamp + presale.RESCUE_GRACE_PERIOD());

        bytes32[] memory proof = new bytes32[](0);
        address depositor = address(0xA1);

        vm.expectEmit(false, false, false, true);
        emit IPresale.CreditBatchClaimed(1);
        vm.prank(depositor);
        presale.selfCreditClaim(500e18, 50e18, proof);

        assertEq(mockBaseline.getTotalClaimedUsers(), 1);
        assertEq(mockBaseline.claimCreditUsers(0), depositor);
        assertEq(mockBaseline.claimCreditCollaterals(0), 500e18);
        assertEq(mockBaseline.claimCreditDebts(0), 50e18);
    }

    function test_SelfCreditClaim_RevertsAfterCompleteFinalization() public {
        PresaleImplementation presale = _deployCreditPresale();

        vm.prank(admin);
        presale.finalizeSale(_defaultFinalizeParams());
        vm.prank(admin);
        presale.completeFinalization();

        vm.warp(block.timestamp + presale.RESCUE_GRACE_PERIOD());

        bytes32[] memory proof = new bytes32[](0);
        vm.prank(address(0xA1));
        vm.expectRevert(IPresale.PresaleAlreadyFinalized.selector);
        presale.selfCreditClaim(500e18, 50e18, proof);
    }

    function test_SelfCreditClaim_RevertsBeforePoolCreated() public {
        PresaleImplementation presale = _deployCreditPresale();

        vm.warp(block.timestamp + presale.RESCUE_GRACE_PERIOD());

        bytes32[] memory proof = new bytes32[](0);
        vm.prank(address(0xA1));
        vm.expectRevert(IPresale.NotPoolCreated.selector);
        presale.selfCreditClaim(500e18, 50e18, proof);
    }
}
