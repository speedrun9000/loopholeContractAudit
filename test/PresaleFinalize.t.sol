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

/// @dev Mock baseline that records claimCredit calls including proofs
contract MockBaseline {
    bool public claimCreditCalled;
    address public claimCreditBToken;
    address[] public claimCreditUsers;
    uint128[] public claimCreditCollaterals;
    uint128[] public claimCreditDebts;
    bytes32[][] public claimCreditProofs;

    function claimCredit(
        address _bToken,
        address[] calldata _users,
        uint128[] calldata _collaterals,
        uint128[] calldata _debts,
        bytes32[][] calldata _proofs
    ) external {
        claimCreditCalled = true;
        claimCreditBToken = _bToken;
        for (uint256 i; i < _users.length; i++) {
            claimCreditUsers.push(_users[i]);
            claimCreditCollaterals.push(_collaterals[i]);
            claimCreditDebts.push(_debts[i]);
            claimCreditProofs.push(_proofs[i]);
        }
    }

    function getClaimCreditUsersLength() external view returns (uint256) {
        return claimCreditUsers.length;
    }

    function getClaimCreditProof(uint256 index) external view returns (bytes32[] memory) {
        return claimCreditProofs[index];
    }
}

contract PresaleFinalizeTest is Test {
    PresaleFactory public factory;
    PresaleImplementation public implementation;
    MockBFactory public bFactory;
    UpgradeableBeacon public beacon;
    MockERC20 public presaleToken;

    address public admin = address(0x3);
    address public treasury = address(0x7777);
    address public feeRouter = address(0x8888);

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
    }

    function _deployAndFundPresale(uint256 softCap, uint256 hardCap, uint256 depositAmount)
        internal
        returns (PresaleImplementation presale)
    {
        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](1);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp,
            endTime: block.timestamp + 7 days,
            totalPhaseCap: hardCap,
            userAllocationCap: hardCap,
            merkleRoot: bytes32(0)
        });

        IPresale.PresaleConfig memory config = IPresale.PresaleConfig({
            admin: admin,
            softCap: softCap,
            hardCap: hardCap,
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
        presaleToken.mint(depositor, depositAmount);
        vm.prank(depositor);
        presaleToken.approve(address(presale), depositAmount);
        vm.prank(depositor);
        presale.deposit(0, depositAmount, new bytes32[](0));
    }

    function _defaultFinalizeParams() internal view returns (IPresale.FinalizeParams memory) {
        return IPresale.FinalizeParams({
            name: "LST Token",
            symbol: "LST",
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

    /*//////////////////////////////////////////////////////////////
                     FUND SPLITTING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_FinalizeSplitsFundsToTreasury() public {
        uint256 raised = 100 ether;
        PresaleImplementation presale = _deployAndFundPresale(50 ether, 200 ether, raised);

        uint256 treasuryBefore = presaleToken.balanceOf(treasury);

        IPresale.FinalizeParams memory params = _defaultFinalizeParams();
        params.acquisitionTreasury = treasury;
        params.bpsToTreasury = 5000; // 50%

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        presale.finalizeSale(params);

        // Credit sale: complete finalization
        vm.prank(admin);
        presale.completeFinalization();

        // 50% of 100 ether = 50 ether to treasury
        assertEq(presaleToken.balanceOf(treasury) - treasuryBefore, 50 ether);
    }

    function test_FinalizeZeroBpsSendsAllToPool() public {
        uint256 raised = 100 ether;
        PresaleImplementation presale = _deployAndFundPresale(50 ether, 200 ether, raised);

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        presale.finalizeSale(_defaultFinalizeParams());
        vm.prank(admin);
        presale.completeFinalization();

        // Treasury gets nothing
        assertEq(presaleToken.balanceOf(treasury), 0);
    }

    function test_FinalizeRevertsInvalidBps() public {
        PresaleImplementation presale = _deployAndFundPresale(50 ether, 200 ether, 100 ether);

        IPresale.FinalizeParams memory params = _defaultFinalizeParams();
        params.acquisitionTreasury = treasury;
        params.bpsToTreasury = 10_001; // > 10000

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vm.expectRevert(IPresale.InvalidFundSplit.selector);
        presale.finalizeSale(params);
    }

    function test_FinalizeRevertsZeroTreasuryWithNonZeroBps() public {
        PresaleImplementation presale = _deployAndFundPresale(50 ether, 200 ether, 100 ether);

        IPresale.FinalizeParams memory params = _defaultFinalizeParams();
        params.acquisitionTreasury = address(0);
        params.bpsToTreasury = 5000;

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vm.expectRevert(IPresale.InvalidFundSplit.selector);
        presale.finalizeSale(params);
    }

    /*//////////////////////////////////////////////////////////////
                     CLAIM DATA TESTS
    //////////////////////////////////////////////////////////////*/

    function test_FinalizePassesClaimDataToFactory() public {
        PresaleImplementation presale = _deployAndFundPresale(50 ether, 200 ether, 100 ether);

        IPresale.FinalizeParams memory params = _defaultFinalizeParams();
        params.claimMerkleRoot = keccak256("test merkle root");
        params.initialCollateral = 500 ether;
        params.initialDebt = 50 ether;

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        presale.finalizeSale(params);

        // Not yet fully finalized (credit sale)
        assertFalse(presale.isFinalized());
        assertTrue(presale.poolCreated());
        assertTrue(presale.getCreatedToken() != address(0));

        vm.prank(admin);
        presale.completeFinalization();
        assertTrue(presale.isFinalized());
    }

    /*//////////////////////////////////////////////////////////////
                     FULL INTEGRATION
    //////////////////////////////////////////////////////////////*/

    function test_FinalizeFull_SplitFunds_ClaimData() public {
        uint256 raised = 200 ether;
        PresaleImplementation presale = _deployAndFundPresale(100 ether, 300 ether, raised);

        IPresale.FinalizeParams memory params = IPresale.FinalizeParams({
            name: "PunkLoop",
            symbol: "PUNKLOOP",
            initialActivePrice: 1 ether,
            initialBlvPrice: 0.5 ether,
            claimMerkleRoot: keccak256("presaler claims"),
            initialCollateral: 1000 ether,
            initialDebt: 100 ether,
            acquisitionTreasury: treasury,
            bpsToTreasury: 3000, // 30% to treasury
            feeRouter: address(0),
            baseline: address(0),
            salt: bytes32(0),
            circulatingSupplyRecipient: address(0)
        });

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        presale.finalizeSale(params);

        // 30% of 200 = 60 to treasury
        assertEq(presaleToken.balanceOf(treasury), 60 ether);

        // Not yet fully finalized (credit sale needs completeFinalization)
        assertFalse(presale.isFinalized());
        assertTrue(presale.getCreatedToken() != address(0));

        vm.prank(admin);
        presale.completeFinalization();
        assertTrue(presale.isFinalized());
    }

    /*//////////////////////////////////////////////////////////////
                     CLAIM CREDIT BATCH TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ClaimCreditBatchOnBaseline() public {
        MockBaseline mockBaseline = new MockBaseline();
        PresaleImplementation presale = _deployAndFundPresale(50 ether, 200 ether, 100 ether);

        IPresale.FinalizeParams memory params = _defaultFinalizeParams();
        params.claimMerkleRoot = keccak256("root");
        params.initialCollateral = 800e18;
        params.initialDebt = 80e18;
        params.baseline = address(mockBaseline);

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        presale.finalizeSale(params);

        // Set up claim credit data for 2 users
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
        proofs[0] = new bytes32[](1);
        proofs[0][0] = keccak256("proof0");
        proofs[1] = new bytes32[](1);
        proofs[1][0] = keccak256("proof1");

        // Claim credit batch
        vm.prank(admin);
        presale.claimCreditBatch(users, collaterals, debts, proofs);

        // Verify claimCredit was called with correct args
        assertTrue(mockBaseline.claimCreditCalled());
        assertEq(mockBaseline.claimCreditBToken(), presale.getCreatedToken());
        assertEq(mockBaseline.getClaimCreditUsersLength(), 2);
        assertEq(mockBaseline.claimCreditUsers(0), address(0xA1));
        assertEq(mockBaseline.claimCreditUsers(1), address(0xA2));
        assertEq(mockBaseline.claimCreditCollaterals(0), 500e18);
        assertEq(mockBaseline.claimCreditCollaterals(1), 300e18);
        assertEq(mockBaseline.claimCreditDebts(0), 50e18);
        assertEq(mockBaseline.claimCreditDebts(1), 30e18);

        // Verify proofs were passed through correctly
        bytes32[] memory proof0 = mockBaseline.getClaimCreditProof(0);
        bytes32[] memory proof1 = mockBaseline.getClaimCreditProof(1);
        assertEq(proof0.length, 1);
        assertEq(proof0[0], keccak256("proof0"));
        assertEq(proof1.length, 1);
        assertEq(proof1[0], keccak256("proof1"));

        // Complete finalization
        vm.prank(admin);
        presale.completeFinalization();
        assertTrue(presale.isFinalized());
    }

    function test_ClaimCreditBatchRevertsBeforePoolCreated() public {
        PresaleImplementation presale = _deployAndFundPresale(50 ether, 200 ether, 100 ether);

        vm.prank(admin);
        vm.expectRevert(IPresale.NotPoolCreated.selector);
        presale.claimCreditBatch(new address[](0), new uint128[](0), new uint128[](0), new bytes32[][](0));
    }

    function test_ClaimCreditBatchRevertsAfterFinalized() public {
        MockBaseline mockBaseline = new MockBaseline();
        PresaleImplementation presale = _deployAndFundPresale(50 ether, 200 ether, 100 ether);

        IPresale.FinalizeParams memory params = _defaultFinalizeParams();
        params.baseline = address(mockBaseline);

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        presale.finalizeSale(params);
        vm.prank(admin);
        presale.completeFinalization();

        vm.prank(admin);
        vm.expectRevert(IPresale.PresaleAlreadyFinalized.selector);
        presale.claimCreditBatch(new address[](0), new uint128[](0), new uint128[](0), new bytes32[][](0));
    }

    function test_CompleteFinalizationRevertsBeforePoolCreated() public {
        PresaleImplementation presale = _deployAndFundPresale(50 ether, 200 ether, 100 ether);

        vm.prank(admin);
        vm.expectRevert(IPresale.NotPoolCreated.selector);
        presale.completeFinalization();
    }

    /*//////////////////////////////////////////////////////////////
                  FINALIZATION GATING (PHASES + CAPS)
    //////////////////////////////////////////////////////////////*/

    function test_FinalizeRevertsBeforePhasesEndedAndUnderHardCap() public {
        // Soft cap met (100 >= 50) but phases still active and hard cap (200) not met
        PresaleImplementation presale = _deployAndFundPresale(50 ether, 200 ether, 100 ether);

        vm.prank(admin);
        vm.expectRevert(IPresale.PresaleNotFinalizable.selector);
        presale.finalizeSale(_defaultFinalizeParams());
    }

    function test_FinalizeAllowedEarlyWhenHardCapMet() public {
        // Hard cap exactly met, phases still active — early finalize should succeed
        PresaleImplementation presale = _deployAndFundPresale(50 ether, 200 ether, 200 ether);

        vm.prank(admin);
        presale.finalizeSale(_defaultFinalizeParams());

        assertTrue(presale.poolCreated());
    }

    function test_FinalizeRevertsAfterPhasesEndedUnderSoftCap() public {
        // Phases ended but soft cap (50) not met — must revert
        PresaleImplementation presale = _deployAndFundPresale(50 ether, 200 ether, 30 ether);

        vm.warp(block.timestamp + 8 days);

        vm.prank(admin);
        vm.expectRevert(IPresale.PresaleNotFinalizable.selector);
        presale.finalizeSale(_defaultFinalizeParams());
    }
}
