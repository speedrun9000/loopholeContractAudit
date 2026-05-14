// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {PresaleFactory} from "../src/PresaleFactory.sol";
import {PresaleImplementation} from "../src/PresaleImplementation.sol";
import {IPresale} from "../src/interfaces/IPresale.sol";
import {BFactory} from "../src/interfaces/IBFactory.sol";
import {MockBFactory} from "./mocks/MockBFactory.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PresaleFactoryTest is Test {
    PresaleFactory public factory;
    PresaleImplementation public implementation;
    MockBFactory public bFactory;
    MockERC20 public presaleToken;
    UpgradeableBeacon public beacon;

    address public deployer = address(this);
    address public user1 = address(0x1);
    address public admin = address(0x2);

    function setUp() public {
        // Deploy mock BFactory
        bFactory = new MockBFactory();

        // Deploy mock presale token
        presaleToken = new MockERC20("Presale Token", "PRESALE", 18);

        // Deploy implementation
        implementation = new PresaleImplementation();

        // Deploy beacon pointing to implementation
        beacon = new UpgradeableBeacon(address(implementation), admin);

        // Deploy factory with beacon, bFactory, and admin
        PresaleFactory factoryImpl = new PresaleFactory();
        ERC1967Proxy factoryProxy = new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeCall(factoryImpl.initialize, (beacon, bFactory, admin))
        );
        factory = PresaleFactory(address(factoryProxy));
    }

    function test_Constructor() public view {
        // Verify beacon is set correctly
        assertEq(factory.getBeacon(), address(beacon));

        // Verify implementation through beacon
        assertEq(factory.getImplementation(), address(implementation));
        assertEq(beacon.implementation(), address(implementation));

        // Verify BFactory address
        assertEq(factory.getBFactoryAddress(), address(bFactory));

        // Verify owner
        assertEq(factory.owner(), admin);

        // Verify initial presale count is zero
        assertEq(factory.getPresaleCount(), 0);
    }

    function test_DeployPresale() public {
        // Create phase configurations
        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](2);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp + 1 days,
            endTime: block.timestamp + 2 days,
            totalPhaseCap: 100 ether,
            userAllocationCap: 10 ether,
            merkleRoot: bytes32(0)
        });
        phases[1] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp + 2 days + 1,
            endTime: block.timestamp + 3 days,
            totalPhaseCap: 200 ether,
            userAllocationCap: 20 ether,
            merkleRoot: bytes32(0)
        });

        // Create presale config
        IPresale.PresaleConfig memory config = IPresale.PresaleConfig({
            admin: admin,
            softCap: 50 ether,
            hardCap: 300 ether,
            saleType: IPresale.SaleType.Credit,
            circulatingSupplyBps: 500
        });

        // Create BFactory params
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

        // Deploy presale as admin
        vm.prank(admin);
        address presale = factory.deployPresale(phases, config, bFactoryParams, address(presaleToken));

        // Verify presale was deployed
        assertTrue(presale != address(0));
        assertTrue(factory.isPresale(presale));
        assertEq(factory.getPresaleCount(), 1);
        assertEq(factory.getAllPresales()[0], presale);

        // Get presale implementation instance
        PresaleImplementation presaleImpl = PresaleImplementation(payable(presale));

        // Verify basic initialization
        assertEq(presaleImpl.getPhaseCount(), 2);

        // Verify phase 0 configuration
        IPresale.PresalePhaseConfig memory phase0 = presaleImpl.getPhaseInfo(0);
        assertEq(phase0.startTime, block.timestamp + 1 days);
        assertEq(phase0.endTime, block.timestamp + 2 days);
        assertEq(phase0.totalPhaseCap, 100 ether);
        assertEq(phase0.userAllocationCap, 10 ether);
        assertEq(phase0.merkleRoot, bytes32(0));

        // Verify phase 1 configuration
        IPresale.PresalePhaseConfig memory phase1 = presaleImpl.getPhaseInfo(1);
        assertEq(phase1.startTime, block.timestamp + 2 days + 1);
        assertEq(phase1.endTime, block.timestamp + 3 days);
        assertEq(phase1.totalPhaseCap, 200 ether);
        assertEq(phase1.userAllocationCap, 20 ether);
        assertEq(phase1.merkleRoot, bytes32(0));

        // Verify presale config
        (address configAdmin, uint256 softCap, uint256 hardCap,,) = presaleImpl.config();
        assertEq(configAdmin, admin);
        assertEq(softCap, 50 ether);
        assertEq(hardCap, 300 ether);

        // Verify BFactory params
        IPresale.BFactoryParams memory storedParams = presaleImpl.getBFactoryParams();
        assertEq(storedParams.bToken, address(0)); // TODO: When salt is added we can precompute and set here
        assertEq(storedParams.initialPoolBTokens, 1000000 ether);
        assertEq(storedParams.creator, admin);
        assertEq(storedParams.creatorFeePct, 100);
        assertEq(storedParams.createHook, false);
        assertEq(storedParams.claimMerkleRoot, bytes32(0));
        assertEq(storedParams.initialCollateral, 0);
        assertEq(storedParams.initialDebt, 0);
        assertEq(storedParams.initialBLV, 0);
        assertEq(storedParams.swapFeePct, 0.01 ether);

        // Verify initial state
        assertEq(presaleImpl.getTotalRaised(), 0);
        assertEq(presaleImpl.isFinalized(), false);
        assertEq(presaleImpl.isCancelled(), false);
        assertEq(presaleImpl.getCreatedToken(), address(0));
        assertEq(presaleImpl.getCreatedPool(), bytes32(0));
    }

    function test_DeployMultiplePresales() public {
        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](1);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp + 1 days,
            endTime: block.timestamp + 2 days,
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
            initialDebt: 0,
            initialBLV: 0,
            swapFeePct: 0.01 ether
        });

        // Deploy 3 presales as owner
        // TODO: CHECK FOR TOKEN UNIQUENESS AFTER SALT IS ADDED TO CREATE
        vm.startPrank(admin);
        address presale1 = factory.deployPresale(phases, config, bFactoryParams, address(presaleToken));
        address presale2 = factory.deployPresale(phases, config, bFactoryParams, address(presaleToken));
        address presale3 = factory.deployPresale(phases, config, bFactoryParams, address(presaleToken));
        vm.stopPrank();

        assertEq(factory.getPresaleCount(), 3);
        assertTrue(factory.isPresale(presale1));
        assertTrue(factory.isPresale(presale2));
        assertTrue(factory.isPresale(presale3));
        assertTrue(presale1 != presale2);
        assertTrue(presale2 != presale3);
    }

    function test_DeployPresale_OnlyOwner() public {
        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](1);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp + 1 days,
            endTime: block.timestamp + 2 days,
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
            initialDebt: 0,
            initialBLV: 0,
            swapFeePct: 0.01 ether
        });

        // Try to deploy as non-owner (user1)
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        factory.deployPresale(phases, config, bFactoryParams, address(presaleToken));

        // Verify no presale was deployed
        assertEq(factory.getPresaleCount(), 0);
    }

    function test_UpgradeBeacon() public {
        // Deploy new implementation
        PresaleImplementation newImplementation = new PresaleImplementation();

        vm.prank(admin);
        beacon.upgradeTo(address(newImplementation));

        assertEq(factory.getImplementation(), address(newImplementation));
        assertEq(beacon.implementation(), address(newImplementation));
    }

    function test_UpgradeBeacon_OnlyOwner() public {
        PresaleImplementation newImplementation = new PresaleImplementation();
        vm.prank(user1);
        vm.expectRevert();
        beacon.upgradeTo(address(newImplementation));
    }

    function test_UpgradeBeacon_InvalidImplementation() public {
        vm.expectRevert();
        beacon.upgradeTo(address(0));
    }

    function test_Constructor_InvalidBeacon() public {
        PresaleFactory factoryImpl = new PresaleFactory();
        vm.expectRevert(PresaleFactory.InvalidImplementation.selector);
        new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeCall(factoryImpl.initialize, (UpgradeableBeacon(address(0)), bFactory, admin))
        );
    }

    function test_Constructor_InvalidBFactory() public {
        PresaleFactory factoryImpl = new PresaleFactory();
        vm.expectRevert(PresaleFactory.BFactoryNotSet.selector);
        new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeCall(factoryImpl.initialize, (beacon, BFactory(address(0)), admin))
        );
    }

    function test_Constructor_InvalidAdmin() public {
        PresaleFactory factoryImpl = new PresaleFactory();
        vm.expectRevert(PresaleFactory.InvalidAdmin.selector);
        new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeCall(factoryImpl.initialize, (beacon, bFactory, address(0)))
        );
    }

    function test_GetBeacon() public view {
        address beaconAddr = factory.getBeacon();
        assertTrue(beaconAddr != address(0));
        assertEq(beaconAddr, address(beacon));
    }

    function test_DeployPresale_RevertsOnSharedPhaseBoundary() public {
        // Two adjacent phases sharing a boundary timestamp would let a depositor
        // appear in both phases at once and double their per-phase allocation.
        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](2);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp + 1 days,
            endTime: block.timestamp + 2 days,
            totalPhaseCap: 100 ether,
            userAllocationCap: 10 ether,
            merkleRoot: bytes32(0)
        });
        phases[1] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp + 2 days,
            endTime: block.timestamp + 3 days,
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
            initialDebt: 0,
            initialBLV: 0,
            swapFeePct: 0.01 ether
        });

        vm.prank(admin);
        vm.expectRevert(IPresale.InvalidPhaseConfiguration.selector);
        factory.deployPresale(phases, config, bFactoryParams, address(presaleToken));
    }
}
