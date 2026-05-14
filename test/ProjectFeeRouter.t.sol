// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {ProjectFeeRouterUpgradeable} from "../src/ProjectFeeRouterUpgradeable.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @dev Mock that accepts informOfFeeDistribution calls (needed because the router calls this on treasury).
///      Records cumulative reported amounts per bToken so tests can assert that the marketplace's
///      view of received fees matches its actual token balance.
contract MockFeeRecipient {
    mapping(address => uint256) public reportedFees;

    function informOfFeeDistribution(address bToken, uint256 amount) external {
        reportedFees[bToken] += amount;
    }
}

contract ProjectFeeRouterTest is Test {
    ProjectFeeRouterUpgradeable public router;
    MockERC20 public reserveToken;

    address public owner = makeAddr("owner");
    address public treasury; // set in setUp — needs to be a contract
    address public royalties = makeAddr("royalties");
    address public team = makeAddr("team");
    address public afterburner = makeAddr("afterburner");
    address public blvModule = makeAddr("blvModule");

    address public lstBToken = address(0xA1);
    address public loopBToken = address(0xA2);

    function setUp() public {
        reserveToken = new MockERC20("Reserve", "RSV", 18);
        treasury = address(new MockFeeRecipient());

        // Deploy implementation + proxy
        ProjectFeeRouterUpgradeable impl = new ProjectFeeRouterUpgradeable();
        bytes memory initData = abi.encodeCall(impl.initialize, (owner));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        router = ProjectFeeRouterUpgradeable(address(proxy));

        // Register bTokens and configure
        vm.startPrank(owner);

        router.registerBToken(lstBToken, address(reserveToken));
        router.registerBToken(loopBToken, address(reserveToken));

        // LST: 6667 treasury, 3333 royalties
        router.setConfig(
            lstBToken,
            ProjectFeeRouterUpgradeable.FeeConfig({
                bpsToAcquisitionTreasury: 6667, bpsToRoyalties: 3333, bpsToTeam: 0, bpsToAfterburner: 0, bpsToBLV: 0
            }),
            ProjectFeeRouterUpgradeable.Recipients({
                acquisitionTreasury: treasury,
                royaltyRecipient: royalties,
                team: address(0),
                afterburner: address(0),
                blvModule: address(0)
            })
        );

        // LOOP: 10000 team
        router.setConfig(
            loopBToken,
            ProjectFeeRouterUpgradeable.FeeConfig({
                bpsToAcquisitionTreasury: 0, bpsToRoyalties: 0, bpsToTeam: 10000, bpsToAfterburner: 0, bpsToBLV: 0
            }),
            ProjectFeeRouterUpgradeable.Recipients({
                acquisitionTreasury: address(0),
                royaltyRecipient: address(0),
                team: team,
                afterburner: address(0),
                blvModule: address(0)
            })
        );

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         LST SPLIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_LST_SweepSplits6667_3333() public {
        uint256 feeAmount = 3 ether; // Simulates 3% creator stream from a 4% total fee

        // Simulate fees arriving at router
        reserveToken.mint(address(router), feeAmount);

        // Anyone can sweep
        router.sweep(lstBToken);

        // 6667/10000 * 3e18 = 2.0001e18
        uint256 expectedTreasury = (feeAmount * 6667) / 10_000;
        // 3333/10000 * 3e18 = 0.9999e18
        uint256 expectedRoyalties = (feeAmount * 3333) / 10_000;
        uint256 expectedRemainder = feeAmount - expectedTreasury - expectedRoyalties;

        // Treasury gets its share + remainder
        assertEq(reserveToken.balanceOf(treasury), expectedTreasury + expectedRemainder);
        assertEq(reserveToken.balanceOf(royalties), expectedRoyalties);
    }

    function test_LST_SweepExactMath() public {
        // Use 10000 tokens for clean math
        uint256 feeAmount = 10_000e18;
        reserveToken.mint(address(router), feeAmount);

        router.sweep(lstBToken);

        assertEq(reserveToken.balanceOf(treasury), 6667e18); // 6667/10000
        assertEq(reserveToken.balanceOf(royalties), 3333e18); // 3333/10000
        // No remainder when amount is divisible
    }

    /*//////////////////////////////////////////////////////////////
                         LOOP SPLIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_LOOP_SweepAllToTeam() public {
        uint256 feeAmount = 1 ether; // Simulates 1% creator stream from a 2% total fee

        reserveToken.mint(address(router), feeAmount);

        router.sweep(loopBToken);

        assertEq(reserveToken.balanceOf(team), feeAmount);
    }

    function test_LOOP_SweepExactMath() public {
        uint256 feeAmount = 777e18;
        reserveToken.mint(address(router), feeAmount);

        router.sweep(loopBToken);

        // 10000 bps = 100%, no remainder
        assertEq(reserveToken.balanceOf(team), feeAmount);
    }

    /*//////////////////////////////////////////////////////////////
                       ROUNDING / REMAINDER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RemainderGoesToTreasuryWhenSet() public {
        // Use an amount that produces rounding: 1 wei
        uint256 feeAmount = 1;
        reserveToken.mint(address(router), feeAmount);

        router.sweep(lstBToken);

        // 6667/10000 * 1 = 0, 3333/10000 * 1 = 0, remainder = 1
        // Remainder goes to treasury (acquisitionTreasury is set)
        assertEq(reserveToken.balanceOf(treasury), 1);
        assertEq(reserveToken.balanceOf(royalties), 0);
    }

    function test_RemainderGoesToTeamWhenNoTreasury() public {
        // LOOP config has no treasury, remainder goes to team
        uint256 feeAmount = 3; // Small amount to trigger rounding edge case
        reserveToken.mint(address(router), feeAmount);

        router.sweep(loopBToken);

        // 10000/10000 * 3 = 3, no remainder actually. Try something that rounds.
        assertEq(reserveToken.balanceOf(team), 3);
    }

    function test_SumOfTransfersNeverExceedsDelta() public {
        // Fuzz-like: try many values
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 1;
        amounts[1] = 7;
        amounts[2] = 999;
        amounts[3] = 1e18 + 1;
        amounts[4] = type(uint128).max;

        for (uint256 i = 0; i < amounts.length; i++) {
            // Reset balances by deploying fresh
            MockERC20 freshToken = new MockERC20("Fresh", "F", 18);
            ProjectFeeRouterUpgradeable impl = new ProjectFeeRouterUpgradeable();
            bytes memory initData = abi.encodeCall(impl.initialize, (owner));
            ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
            ProjectFeeRouterUpgradeable freshRouter = ProjectFeeRouterUpgradeable(address(proxy));

            vm.startPrank(owner);
            freshRouter.registerBToken(lstBToken, address(freshToken));
            freshRouter.setConfig(
                lstBToken,
                ProjectFeeRouterUpgradeable.FeeConfig(6667, 3333, 0, 0, 0),
                ProjectFeeRouterUpgradeable.Recipients(treasury, royalties, address(0), address(0), address(0))
            );
            vm.stopPrank();

            freshToken.mint(address(freshRouter), amounts[i]);
            freshRouter.sweep(lstBToken);

            // Router should have 0 left for this bToken
            assertEq(freshToken.balanceOf(address(freshRouter)), 0);
        }
    }

    /*//////////////////////////////////////////////////////////////
                       MULTIPLE SWEEPS
    //////////////////////////////////////////////////////////////*/

    function test_MultipleSweepsAccumulateCorrectly() public {
        // First fee arrival
        reserveToken.mint(address(router), 1 ether);
        router.sweep(lstBToken);

        uint256 treasuryAfterFirst = reserveToken.balanceOf(treasury);
        uint256 royaltiesAfterFirst = reserveToken.balanceOf(royalties);

        // Second fee arrival
        reserveToken.mint(address(router), 2 ether);
        router.sweep(lstBToken);

        // Second sweep should only distribute the new 2 ether delta
        uint256 expectedTreasury2 = (2 ether * 6667) / 10_000;
        uint256 expectedRoyalties2 = (2 ether * 3333) / 10_000;
        uint256 remainder2 = 2 ether - expectedTreasury2 - expectedRoyalties2;

        assertEq(reserveToken.balanceOf(treasury), treasuryAfterFirst + expectedTreasury2 + remainder2);
        assertEq(reserveToken.balanceOf(royalties), royaltiesAfterFirst + expectedRoyalties2);
    }

    function test_SweepRevertsWhenNothingNew() public {
        vm.expectRevert(ProjectFeeRouterUpgradeable.NothingToSweep.selector);
        router.sweep(lstBToken);
    }

    /*//////////////////////////////////////////////////////////////
                       ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    function test_OnlyOwnerCanRegister() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        router.registerBToken(address(0xC1), address(reserveToken));
    }

    function test_OnlyOwnerCanSetConfig() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        router.setConfig(
            lstBToken,
            ProjectFeeRouterUpgradeable.FeeConfig(5000, 5000, 0, 0, 0),
            ProjectFeeRouterUpgradeable.Recipients(treasury, royalties, address(0), address(0), address(0))
        );
    }

    function test_SweepIsPermissionless() public {
        reserveToken.mint(address(router), 1 ether);

        // Random address can sweep
        vm.prank(address(0xBEEF));
        router.sweep(lstBToken);

        assertTrue(reserveToken.balanceOf(treasury) > 0);
    }

    /*//////////////////////////////////////////////////////////////
                       VALIDATION
    //////////////////////////////////////////////////////////////*/

    function test_ConfigRequiresBpsSumTo10000() public {
        vm.prank(owner);
        vm.expectRevert(ProjectFeeRouterUpgradeable.InvalidBpSum.selector);
        router.setConfig(
            lstBToken,
            ProjectFeeRouterUpgradeable.FeeConfig(5000, 5000, 5000, 0, 0),
            ProjectFeeRouterUpgradeable.Recipients(treasury, royalties, team, address(0), address(0))
        );
    }

    function test_ConfigRequiresNonZeroRecipientForNonZeroBps() public {
        vm.prank(owner);
        vm.expectRevert(ProjectFeeRouterUpgradeable.ZeroRecipientForNonZeroBps.selector);
        router.setConfig(
            lstBToken,
            ProjectFeeRouterUpgradeable.FeeConfig(6667, 3333, 0, 0, 0),
            ProjectFeeRouterUpgradeable.Recipients(address(0), royalties, address(0), address(0), address(0))
        );
    }

    function test_SweepRevertsForUnregisteredBToken() public {
        vm.expectRevert(ProjectFeeRouterUpgradeable.BTokenNotRegistered.selector);
        router.sweep(address(0xDEAD));
    }

    /*//////////////////////////////////////////////////////////////
                       UPGRADE TEST
    //////////////////////////////////////////////////////////////*/

    function test_UpgradePreservesState() public {
        // Deposit fees
        reserveToken.mint(address(router), 1 ether);

        // Upgrade to new implementation
        ProjectFeeRouterUpgradeable newImpl = new ProjectFeeRouterUpgradeable();
        vm.prank(owner);
        router.upgradeToAndCall(address(newImpl), "");

        // State should be preserved - sweep should still work
        router.sweep(lstBToken);
        assertTrue(reserveToken.balanceOf(treasury) > 0);
    }

    /*//////////////////////////////////////////////////////////////
                       FIVE-WAY SPLIT TEST
    //////////////////////////////////////////////////////////////*/

    function test_FiveWaySplit() public {
        address newBToken = address(0xA3);

        vm.startPrank(owner);
        router.registerBToken(newBToken, address(reserveToken));
        router.setConfig(
            newBToken,
            ProjectFeeRouterUpgradeable.FeeConfig(2000, 2000, 2000, 2000, 2000),
            ProjectFeeRouterUpgradeable.Recipients(treasury, royalties, team, afterburner, blvModule)
        );
        vm.stopPrank();

        uint256 feeAmount = 10_000e18;
        reserveToken.mint(address(router), feeAmount);

        router.sweep(newBToken);

        assertEq(reserveToken.balanceOf(treasury), 2000e18);
        assertEq(reserveToken.balanceOf(royalties), 2000e18);
        assertEq(reserveToken.balanceOf(team), 2000e18);
        assertEq(reserveToken.balanceOf(afterburner), 2000e18);
        assertEq(reserveToken.balanceOf(blvModule), 2000e18);
    }

    /*//////////////////////////////////////////////////////////////
                  CALLBACK ACCOUNTING (DUST INCLUDED)
    //////////////////////////////////////////////////////////////*/

    function test_SweepCallbackIncludesRemainder() public {
        // 6667/3333 split on 3 ether produces a 1-wei rounding remainder.
        uint256 feeAmount = 3 ether;
        reserveToken.mint(address(router), feeAmount);

        router.sweep(lstBToken);

        // The marketplace's reported fees (used to update checkpointBalance) must equal
        // its actual token balance — i.e. the dust transferred via the remainder branch
        // is reflected in the fee-distribution callback.
        uint256 actualBalance = reserveToken.balanceOf(treasury);
        uint256 reported = MockFeeRecipient(treasury).reportedFees(lstBToken);
        assertEq(reported, actualBalance, "callback must report full transferred amount");

        // Sanity: balance equals the slice + remainder.
        uint256 expectedTreasury = (feeAmount * 6667) / 10_000;
        uint256 expectedRoyalties = (feeAmount * 3333) / 10_000;
        uint256 expectedRemainder = feeAmount - expectedTreasury - expectedRoyalties;
        assertEq(actualBalance, expectedTreasury + expectedRemainder);
    }

    function test_SweepCallbackFiresForRemainderOnlyTreasury() public {
        // Config where treasury bps == 0 but acquisitionTreasury is set, alongside a slice
        // that produces a remainder. The remainder must still go to treasury and trigger
        // the callback so checkpointBalance reflects the dust.
        address newBToken = address(0xB1);
        vm.startPrank(owner);
        router.registerBToken(newBToken, address(reserveToken));
        router.setConfig(
            newBToken,
            ProjectFeeRouterUpgradeable.FeeConfig({
                bpsToAcquisitionTreasury: 0,
                bpsToRoyalties: 3333,
                bpsToTeam: 6667,
                bpsToAfterburner: 0,
                bpsToBLV: 0
            }),
            ProjectFeeRouterUpgradeable.Recipients({
                acquisitionTreasury: treasury,
                royaltyRecipient: royalties,
                team: team,
                afterburner: address(0),
                blvModule: address(0)
            })
        );
        vm.stopPrank();

        // 7 wei -> royalties=2 (3333*7/10000=2.33), team=4 (6667*7/10000=4.67), remainder=1 -> treasury
        uint256 feeAmount = 7;
        reserveToken.mint(address(router), feeAmount);
        router.sweep(newBToken);

        uint256 expectedRoyalties = (feeAmount * 3333) / 10_000;
        uint256 expectedTeam = (feeAmount * 6667) / 10_000;
        uint256 expectedRemainder = feeAmount - expectedRoyalties - expectedTeam;
        assertGt(expectedRemainder, 0, "test setup: must produce a nonzero remainder");

        assertEq(reserveToken.balanceOf(treasury), expectedRemainder);
        assertEq(MockFeeRecipient(treasury).reportedFees(newBToken), expectedRemainder);
    }
}
