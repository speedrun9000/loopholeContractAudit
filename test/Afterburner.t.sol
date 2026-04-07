// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {AfterburnerUpgradeable} from "../src/AfterburnerUpgradeable.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @dev Mock baseline relay that implements IBCredit.leverage()
contract MockBaseline {
    MockERC20 public reserveToken;

    constructor(address _reserveToken) {
        reserveToken = MockERC20(_reserveToken);
    }

    function claim(address, address, bool) external returns (uint256) {
        return 0;
    }

    /// @dev Simulates leverage: pulls reserves from caller, returns values
    function leverage(address, uint256, uint256, uint256 _maxSwapReservesIn)
        external
        payable
        returns (uint256 debtAdded_)
    {
        debtAdded_ = _maxSwapReservesIn * 2; // Mock: debt = 2x reserves (leveraged)
    }
}

contract AfterburnerTest is Test {
    AfterburnerUpgradeable public burner;
    MockERC20 public reserveToken;
    MockBaseline public baseline;

    address public owner = address(0x1);
    address public funder = address(0x2);
    address public bToken = address(0xB1);

    function setUp() public {
        reserveToken = new MockERC20("Reserve", "RSV", 18);
        baseline = new MockBaseline(address(reserveToken));

        // Deploy implementation + proxy
        AfterburnerUpgradeable impl = new AfterburnerUpgradeable();
        bytes memory initData =
            abi.encodeCall(impl.initialize, (owner, bToken, address(reserveToken), address(baseline)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        burner = AfterburnerUpgradeable(address(proxy));

        // Authorize funder
        vm.prank(owner);
        burner.setAuthorizedFunder(funder, true);
    }

    /*//////////////////////////////////////////////////////////////
                         INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function test_InitializesCorrectly() public view {
        assertEq(burner.bToken(), bToken);
        assertEq(burner.reserveToken(), address(reserveToken));
        assertEq(burner.baseline(), address(baseline));
        assertEq(burner.owner(), owner);
    }

    /*//////////////////////////////////////////////////////////////
                         FUNDING
    //////////////////////////////////////////////////////////////*/

    function test_AuthorizedFunderCanFund() public {
        reserveToken.mint(funder, 10 ether);
        vm.startPrank(funder);
        reserveToken.approve(address(burner), 10 ether);
        burner.fund(10 ether);
        vm.stopPrank();

        assertEq(reserveToken.balanceOf(address(burner)), 10 ether);
    }

    function test_OwnerCanFund() public {
        reserveToken.mint(owner, 5 ether);
        vm.startPrank(owner);
        reserveToken.approve(address(burner), 5 ether);
        burner.fund(5 ether);
        vm.stopPrank();

        assertEq(reserveToken.balanceOf(address(burner)), 5 ether);
    }

    function test_UnauthorizedCannotFund() public {
        address rando = address(0xBEEF);
        reserveToken.mint(rando, 1 ether);

        vm.startPrank(rando);
        reserveToken.approve(address(burner), 1 ether);
        vm.expectRevert(AfterburnerUpgradeable.NotAuthorized.selector);
        burner.fund(1 ether);
        vm.stopPrank();
    }

    function test_FundRevertsOnZero() public {
        vm.prank(funder);
        vm.expectRevert(AfterburnerUpgradeable.ZeroAmount.selector);
        burner.fund(0);
    }

    /*//////////////////////////////////////////////////////////////
                         EXECUTE
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteCallsLeverageOnBaseline() public {
        // Fund the afterburner
        reserveToken.mint(address(burner), 5 ether);

        vm.prank(owner);
        burner.execute(10 ether, 5 ether, 5 ether);

        // Baseline should have received the reserves
        // @afkbyte baseline will no longer do any token transfer during leverage
        //assertEq(reserveToken.balanceOf(address(baseline)), 5 ether);
        //assertEq(reserveToken.balanceOf(address(burner)), 0);
    }

    function test_ExecuteRevertsWhenBaselineNotSet() public {
        // Deploy a fresh burner without baseline
        AfterburnerUpgradeable impl = new AfterburnerUpgradeable();
        bytes memory initData = abi.encodeCall(impl.initialize, (owner, bToken, address(reserveToken), address(0)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        AfterburnerUpgradeable freshBurner = AfterburnerUpgradeable(address(proxy));

        vm.prank(owner);
        vm.expectRevert(AfterburnerUpgradeable.BaselineNotSet.selector);
        freshBurner.execute(10 ether, 5 ether, 5 ether);
    }

    function test_ExecuteRevertsForNonOwner() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        burner.execute(10 ether, 5 ether, 5 ether);
    }

    function test_ExecuteRevertsOnZeroCollateral() public {
        vm.prank(owner);
        vm.expectRevert(AfterburnerUpgradeable.ZeroAmount.selector);
        burner.execute(0, 5 ether, 5 ether);
    }

    /*//////////////////////////////////////////////////////////////
                         ADMIN
    //////////////////////////////////////////////////////////////*/

    function test_SetBaseline() public {
        address newBaseline = address(0xBBBB);
        vm.prank(owner);
        burner.setBaseline(newBaseline);
        assertEq(burner.baseline(), newBaseline);
    }

    function test_SetFunder() public {
        address newFunder = address(0xCCCC);

        vm.prank(owner);
        burner.setAuthorizedFunder(newFunder, true);
        assertTrue(burner.authorizedFunders(newFunder));

        vm.prank(owner);
        burner.setAuthorizedFunder(newFunder, false);
        assertFalse(burner.authorizedFunders(newFunder));
    }

    function test_OnlyOwnerCanSetBaseline() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        burner.setBaseline(address(0xBBBB));
    }

    /*//////////////////////////////////////////////////////////////
                         UPGRADE
    //////////////////////////////////////////////////////////////*/

    function test_UpgradePreservesState() public {
        // Fund
        reserveToken.mint(address(burner), 3 ether);

        // Upgrade
        AfterburnerUpgradeable newImpl = new AfterburnerUpgradeable();
        vm.prank(owner);
        burner.upgradeToAndCall(address(newImpl), "");

        // State preserved
        assertEq(burner.bToken(), bToken);
        assertEq(burner.baseline(), address(baseline));
        assertEq(reserveToken.balanceOf(address(burner)), 3 ether);
    }
}
