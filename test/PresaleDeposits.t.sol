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

contract PresaleDepositTest is Test {
    PresaleFactory public factory;
    PresaleImplementation public implementation;
    MockBFactory public bFactory;
    MockERC20 public presaleToken;
    UpgradeableBeacon public beacon;
    PresaleImplementation public presale;

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public admin = address(0x3);

    function setUp() public {
        bFactory = new MockBFactory();
        presaleToken = new MockERC20("Presale Token", "PRESALE", 18);
        implementation = new PresaleImplementation();
        beacon = new UpgradeableBeacon(address(implementation), owner);
        PresaleFactory factoryImpl = new PresaleFactory();
        ERC1967Proxy factoryProxy = new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeCall(factoryImpl.initialize, (beacon, bFactory, owner))
        );
        factory = PresaleFactory(address(factoryProxy));

        // Deploy a presale with 1 phase
        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](1);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp,
            endTime: block.timestamp + 7 days,
            totalPhaseCap: 100 ether,
            userAllocationCap: 10 ether,
            merkleRoot: bytes32(0) // No whitelist
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
            initialDebt: 0
        });

        address presaleAddr = factory.deployPresale(phases, config, bFactoryParams, address(presaleToken));
        presale = PresaleImplementation(payable(presaleAddr));

        // Mint tokens to users
        presaleToken.mint(user1, 1000 ether);
        presaleToken.mint(user2, 1000 ether);

        // Approve presale contract to spend users' tokens
        vm.prank(user1);
        presaleToken.approve(address(presale), type(uint256).max);
        vm.prank(user2);
        presaleToken.approve(address(presale), type(uint256).max);
    }

    function test_SingleDeposit() public {
        vm.prank(user1);
        presale.deposit(0, 5 ether, new bytes32[](0));

        assertEq(presale.getUserDepositedAmount(user1, 0), 5 ether);
        assertEq(presale.getTotalRaised(), 5 ether);
        assertEq(presale.getUserRemainingAllocation(user1, 0), 5 ether);
    }

    function test_MultipleDeposits() public {
        // First deposit
        vm.prank(user1);
        presale.deposit(0, 3 ether, new bytes32[](0));

        assertEq(presale.getUserDepositedAmount(user1, 0), 3 ether);
        assertEq(presale.getUserRemainingAllocation(user1, 0), 7 ether);

        // Second deposit
        vm.prank(user1);
        presale.deposit(0, 4 ether, new bytes32[](0));

        assertEq(presale.getUserDepositedAmount(user1, 0), 7 ether);
        assertEq(presale.getUserRemainingAllocation(user1, 0), 3 ether);

        // Third deposit
        vm.prank(user1);
        presale.deposit(0, 3 ether, new bytes32[](0));

        assertEq(presale.getUserDepositedAmount(user1, 0), 10 ether);
        assertEq(presale.getUserRemainingAllocation(user1, 0), 0);
        assertEq(presale.getTotalRaised(), 10 ether);
    }

    function test_MultipleDeposits_ExceedAllocation() public {
        // Deposit up to cap
        vm.prank(user1);
        presale.deposit(0, 8 ether, new bytes32[](0));

        // Try to exceed allocation
        vm.prank(user1);
        vm.expectRevert(IPresale.UserAllocationExceeded.selector);
        presale.deposit(0, 3 ether, new bytes32[](0));
    }

    function test_MultipleUsers() public {
        // User1 deposits
        vm.prank(user1);
        presale.deposit(0, 6 ether, new bytes32[](0));

        // User2 deposits
        vm.prank(user2);
        presale.deposit(0, 7 ether, new bytes32[](0));

        assertEq(presale.getUserDepositedAmount(user1, 0), 6 ether);
        assertEq(presale.getUserDepositedAmount(user2, 0), 7 ether);
        assertEq(presale.getTotalRaised(), 13 ether);
    }

    function test_DepositExceedsPhaseCap() public {
        // User1 deposits 10 ether
        vm.prank(user1);
        presale.deposit(0, 10 ether, new bytes32[](0));

        // User2 deposits 10 ether
        vm.prank(user2);
        presale.deposit(0, 10 ether, new bytes32[](0));

        // Deploy another presale to fill more
        for (uint256 i = 0; i < 8; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            address user = address(uint160(0x100 + i));
            presaleToken.mint(user, 100 ether);
            vm.prank(user);
            presaleToken.approve(address(presale), type(uint256).max);
            vm.prank(user);
            presale.deposit(0, 10 ether, new bytes32[](0));
        }

        // Total should be 100 ether (phase cap reached)
        assertEq(presale.getTotalRaised(), 100 ether);

        // Next deposit should fail
        address extraUser = address(0x999);
        presaleToken.mint(extraUser, 100 ether);
        vm.prank(extraUser);
        presaleToken.approve(address(presale), type(uint256).max);
        vm.prank(extraUser);
        vm.expectRevert(IPresale.PhaseCapExceeded.selector);
        presale.deposit(0, 1 ether, new bytes32[](0));
    }

    function test_DepositBeforePhaseStart() public {
        // Deploy presale with future start time
        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](1);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp + 1 days,
            endTime: block.timestamp + 7 days,
            totalPhaseCap: 100 ether,
            userAllocationCap: 10 ether,
            merkleRoot: bytes32(0)
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
            initialDebt: 0
        });

        address presaleAddr = factory.deployPresale(phases, config, bFactoryParams, address(presaleToken));
        PresaleImplementation futurePresale = PresaleImplementation(payable(presaleAddr));

        // Try to deposit before phase starts
        vm.prank(user1);
        vm.expectRevert(IPresale.PhaseNotActive.selector);
        futurePresale.deposit(0, 5 ether, new bytes32[](0));
    }

    function test_DepositAfterPhaseEnd() public {
        // Warp to after phase end
        vm.warp(block.timestamp + 8 days);

        // Try to deposit
        vm.prank(user1);
        vm.expectRevert(IPresale.PhaseNotActive.selector);
        presale.deposit(0, 5 ether, new bytes32[](0));
    }

    function test_DepositZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(IPresale.InvalidAmount.selector);
        presale.deposit(0, 0, new bytes32[](0));
    }

    function test_DepositInvalidPhase() public {
        vm.prank(user1);
        vm.expectRevert(IPresale.InvalidPhaseId.selector);
        presale.deposit(1, 5 ether, new bytes32[](0)); // Phase 1 doesn't exist
    }

    function testFuzz_MultipleDepositsSingleUser(uint256 deposit1, uint256 deposit2, uint256 deposit3) public {
        // Bound deposits to reasonable values
        deposit1 = bound(deposit1, 0.1 ether, 3 ether);
        deposit2 = bound(deposit2, 0.1 ether, 3 ether);
        deposit3 = bound(deposit3, 0.1 ether, 4 ether);

        // Calculate total
        uint256 total = deposit1 + deposit2 + deposit3;

        vm.startPrank(user1);
        presale.deposit(0, deposit1, new bytes32[](0));
        presale.deposit(0, deposit2, new bytes32[](0));
        presale.deposit(0, deposit3, new bytes32[](0));
        vm.stopPrank();

        assertEq(presale.getUserDepositedAmount(user1, 0), total);
        assertEq(presale.getTotalRaised(), total);
    }
}
