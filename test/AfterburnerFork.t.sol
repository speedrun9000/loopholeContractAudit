// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {AfterburnerUpgradeable} from "../src/AfterburnerUpgradeable.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// baseline deps
import {BFactory} from "../src/interfaces/IBFactory.sol";
import {IBController} from "../src/interfaces/IBController.sol";
import {IBSwap} from "../src/interfaces/IBSwap.sol";
import {IBLens} from "../src/interfaces/IBLens.sol";

contract AfterburnerForkTest is Test {
    AfterburnerUpgradeable public burner;
    MockERC20 public reserveToken;

    address public owner = address(0x1);
    address public funder = address(0x2);
    address public feeRecipient = address(0x3);
    address public bToken;

    address baseline = address(0xf020C709fe9Ae902e3CDED1E50CA01021ce968E8); // latest sepolia base deployment (block 38018695)
    address baselineAdmin = address(0xe5393AA43106210e50CF8540Bab4F764079bE355);
    BFactory bFactory = BFactory(baseline);
    IBController bController = IBController(baseline);

    function setUp() public {
        vm.createSelectFork("https://sepolia.base.org", 38018750);

        // set up baseline bToken and reserve token
        reserveToken = new MockERC20("Reserve", "RSV", 18);
        vm.prank(baselineAdmin);
        bController.setReserveApproval(address(reserveToken), true);
        bToken = _createPool();

        // set up afterburner
        // Deploy implementation + proxy
        AfterburnerUpgradeable impl = new AfterburnerUpgradeable();
        bytes memory initData = abi.encodeCall(impl.initialize, (owner, bToken, address(reserveToken), baseline));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        burner = AfterburnerUpgradeable(address(proxy));

        // Authorize funder
        vm.prank(owner);
        burner.setAuthorizedFunder(funder, true);
    }

    function _createPool() internal returns (address bToken_) {
        bToken_ = address(bFactory.createBToken("Test", "TEST", 1_000_000 ether, bytes32(0)));
        reserveToken.mint(address(this), 200_000 ether);

        MockERC20(bToken_).approve(address(bFactory), 200_000 ether);
        reserveToken.approve(address(bFactory), 200_000 ether);

        BFactory.CreateParams memory createParams = BFactory.CreateParams({
            bToken: bToken_,
            initialPoolBTokens: 200_000 ether,
            reserve: address(reserveToken),
            initialPoolReserves: 200_000 ether,
            initialActivePrice: 1.1 ether,
            initialBLV: 0,
            creator: owner,
            feeRecipient: feeRecipient,
            creatorFeePct: 100,
            swapFeePct: 0.01 ether,
            createHook: false,
            claimMerkleRoot: bytes32(0),
            initialCollateral: 0,
            initialDebt: 0
        });

        bFactory.createPool(createParams);
    }

    function test_forked() public {
        uint256 funding = 100 ether;
        // fund the afterburner
        vm.startPrank(funder);
        reserveToken.mint(funder, funding);
        reserveToken.approve(address(burner), funding);
        burner.fund(funding);
        vm.stopPrank();

        // convert the reserve tokens to bTokens
        (uint256 amountOut,,) = IBSwap(baseline).quoteBuyExactIn(bToken, funding);
        vm.prank(owner);
        burner.swapAndStake(funding, amountOut);

        // get a leverage quote
        (uint256 total, uint256 locked,,) = IBLens(baseline).stakedPosition(bToken, address(burner));
        uint256 collateralIn = total - locked; // this is the max collateralIn value that can be used
        assert(collateralIn > 0); // sanity check we actually have some staked bTokens available
        (uint256 targetCollateral, uint256 maxSwapReservesIn, uint256 expectedDebt,) =
            IBLens(baseline).quoteLeverage(bToken, collateralIn, 1e18); // 1e18 == 100% leverage

        // execute leverage
        vm.prank(owner);
        burner.execute(targetCollateral, collateralIn, maxSwapReservesIn);

        // verify we used all of the available collateral
        (total, locked,,) = IBLens(baseline).stakedPosition(bToken, address(burner));
        assertEq(total - locked, 0); // we should have used all of the available collateral

        // verify we borrowed the expected amount
        (uint256 collateral, uint256 debt) = IBLens(baseline).creditAccount(bToken, address(burner));
        assertEq(collateral, targetCollateral);
        assertEq(debt, expectedDebt);
    }
}
