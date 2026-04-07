// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {PresaleFactory} from "../src/PresaleFactory.sol";
import {PresaleImplementation} from "../src/PresaleImplementation.sol";
import {IPresale} from "../src/interfaces/IPresale.sol";
import {MockBFactory} from "./mocks/MockBFactory.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PresaleSpotClaimTest is Test {
    PresaleFactory public factory;
    PresaleImplementation public implementation;
    MockBFactory public bFactory;
    UpgradeableBeacon public beacon;
    MockERC20 public presaleToken;

    address public admin = address(0x3);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public user3 = address(0x4);

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

        presaleToken.mint(user1, 1000 ether);
        presaleToken.mint(user2, 1000 ether);
        presaleToken.mint(user3, 1000 ether);
    }

    function _deploySpotPresale(uint256 softCap, uint256 hardCap, uint16 circulatingBps)
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
            saleType: IPresale.SaleType.Spot,
            circulatingSupplyBps: circulatingBps
        });

        IPresale.BFactoryParams memory bfp = IPresale.BFactoryParams({
            bToken: address(0),
            initialPoolBTokens: 1_000_000 ether,
            creator: admin,
            creatorFeePct: 0.75e18,
            createHook: false,
            claimMerkleRoot: bytes32(0),
            initialCollateral: 0,
            initialDebt: 0
        });

        vm.prank(admin);
        address presaleAddr = factory.deployPresale(phases, config, bfp, address(presaleToken));
        presale = PresaleImplementation(payable(presaleAddr));
    }

    function _deployMultiPhaseSpotPresale() internal returns (PresaleImplementation presale) {
        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](2);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp,
            endTime: block.timestamp + 3 days,
            totalPhaseCap: 100 ether,
            userAllocationCap: 50 ether,
            merkleRoot: bytes32(0)
        });
        phases[1] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp + 3 days,
            endTime: block.timestamp + 7 days,
            totalPhaseCap: 100 ether,
            userAllocationCap: 50 ether,
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
            initialDebt: 0
        });

        vm.prank(admin);
        address presaleAddr = factory.deployPresale(phases, config, bfp, address(presaleToken));
        presale = PresaleImplementation(payable(presaleAddr));
    }

    function _defaultFinalizeParams() internal pure returns (IPresale.FinalizeParams memory) {
        return IPresale.FinalizeParams({
            name: "Spot Token",
            symbol: "SPOT",
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
                     BASIC SPOT CLAIM FLOW
    //////////////////////////////////////////////////////////////*/

    function test_SpotClaim_BasicFlow() public {
        PresaleImplementation presale = _deploySpotPresale(50 ether, 200 ether, 500);

        // User1 deposits
        vm.prank(user1);
        presaleToken.approve(address(presale), type(uint256).max);
        vm.prank(user1);
        presale.deposit(0, 100 ether, new bytes32[](0));

        // Finalize — verify PresaleFinalized event
        vm.prank(admin);
        presale.finalizeSale(_defaultFinalizeParams());

        // Spot sale should be immediately finalized
        assertTrue(presale.isFinalized());
        assertTrue(presale.getTotalClaimableTokens() > 0);

        // Claim — verify SpotClaimed event
        uint256 claimable = presale.getClaimableAmount(user1);
        assertEq(claimable, presale.getTotalClaimableTokens()); // Only depositor, gets all

        vm.expectEmit(true, false, false, true);
        emit IPresale.SpotClaimed(user1, claimable);
        vm.prank(user1);
        presale.claimSpot();

        // Verify bToken received
        address bToken = presale.getCreatedToken();
        assertEq(IERC20(bToken).balanceOf(user1), claimable);

        // Verify claimed
        assertEq(presale.getClaimableAmount(user1), 0);
    }

    function test_SpotClaim_MultipleUsers_ProRata() public {
        PresaleImplementation presale = _deploySpotPresale(50 ether, 200 ether, 500);

        // User1 deposits 60, user2 deposits 40 (60/40 split)
        vm.prank(user1);
        presaleToken.approve(address(presale), type(uint256).max);
        vm.prank(user2);
        presaleToken.approve(address(presale), type(uint256).max);

        vm.prank(user1);
        presale.deposit(0, 60 ether, new bytes32[](0));
        vm.prank(user2);
        presale.deposit(0, 40 ether, new bytes32[](0));

        // Finalize
        vm.prank(admin);
        presale.finalizeSale(_defaultFinalizeParams());

        uint256 totalClaimable = presale.getTotalClaimableTokens();

        // Check pro-rata amounts
        uint256 user1Claimable = presale.getClaimableAmount(user1);
        uint256 user2Claimable = presale.getClaimableAmount(user2);

        assertEq(user1Claimable, (60 ether * totalClaimable) / 100 ether);
        assertEq(user2Claimable, (40 ether * totalClaimable) / 100 ether);

        // Both claim
        vm.prank(user1);
        presale.claimSpot();
        vm.prank(user2);
        presale.claimSpot();

        address bToken = presale.getCreatedToken();
        assertEq(IERC20(bToken).balanceOf(user1), user1Claimable);
        assertEq(IERC20(bToken).balanceOf(user2), user2Claimable);
    }

    function test_SpotClaim_MultiPhase() public {
        PresaleImplementation presale = _deployMultiPhaseSpotPresale();

        vm.prank(user1);
        presaleToken.approve(address(presale), type(uint256).max);

        // Deposit in phase 0
        vm.prank(user1);
        presale.deposit(0, 30 ether, new bytes32[](0));

        // Warp to phase 1
        vm.warp(block.timestamp + 3 days);

        // Deposit in phase 1
        vm.prank(user1);
        presale.deposit(1, 20 ether, new bytes32[](0));

        // Finalize
        vm.prank(admin);
        presale.finalizeSale(_defaultFinalizeParams());

        // Claim should include both phases (50 ether total)
        uint256 totalClaimable = presale.getTotalClaimableTokens();
        uint256 claimable = presale.getClaimableAmount(user1);
        assertEq(claimable, totalClaimable); // Only depositor

        vm.prank(user1);
        presale.claimSpot();

        address bToken = presale.getCreatedToken();
        assertEq(IERC20(bToken).balanceOf(user1), totalClaimable);
    }

    /*//////////////////////////////////////////////////////////////
                     CONFIGURABLE CIRCULATING SUPPLY
    //////////////////////////////////////////////////////////////*/

    function test_SpotClaim_ConfigurableCirculatingSupply() public {
        // Deploy with 10% circulating supply (1000 bps)
        PresaleImplementation presale = _deploySpotPresale(50 ether, 200 ether, 1000);

        vm.prank(user1);
        presaleToken.approve(address(presale), type(uint256).max);
        vm.prank(user1);
        presale.deposit(0, 100 ether, new bytes32[](0));

        vm.prank(admin);
        presale.finalizeSale(_defaultFinalizeParams());

        uint256 totalClaimable = presale.getTotalClaimableTokens();

        // With 10% circulating, totalSupply = initialPoolBTokens * 110 / 100
        // circulating = totalSupply - initialPoolBTokens = initialPoolBTokens * 10 / 100
        uint256 expectedCirculating = (1_000_000 ether * 1000) / 10_000;
        assertEq(totalClaimable, expectedCirculating);
    }

    function test_SpotClaim_WithInitialCollateral() public {
        // Deploy spot presale
        PresaleImplementation presale = _deploySpotPresale(50 ether, 200 ether, 500);

        vm.prank(user1);
        presaleToken.approve(address(presale), type(uint256).max);
        vm.prank(user1);
        presale.deposit(0, 100 ether, new bytes32[](0));

        // Finalize with nonzero initialCollateral
        IPresale.FinalizeParams memory params = _defaultFinalizeParams();
        params.initialCollateral = 500 ether;
        params.initialDebt = 50 ether;

        vm.prank(admin);
        presale.finalizeSale(params);

        uint256 totalClaimable = presale.getTotalClaimableTokens();

        // circulatingSupply = totalSupply - initialPoolBTokens - initialCollateral
        // totalSupply = (1_000_000 + 500) * 10_500 / 10_000 = 1_050_525
        // circulating = 1_050_525 - 1_000_000 - 500 = 50_025
        uint256 expectedTotalSupply = ((1_000_000 ether + 500 ether) * 10_500) / 10_000;
        uint256 expectedCirculating = expectedTotalSupply - 1_000_000 ether - 500 ether;
        assertEq(totalClaimable, expectedCirculating);
        assertTrue(totalClaimable > 0);

        // User can still claim
        vm.prank(user1);
        presale.claimSpot();

        address bToken = presale.getCreatedToken();
        assertEq(IERC20(bToken).balanceOf(user1), totalClaimable);
    }

    function test_SpotClaim_MinCirculatingSupplyBps() public {
        // 500 bps (5%) is the minimum
        _deploySpotPresale(50 ether, 200 ether, 500);

        // Below 500 should revert
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
            circulatingSupplyBps: 499 // below minimum
        });

        IPresale.BFactoryParams memory bfp = IPresale.BFactoryParams({
            bToken: address(0),
            initialPoolBTokens: 1_000_000 ether,
            creator: admin,
            creatorFeePct: 0.75e18,
            createHook: false,
            claimMerkleRoot: bytes32(0),
            initialCollateral: 0,
            initialDebt: 0
        });

        vm.prank(admin);
        vm.expectRevert(IPresale.InvalidPresaleConfiguration.selector);
        factory.deployPresale(phases, config, bfp, address(presaleToken));
    }

    /*//////////////////////////////////////////////////////////////
                     REVERT CASES
    //////////////////////////////////////////////////////////////*/

    function test_SpotClaim_RevertsBeforeFinalization() public {
        PresaleImplementation presale = _deploySpotPresale(50 ether, 200 ether, 500);

        vm.prank(user1);
        presaleToken.approve(address(presale), type(uint256).max);
        vm.prank(user1);
        presale.deposit(0, 100 ether, new bytes32[](0));

        vm.prank(user1);
        vm.expectRevert(IPresale.PresaleNotFinalized.selector);
        presale.claimSpot();
    }

    function test_SpotClaim_RevertsForCreditSale() public {
        // Deploy credit sale
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
            initialDebt: 0
        });

        vm.prank(admin);
        address presaleAddr = factory.deployPresale(phases, config, bfp, address(presaleToken));
        PresaleImplementation presale = PresaleImplementation(payable(presaleAddr));

        vm.prank(user1);
        presaleToken.approve(address(presale), type(uint256).max);
        vm.prank(user1);
        presale.deposit(0, 100 ether, new bytes32[](0));

        vm.prank(admin);
        presale.finalizeSale(_defaultFinalizeParams());
        vm.prank(admin);
        presale.completeFinalization();

        vm.prank(user1);
        vm.expectRevert(IPresale.InvalidSaleType.selector);
        presale.claimSpot();
    }

    function test_SpotClaim_RevertsDoubleClaim() public {
        PresaleImplementation presale = _deploySpotPresale(50 ether, 200 ether, 500);

        vm.prank(user1);
        presaleToken.approve(address(presale), type(uint256).max);
        vm.prank(user1);
        presale.deposit(0, 100 ether, new bytes32[](0));

        vm.prank(admin);
        presale.finalizeSale(_defaultFinalizeParams());

        vm.prank(user1);
        presale.claimSpot();

        vm.prank(user1);
        vm.expectRevert(IPresale.AlreadyClaimed.selector);
        presale.claimSpot();
    }

    function test_SpotClaim_RevertsNoDeposit() public {
        PresaleImplementation presale = _deploySpotPresale(50 ether, 200 ether, 500);

        // user1 deposits so we can finalize
        vm.prank(user1);
        presaleToken.approve(address(presale), type(uint256).max);
        vm.prank(user1);
        presale.deposit(0, 100 ether, new bytes32[](0));

        vm.prank(admin);
        presale.finalizeSale(_defaultFinalizeParams());

        // user2 never deposited
        vm.prank(user2);
        vm.expectRevert(IPresale.NothingToClaim.selector);
        presale.claimSpot();
    }

    /*//////////////////////////////////////////////////////////////
                     VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_GetSaleType() public {
        PresaleImplementation presale = _deploySpotPresale(50 ether, 200 ether, 500);
        assertEq(uint256(presale.getSaleType()), uint256(IPresale.SaleType.Spot));
    }

    function test_GetClaimableAmount_ZeroBeforeFinalize() public {
        PresaleImplementation presale = _deploySpotPresale(50 ether, 200 ether, 500);

        vm.prank(user1);
        presaleToken.approve(address(presale), type(uint256).max);
        vm.prank(user1);
        presale.deposit(0, 100 ether, new bytes32[](0));

        // Before finalization: returns 0
        assertEq(presale.getClaimableAmount(user1), 0);

        // After finalization: returns non-zero claimable amount
        vm.prank(admin);
        presale.finalizeSale(_defaultFinalizeParams());

        uint256 claimable = presale.getClaimableAmount(user1);
        assertEq(claimable, presale.getTotalClaimableTokens());
        assertTrue(claimable > 0);

        // After claiming: returns 0 again
        vm.prank(user1);
        presale.claimSpot();
        assertEq(presale.getClaimableAmount(user1), 0);

        // Non-depositor: always 0
        assertEq(presale.getClaimableAmount(user2), 0);
    }

    /*//////////////////////////////////////////////////////////////
                     FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_SpotClaim_ProRataDistribution(
        uint256 deposit1,
        uint256 deposit2,
        uint16 circulatingBps,
        uint256 initialCollateral
    ) public {
        deposit1 = bound(deposit1, 1 ether, 500 ether);
        deposit2 = bound(deposit2, 1 ether, 500 ether);
        circulatingBps = uint16(bound(circulatingBps, 500, 5000));
        initialCollateral = bound(initialCollateral, 0, 500_000 ether);

        uint256 hardCap = deposit1 + deposit2;
        PresaleImplementation presale = _deploySpotPresale(1 ether, hardCap, circulatingBps);

        presaleToken.mint(user1, deposit1);
        presaleToken.mint(user2, deposit2);

        vm.prank(user1);
        presaleToken.approve(address(presale), type(uint256).max);
        vm.prank(user2);
        presaleToken.approve(address(presale), type(uint256).max);

        vm.prank(user1);
        presale.deposit(0, deposit1, new bytes32[](0));
        vm.prank(user2);
        presale.deposit(0, deposit2, new bytes32[](0));

        IPresale.FinalizeParams memory params = _defaultFinalizeParams();
        params.initialCollateral = initialCollateral;

        vm.prank(admin);
        presale.finalizeSale(params);

        uint256 totalClaimable = presale.getTotalClaimableTokens();

        // Validate totalClaimable matches expected circulating supply from first principles
        uint256 initialPoolBTokens = 1_000_000 ether;
        uint256 expectedTotalSupply = ((initialPoolBTokens + initialCollateral) * (10_000 + circulatingBps)) / 10_000;
        uint256 expectedCirculating = expectedTotalSupply - initialPoolBTokens - initialCollateral;
        assertEq(totalClaimable, expectedCirculating, "totalClaimable should match circulating supply formula");
        assertTrue(totalClaimable > 0, "totalClaimable must be nonzero");

        uint256 claim1 = presale.getClaimableAmount(user1);
        uint256 claim2 = presale.getClaimableAmount(user2);

        // Validate each user's claim from first principles
        assertEq(claim1, (deposit1 * expectedCirculating) / hardCap);
        assertEq(claim2, (deposit2 * expectedCirculating) / hardCap);

        // Validate each user's share is proportional to their deposit
        // claim1 / claim2 should approximate deposit1 / deposit2
        // We check: claim1 * deposit2 ≈ claim2 * deposit1 (cross-multiply to avoid division)
        uint256 cross1 = claim1 * deposit2;
        uint256 cross2 = claim2 * deposit1;
        uint256 crossDiff = cross1 > cross2 ? cross1 - cross2 : cross2 - cross1;
        assertLe(crossDiff, deposit1 + deposit2, "pro-rata shares should be proportional to deposits");

        // Sum of claims should never exceed total claimable (rounding dust is ok)
        assertLe(claim1 + claim2, totalClaimable);

        // Both claim successfully
        vm.prank(user1);
        presale.claimSpot();
        vm.prank(user2);
        presale.claimSpot();

        address bToken = presale.getCreatedToken();
        assertEq(IERC20(bToken).balanceOf(user1), claim1);
        assertEq(IERC20(bToken).balanceOf(user2), claim2);
    }

    function testFuzz_SpotClaim_50Users(uint256 seed, uint256 initialCollateral) public {
        uint256 numUsers = 50;
        uint16 circulatingBps = 500;
        initialCollateral = bound(initialCollateral, 0, 500_000 ether);

        // Generate deterministic but varied deposits from the seed
        address[] memory users = new address[](numUsers);
        uint256[] memory deposits = new uint256[](numUsers);
        uint256 totalDeposits = 0;

        for (uint256 i = 0; i < numUsers; i++) {
            users[i] = address(uint160(0x1000 + i));
            // Each user deposits between 1 and 100 ether, derived from seed
            deposits[i] = bound(uint256(keccak256(abi.encode(seed, i))), 1 ether, 100 ether);
            totalDeposits += deposits[i];
        }

        // Deploy presale with enough capacity
        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](1);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp,
            endTime: block.timestamp + 7 days,
            totalPhaseCap: totalDeposits,
            userAllocationCap: totalDeposits,
            merkleRoot: bytes32(0)
        });

        IPresale.PresaleConfig memory config = IPresale.PresaleConfig({
            admin: admin,
            softCap: 1 ether,
            hardCap: totalDeposits,
            saleType: IPresale.SaleType.Spot,
            circulatingSupplyBps: circulatingBps
        });

        IPresale.BFactoryParams memory bfp = IPresale.BFactoryParams({
            bToken: address(0),
            initialPoolBTokens: 1_000_000 ether,
            creator: admin,
            creatorFeePct: 0.75e18,
            createHook: false,
            claimMerkleRoot: bytes32(0),
            initialCollateral: 0,
            initialDebt: 0
        });

        vm.prank(admin);
        address presaleAddr = factory.deployPresale(phases, config, bfp, address(presaleToken));
        PresaleImplementation presale = PresaleImplementation(payable(presaleAddr));

        // All users deposit
        for (uint256 i = 0; i < numUsers; i++) {
            presaleToken.mint(users[i], deposits[i]);
            vm.prank(users[i]);
            presaleToken.approve(address(presale), deposits[i]);
            vm.prank(users[i]);
            presale.deposit(0, deposits[i], new bytes32[](0));
        }

        assertEq(presale.getTotalRaised(), totalDeposits);

        // Finalize with fuzzed initialCollateral
        IPresale.FinalizeParams memory params = _defaultFinalizeParams();
        params.initialCollateral = initialCollateral;

        vm.prank(admin);
        presale.finalizeSale(params);
        assertTrue(presale.isFinalized());

        uint256 totalClaimable = presale.getTotalClaimableTokens();
        address bToken = presale.getCreatedToken();

        // Validate totalClaimable against expected circulating supply
        uint256 initialPoolBTokens = 1_000_000 ether;
        uint256 expectedTotalSupply = ((initialPoolBTokens + initialCollateral) * (10_000 + circulatingBps)) / 10_000;
        uint256 expectedCirculating = expectedTotalSupply - initialPoolBTokens - initialCollateral;
        assertEq(totalClaimable, expectedCirculating, "totalClaimable must match circulating supply formula");

        // All users claim and verify pro-rata amounts
        uint256 totalClaimed = 0;
        uint256 claimedCount = 0;
        for (uint256 i = 0; i < numUsers; i++) {
            // Independently compute expected claim from first principles
            uint256 expectedClaim = (deposits[i] * expectedCirculating) / totalDeposits;
            assertEq(presale.getClaimableAmount(users[i]), expectedClaim);
            assertTrue(expectedClaim > 0, "each user should have nonzero claim");

            vm.prank(users[i]);
            presale.claimSpot();
            claimedCount++;

            assertEq(IERC20(bToken).balanceOf(users[i]), expectedClaim);
            totalClaimed += expectedClaim;

            // Can't double claim
            vm.prank(users[i]);
            vm.expectRevert(IPresale.AlreadyClaimed.selector);
            presale.claimSpot();
        }

        // Verify all 50 users claimed
        assertEq(claimedCount, numUsers);
        // Total claimed should never exceed claimable (rounding dust stays in contract)
        assertLe(totalClaimed, totalClaimable);
        // Dust should be minimal (less than numUsers wei due to integer division)
        assertLe(totalClaimable - totalClaimed, numUsers);
    }

    function testFuzz_SpotClaim_50Users_MultiPhase(uint256 seed, uint256 initialCollateral) public {
        uint256 numUsers = 50;
        uint256 startTime = block.timestamp;
        initialCollateral = bound(initialCollateral, 0, 500_000 ether);

        // Deploy 3-phase spot presale
        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](3);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: startTime,
            endTime: startTime + 3 days,
            totalPhaseCap: 5000 ether,
            userAllocationCap: 100 ether,
            merkleRoot: bytes32(0)
        });
        phases[1] = IPresale.PresalePhaseConfig({
            startTime: startTime + 3 days,
            endTime: startTime + 6 days,
            totalPhaseCap: 5000 ether,
            userAllocationCap: 100 ether,
            merkleRoot: bytes32(0)
        });
        phases[2] = IPresale.PresalePhaseConfig({
            startTime: startTime + 6 days,
            endTime: startTime + 10 days,
            totalPhaseCap: 5000 ether,
            userAllocationCap: 100 ether,
            merkleRoot: bytes32(0)
        });

        IPresale.PresaleConfig memory config = IPresale.PresaleConfig({
            admin: admin,
            softCap: 1 ether,
            hardCap: 15000 ether,
            saleType: IPresale.SaleType.Spot,
            circulatingSupplyBps: 1000
        });

        IPresale.BFactoryParams memory bfp = IPresale.BFactoryParams({
            bToken: address(0),
            initialPoolBTokens: 1_000_000 ether,
            creator: admin,
            creatorFeePct: 0.75e18,
            createHook: false,
            claimMerkleRoot: bytes32(0),
            initialCollateral: 0,
            initialDebt: 0
        });

        vm.prank(admin);
        address presaleAddr = factory.deployPresale(phases, config, bfp, address(presaleToken));
        PresaleImplementation presale = PresaleImplementation(payable(presaleAddr));

        // Generate users and their multi-phase deposits
        address[] memory users = new address[](numUsers);
        uint256[] memory totalUserDeposits = new uint256[](numUsers);
        uint256 totalRaised = 0;

        for (uint256 i = 0; i < numUsers; i++) {
            users[i] = address(uint160(0x2000 + i));
            presaleToken.mint(users[i], 300 ether);
            vm.prank(users[i]);
            presaleToken.approve(address(presale), type(uint256).max);
        }

        // Phase 0: first 30 users deposit
        for (uint256 i = 0; i < 30; i++) {
            uint256 amount = bound(uint256(keccak256(abi.encode(seed, "p0", i))), 1 ether, 100 ether);
            vm.prank(users[i]);
            presale.deposit(0, amount, new bytes32[](0));
            totalUserDeposits[i] += amount;
            totalRaised += amount;
        }

        // Phase 1: users 10-40 deposit
        vm.warp(startTime + 3 days);
        for (uint256 i = 10; i < 40; i++) {
            uint256 amount = bound(uint256(keccak256(abi.encode(seed, "p1", i))), 1 ether, 100 ether);
            vm.prank(users[i]);
            presale.deposit(1, amount, new bytes32[](0));
            totalUserDeposits[i] += amount;
            totalRaised += amount;
        }

        // Phase 2: users 20-49 deposit
        vm.warp(startTime + 6 days);
        for (uint256 i = 20; i < numUsers; i++) {
            uint256 amount = bound(uint256(keccak256(abi.encode(seed, "p2", i))), 1 ether, 100 ether);
            vm.prank(users[i]);
            presale.deposit(2, amount, new bytes32[](0));
            totalUserDeposits[i] += amount;
            totalRaised += amount;
        }

        assertEq(presale.getTotalRaised(), totalRaised);

        // Finalize with fuzzed initialCollateral
        IPresale.FinalizeParams memory params = _defaultFinalizeParams();
        params.initialCollateral = initialCollateral;

        vm.prank(admin);
        presale.finalizeSale(params);

        uint256 totalClaimable = presale.getTotalClaimableTokens();
        address bToken = presale.getCreatedToken();

        // Validate totalClaimable against expected circulating supply (10% = 1000 bps)
        uint256 initialPoolBTokens = 1_000_000 ether;
        uint256 expectedTotalSupply = ((initialPoolBTokens + initialCollateral) * (10_000 + 1000)) / 10_000;
        uint256 expectedCirculating = expectedTotalSupply - initialPoolBTokens - initialCollateral;
        assertEq(totalClaimable, expectedCirculating, "totalClaimable must match circulating supply formula");

        // Verify each phase had deposits (no vacuous phases)
        uint256 phase0Deposits = 0;
        uint256 phase1Deposits = 0;
        uint256 phase2Deposits = 0;
        for (uint256 i = 0; i < 30; i++) {
            phase0Deposits += presale.getUserDepositedAmount(users[i], 0);
        }
        for (uint256 i = 10; i < 40; i++) {
            phase1Deposits += presale.getUserDepositedAmount(users[i], 1);
        }
        for (uint256 i = 20; i < numUsers; i++) {
            phase2Deposits += presale.getUserDepositedAmount(users[i], 2);
        }
        assertTrue(phase0Deposits > 0, "phase 0 should have deposits");
        assertTrue(phase1Deposits > 0, "phase 1 should have deposits");
        assertTrue(phase2Deposits > 0, "phase 2 should have deposits");

        // All users claim
        uint256 totalClaimed = 0;
        uint256 claimedCount = 0;
        uint256 skippedCount = 0;
        for (uint256 i = 0; i < numUsers; i++) {
            // Compute expected claim from first principles, not from contract's totalClaimable
            uint256 expectedClaim = (totalUserDeposits[i] * expectedCirculating) / totalRaised;

            if (totalUserDeposits[i] == 0) {
                vm.prank(users[i]);
                vm.expectRevert(IPresale.NothingToClaim.selector);
                presale.claimSpot();
                skippedCount++;
                continue;
            }

            assertEq(presale.getClaimableAmount(users[i]), expectedClaim);
            assertTrue(expectedClaim > 0, "depositor should have nonzero claim");

            vm.prank(users[i]);
            presale.claimSpot();
            claimedCount++;

            assertEq(IERC20(bToken).balanceOf(users[i]), expectedClaim);
            totalClaimed += expectedClaim;
        }

        // All 50 users accounted for, and all depositors claimed
        assertEq(claimedCount + skippedCount, numUsers);
        // Users 0-9 deposit only in phase 0, users 40-49 only in phase 2
        // Users 10-19 in phases 0+1, users 20-29 in all 3, users 30-39 in phases 1+2
        // So all 50 users deposited in at least one phase
        assertEq(claimedCount, numUsers);
        assertEq(skippedCount, 0);

        // Rounding dust check
        assertLe(totalClaimed, totalClaimable);
        assertLe(totalClaimable - totalClaimed, numUsers);
    }

    /*//////////////////////////////////////////////////////////////
                     VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_SpotFinalizeSetsFinalized() public {
        PresaleImplementation presale = _deploySpotPresale(50 ether, 200 ether, 500);

        vm.prank(user1);
        presaleToken.approve(address(presale), type(uint256).max);
        vm.prank(user1);
        presale.deposit(0, 100 ether, new bytes32[](0));

        vm.prank(admin);
        presale.finalizeSale(_defaultFinalizeParams());

        // Spot sale: finalized immediately after finalizeSale
        assertTrue(presale.isFinalized());
        assertTrue(presale.poolCreated());
    }
}
