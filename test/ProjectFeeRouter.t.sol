// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {ProjectFeeRouterUpgradeable} from "../src/ProjectFeeRouterUpgradeable.sol";
import {BTokenFeeForwarder} from "../src/BTokenFeeForwarder.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @dev Mock that accepts informOfFeeDistribution calls (needed because the router calls this on treasury)
contract MockFeeRecipient {
    function informOfFeeDistribution(address, uint256) external {}
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

    BTokenFeeForwarder public lstForwarder;
    BTokenFeeForwarder public loopForwarder;

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

        lstForwarder = BTokenFeeForwarder(router.registerBToken(lstBToken, address(reserveToken)));
        loopForwarder = BTokenFeeForwarder(router.registerBToken(loopBToken, address(reserveToken)));

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

    /// @dev Simulate a pool depositing creator fees to the bToken's forwarder, then push them.
    function _depositAndFlush(BTokenFeeForwarder forwarder, uint256 amount) internal {
        reserveToken.mint(address(forwarder), amount);
        forwarder.flush();
    }

    /*//////////////////////////////////////////////////////////////
                         LST SPLIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_LST_SweepSplits6667_3333() public {
        uint256 feeAmount = 3 ether; // Simulates 3% creator stream from a 4% total fee

        _depositAndFlush(lstForwarder, feeAmount);

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
        uint256 feeAmount = 10_000e18;
        _depositAndFlush(lstForwarder, feeAmount);

        router.sweep(lstBToken);

        assertEq(reserveToken.balanceOf(treasury), 6667e18); // 6667/10000
        assertEq(reserveToken.balanceOf(royalties), 3333e18); // 3333/10000
    }

    /*//////////////////////////////////////////////////////////////
                         LOOP SPLIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_LOOP_SweepAllToTeam() public {
        uint256 feeAmount = 1 ether;
        _depositAndFlush(loopForwarder, feeAmount);

        router.sweep(loopBToken);

        assertEq(reserveToken.balanceOf(team), feeAmount);
    }

    function test_LOOP_SweepExactMath() public {
        uint256 feeAmount = 777e18;
        _depositAndFlush(loopForwarder, feeAmount);

        router.sweep(loopBToken);

        assertEq(reserveToken.balanceOf(team), feeAmount);
    }

    /*//////////////////////////////////////////////////////////////
                       ROUNDING / REMAINDER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RemainderGoesToTreasuryWhenSet() public {
        _depositAndFlush(lstForwarder, 1);

        router.sweep(lstBToken);

        // 6667/10000 * 1 = 0, 3333/10000 * 1 = 0, remainder = 1 → treasury (set)
        assertEq(reserveToken.balanceOf(treasury), 1);
        assertEq(reserveToken.balanceOf(royalties), 0);
    }

    function test_RemainderGoesToTeamWhenNoTreasury() public {
        _depositAndFlush(loopForwarder, 3);

        router.sweep(loopBToken);

        assertEq(reserveToken.balanceOf(team), 3);
    }

    function test_SumOfTransfersNeverExceedsDelta() public {
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 1;
        amounts[1] = 7;
        amounts[2] = 999;
        amounts[3] = 1e18 + 1;
        amounts[4] = type(uint128).max;

        for (uint256 i = 0; i < amounts.length; i++) {
            // Reset by deploying fresh
            MockERC20 freshToken = new MockERC20("Fresh", "F", 18);
            ProjectFeeRouterUpgradeable impl = new ProjectFeeRouterUpgradeable();
            bytes memory initData = abi.encodeCall(impl.initialize, (owner));
            ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
            ProjectFeeRouterUpgradeable freshRouter = ProjectFeeRouterUpgradeable(address(proxy));

            vm.startPrank(owner);
            address forwarder = freshRouter.registerBToken(lstBToken, address(freshToken));
            freshRouter.setConfig(
                lstBToken,
                ProjectFeeRouterUpgradeable.FeeConfig(6667, 3333, 0, 0, 0),
                ProjectFeeRouterUpgradeable.Recipients(treasury, royalties, address(0), address(0), address(0))
            );
            vm.stopPrank();

            freshToken.mint(forwarder, amounts[i]);
            BTokenFeeForwarder(forwarder).flush();
            freshRouter.sweep(lstBToken);

            // Router holds nothing (everything distributed); forwarder is empty.
            assertEq(freshToken.balanceOf(address(freshRouter)), 0);
            assertEq(freshToken.balanceOf(forwarder), 0);
        }
    }

    /*//////////////////////////////////////////////////////////////
                       MULTIPLE SWEEPS
    //////////////////////////////////////////////////////////////*/

    function test_MultipleSweepsAccumulateCorrectly() public {
        _depositAndFlush(lstForwarder, 1 ether);
        router.sweep(lstBToken);

        uint256 treasuryAfterFirst = reserveToken.balanceOf(treasury);
        uint256 royaltiesAfterFirst = reserveToken.balanceOf(royalties);

        _depositAndFlush(lstForwarder, 2 ether);
        router.sweep(lstBToken);

        uint256 expectedTreasury2 = (2 ether * 6667) / 10_000;
        uint256 expectedRoyalties2 = (2 ether * 3333) / 10_000;
        uint256 remainder2 = 2 ether - expectedTreasury2 - expectedRoyalties2;

        assertEq(reserveToken.balanceOf(treasury), treasuryAfterFirst + expectedTreasury2 + remainder2);
        assertEq(reserveToken.balanceOf(royalties), royaltiesAfterFirst + expectedRoyalties2);
    }

    function test_MultipleFlushesBeforeSweep_AccumulateAccrued() public {
        _depositAndFlush(lstForwarder, 1 ether);
        _depositAndFlush(lstForwarder, 2 ether);
        // accrued[lstBToken] should be 3 ether at this point
        assertEq(router.accrued(lstBToken), 3 ether);

        router.sweep(lstBToken);

        uint256 expectedTreasury = (3 ether * 6667) / 10_000;
        uint256 expectedRoyalties = (3 ether * 3333) / 10_000;
        uint256 remainder = 3 ether - expectedTreasury - expectedRoyalties;
        assertEq(reserveToken.balanceOf(treasury), expectedTreasury + remainder);
        assertEq(reserveToken.balanceOf(royalties), expectedRoyalties);
        assertEq(router.accrued(lstBToken), 0);
    }

    function test_SweepRevertsWhenNothingNew() public {
        vm.expectRevert(ProjectFeeRouterUpgradeable.NothingToSweep.selector);
        router.sweep(lstBToken);
    }

    /*//////////////////////////////////////////////////////////////
              CROSS-BTOKEN SEGREGATION (audit regression)
    //////////////////////////////////////////////////////////////*/

    /// @notice Audit PoC inverted: with per-bToken forwarders, fees for one bToken
    ///         can no longer be swept under another bToken's config even when both
    ///         share the same reserve token.
    function test_FeesSegregatedAcrossBTokensSharingReserve() public {
        assertEq(reserveToken.balanceOf(treasury), 0);
        assertEq(reserveToken.balanceOf(royalties), 0);
        assertEq(reserveToken.balanceOf(team), 0);
        assertEq(router.reserve(loopBToken), router.reserve(lstBToken), "reserve token shared");

        // Fees accrue for both bTokens — but to distinct addresses now.
        uint256 lstFees = 1 ether;
        uint256 loopFees = 2 ether;
        _depositAndFlush(lstForwarder, lstFees);
        _depositAndFlush(loopForwarder, loopFees);

        // LST sweep gets exactly LST's fees, not the combined pot.
        router.sweep(lstBToken);
        uint256 lstTreasury = (lstFees * 6667) / 10_000;
        uint256 lstRoyalties = (lstFees * 3333) / 10_000;
        uint256 lstRemainder = lstFees - lstTreasury - lstRoyalties;
        assertEq(reserveToken.balanceOf(treasury), lstTreasury + lstRemainder, "LST treasury exact");
        assertEq(reserveToken.balanceOf(royalties), lstRoyalties, "LST royalties exact");

        // LOOP sweep still works and gets LOOP's fees.
        router.sweep(loopBToken);
        assertEq(reserveToken.balanceOf(team), loopFees, "LOOP team exact");
    }

    /*//////////////////////////////////////////////////////////////
                       FORWARDER / RECEIVE FEES
    //////////////////////////////////////////////////////////////*/

    function test_ReceiveFees_RevertsForNonForwarder() public {
        vm.expectRevert(ProjectFeeRouterUpgradeable.OnlyForwarder.selector);
        vm.prank(address(0xBAD));
        router.receiveFees(lstBToken, 1 ether);
    }

    function test_ReceiveFees_RevertsForWrongBToken() public {
        // The LOOP forwarder cannot credit LST: msg.sender check fails since
        // forwarderOf[lstBToken] != address(loopForwarder).
        reserveToken.mint(address(loopForwarder), 1 ether);
        vm.prank(address(loopForwarder));
        vm.expectRevert(ProjectFeeRouterUpgradeable.OnlyForwarder.selector);
        router.receiveFees(lstBToken, 1 ether);
    }

    function test_Forwarder_FlushRevertsAtZeroBalance() public {
        vm.expectRevert(BTokenFeeForwarder.NothingToFlush.selector);
        lstForwarder.flush();
    }

    function test_Register_RevertsOnSecondRegister() public {
        vm.prank(owner);
        vm.expectRevert(ProjectFeeRouterUpgradeable.BTokenAlreadyRegistered.selector);
        router.registerBToken(lstBToken, address(reserveToken));
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
        _depositAndFlush(lstForwarder, 1 ether);

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
        _depositAndFlush(lstForwarder, 1 ether);

        // Upgrade to new implementation
        ProjectFeeRouterUpgradeable newImpl = new ProjectFeeRouterUpgradeable();
        vm.prank(owner);
        router.upgradeToAndCall(address(newImpl), "");

        // accrued and forwarderOf should survive — sweep still works.
        assertEq(router.accrued(lstBToken), 1 ether);
        assertEq(router.forwarderOf(lstBToken), address(lstForwarder));
        router.sweep(lstBToken);
        assertTrue(reserveToken.balanceOf(treasury) > 0);
    }

    /*//////////////////////////////////////////////////////////////
                       FIVE-WAY SPLIT TEST
    //////////////////////////////////////////////////////////////*/

    function test_FiveWaySplit() public {
        address newBToken = address(0xA3);

        vm.startPrank(owner);
        address newForwarder = router.registerBToken(newBToken, address(reserveToken));
        router.setConfig(
            newBToken,
            ProjectFeeRouterUpgradeable.FeeConfig(2000, 2000, 2000, 2000, 2000),
            ProjectFeeRouterUpgradeable.Recipients(treasury, royalties, team, afterburner, blvModule)
        );
        vm.stopPrank();

        uint256 feeAmount = 10_000e18;
        reserveToken.mint(newForwarder, feeAmount);
        BTokenFeeForwarder(newForwarder).flush();

        router.sweep(newBToken);

        assertEq(reserveToken.balanceOf(treasury), 2000e18);
        assertEq(reserveToken.balanceOf(royalties), 2000e18);
        assertEq(reserveToken.balanceOf(team), 2000e18);
        assertEq(reserveToken.balanceOf(afterburner), 2000e18);
        assertEq(reserveToken.balanceOf(blvModule), 2000e18);
    }
}
