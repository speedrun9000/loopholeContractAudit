// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {PresaleFactory} from "../src/PresaleFactory.sol";
import {PresaleImplementation} from "../src/PresaleImplementation.sol";
import {IPresale} from "../src/interfaces/IPresale.sol";
import {MockBFactory} from "./mocks/MockBFactory.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Merkle} from "murky/Merkle.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PresaleMerkleTest is Test {
    PresaleFactory public factory;
    PresaleImplementation public implementation;
    MockBFactory public bFactory;
    UpgradeableBeacon public beacon;
    Merkle public merkle;
    MockERC20 public presaleToken;

    address public admin = address(0x5);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public user3 = address(0x3);
    address public user4 = address(0x4);

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

        presaleToken.mint(user1, 100 ether);
        vm.prank(user1);
        presaleToken.approve(address(factory), type(uint256).max);

        presaleToken.mint(user2, 100 ether);
        vm.prank(user2);
        presaleToken.approve(address(factory), type(uint256).max);

        presaleToken.mint(user3, 100 ether);
        vm.prank(user3);
        presaleToken.approve(address(factory), type(uint256).max);

        presaleToken.mint(user4, 100 ether);
        vm.prank(user4);
        presaleToken.approve(address(factory), type(uint256).max);
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

    function test_WhitelistValidDeposit() public {
        // Create whitelist with user1 and user2
        address[] memory whitelist = new address[](2);
        whitelist[0] = user1;
        whitelist[1] = user2;

        bytes32 merkleRoot = _createMerkleRoot(whitelist);

        // Deploy presale with whitelist
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
        address presaleAddr = factory.deployPresale(phases, config, bFactoryParams, address(presaleToken));
        PresaleImplementation presale = PresaleImplementation(payable(presaleAddr));

        // Approve presale contract
        vm.prank(user1);
        presaleToken.approve(address(presale), type(uint256).max);

        // User1 deposits with valid proof
        bytes32[] memory proof = _getProof(whitelist, 0);
        vm.prank(user1);
        presale.deposit(0, 5 ether, proof);

        assertEq(presale.getUserDepositedAmount(user1, 0), 5 ether);
    }

    function test_WhitelistInvalidDeposit() public {
        // Create whitelist with user1 and user2 (user3 not included)
        address[] memory whitelist = new address[](2);
        whitelist[0] = user1;
        whitelist[1] = user2;

        bytes32 merkleRoot = _createMerkleRoot(whitelist);

        // Deploy presale with whitelist
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
        address presaleAddr = factory.deployPresale(phases, config, bFactoryParams, address(presaleToken));
        PresaleImplementation presale = PresaleImplementation(payable(presaleAddr));

        // Approve presale contract
        vm.prank(user3);
        presaleToken.approve(address(presale), type(uint256).max);

        // User3 tries to deposit with empty proof (not whitelisted)
        vm.prank(user3);
        vm.expectRevert(IPresale.UserNotWhitelisted.selector);
        presale.deposit(0, 5 ether, new bytes32[](0));
    }

    function test_NoWhitelist() public {
        // Deploy presale without whitelist (merkleRoot = 0)
        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](1);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp,
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
            initialDebt: 0,
            initialBLV: 0,
            swapFeePct: 0.01 ether
        });

        vm.prank(admin);
        address presaleAddr = factory.deployPresale(phases, config, bFactoryParams, address(presaleToken));
        PresaleImplementation presale = PresaleImplementation(payable(presaleAddr));

        // Approve presale contract for all users
        vm.prank(user1);
        presaleToken.approve(address(presale), type(uint256).max);
        vm.prank(user2);
        presaleToken.approve(address(presale), type(uint256).max);
        vm.prank(user3);
        presaleToken.approve(address(presale), type(uint256).max);

        // Anyone can deposit
        vm.prank(user1);
        presale.deposit(0, 5 ether, new bytes32[](0));

        vm.prank(user2);
        presale.deposit(0, 5 ether, new bytes32[](0));

        vm.prank(user3);
        presale.deposit(0, 5 ether, new bytes32[](0));

        assertEq(presale.getTotalRaised(), 15 ether);
    }

    function test_MultipleWhitelistedUsers() public {
        // Create whitelist with 4 users
        address[] memory whitelist = new address[](4);
        whitelist[0] = user1;
        whitelist[1] = user2;
        whitelist[2] = user3;
        whitelist[3] = user4;

        bytes32 merkleRoot = _createMerkleRoot(whitelist);

        // Deploy presale
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
        address presaleAddr = factory.deployPresale(phases, config, bFactoryParams, address(presaleToken));
        PresaleImplementation presale = PresaleImplementation(payable(presaleAddr));

        // Approve presale contract for all users
        vm.prank(user1);
        presaleToken.approve(address(presale), type(uint256).max);
        vm.prank(user2);
        presaleToken.approve(address(presale), type(uint256).max);
        vm.prank(user3);
        presaleToken.approve(address(presale), type(uint256).max);
        vm.prank(user4);
        presaleToken.approve(address(presale), type(uint256).max);

        // All whitelisted users can deposit
        bytes32[] memory proof1 = _getProof(whitelist, 0);
        vm.prank(user1);
        presale.deposit(0, 5 ether, proof1);

        bytes32[] memory proof2 = _getProof(whitelist, 1);
        vm.prank(user2);
        presale.deposit(0, 6 ether, proof2);

        bytes32[] memory proof3 = _getProof(whitelist, 2);
        vm.prank(user3);
        presale.deposit(0, 7 ether, proof3);

        bytes32[] memory proof4 = _getProof(whitelist, 3);
        vm.prank(user4);
        presale.deposit(0, 8 ether, proof4);

        assertEq(presale.getTotalRaised(), 26 ether);
    }

    function test_DifferentWhitelistsPerPhase() public {
        // Phase 0 whitelist: user1, user2
        address[] memory whitelist0 = new address[](2);
        whitelist0[0] = user1;
        whitelist0[1] = user2;
        bytes32 merkleRoot0 = _createMerkleRoot(whitelist0);

        // Phase 1 whitelist: user3, user4
        address[] memory whitelist1 = new address[](2);
        whitelist1[0] = user3;
        whitelist1[1] = user4;
        bytes32 merkleRoot1 = _createMerkleRoot(whitelist1);

        // Deploy presale
        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](2);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp,
            endTime: block.timestamp + 7 days,
            totalPhaseCap: 100 ether,
            userAllocationCap: 10 ether,
            merkleRoot: merkleRoot0
        });
        phases[1] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp + 7 days,
            endTime: block.timestamp + 14 days,
            totalPhaseCap: 100 ether,
            userAllocationCap: 10 ether,
            merkleRoot: merkleRoot1
        });

        IPresale.PresaleConfig memory config = IPresale.PresaleConfig({
            admin: admin,
            softCap: 50 ether,
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
        vm.prank(user1);
        presaleToken.approve(address(presale), type(uint256).max);
        vm.prank(user3);
        presaleToken.approve(address(presale), type(uint256).max);

        // User1 can deposit in phase 0
        bytes32[] memory proof1Phase0 = _getProof(whitelist0, 0);
        vm.prank(user1);
        presale.deposit(0, 5 ether, proof1Phase0);

        // User3 cannot deposit in phase 0
        vm.prank(user3);
        vm.expectRevert(IPresale.UserNotWhitelisted.selector);
        presale.deposit(0, 5 ether, new bytes32[](0));

        // Warp to phase 1
        vm.warp(block.timestamp + 7 days);

        // User3 can deposit in phase 1
        bytes32[] memory proof3Phase1 = _getProof(whitelist1, 0);
        vm.prank(user3);
        presale.deposit(1, 5 ether, proof3Phase1);

        // User1 cannot deposit in phase 1
        vm.prank(user1);
        vm.expectRevert(IPresale.UserNotWhitelisted.selector);
        presale.deposit(1, 5 ether, new bytes32[](0));

        assertEq(presale.getTotalRaised(), 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                      setPhaseMerkleRoot TESTS
    //////////////////////////////////////////////////////////////*/

    function _deployPresaleNoWhitelist() internal returns (PresaleImplementation) {
        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](1);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp,
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
            initialDebt: 0,
            initialBLV: 0,
            swapFeePct: 0.01 ether
        });

        vm.prank(admin);
        address presaleAddr = factory.deployPresale(phases, config, bFactoryParams, address(presaleToken));
        return PresaleImplementation(payable(presaleAddr));
    }

    function test_SetPhaseMerkleRoot() public {
        PresaleImplementation presale = _deployPresaleNoWhitelist();

        // Anyone can deposit when no whitelist
        vm.prank(user3);
        presaleToken.approve(address(presale), type(uint256).max);
        vm.prank(user3);
        presale.deposit(0, 1 ether, new bytes32[](0));

        // Admin sets a whitelist
        address[] memory whitelist = new address[](2);
        whitelist[0] = user1;
        whitelist[1] = user2;
        bytes32 newRoot = _createMerkleRoot(whitelist);

        vm.prank(admin);
        presale.setPhaseMerkleRoot(0, newRoot);

        // Verify the root was updated
        IPresale.PresalePhaseConfig memory phase = presale.getPhaseInfo(0);
        assertEq(phase.merkleRoot, newRoot);

        // user3 can no longer deposit (not in new whitelist)
        vm.prank(user3);
        vm.expectRevert(IPresale.UserNotWhitelisted.selector);
        presale.deposit(0, 1 ether, new bytes32[](0));

        // user1 can deposit with valid proof
        vm.prank(user1);
        presaleToken.approve(address(presale), type(uint256).max);
        bytes32[] memory proof = _getProof(whitelist, 0);
        vm.prank(user1);
        presale.deposit(0, 5 ether, proof);

        assertEq(presale.getUserDepositedAmount(user1, 0), 5 ether);
    }

    function test_SetPhaseMerkleRoot_EmitsEvent() public {
        PresaleImplementation presale = _deployPresaleNoWhitelist();

        bytes32 newRoot = keccak256("new root");

        vm.expectEmit(true, false, false, true);
        emit IPresale.PhaseMerkleRootUpdated(0, bytes32(0), newRoot);

        vm.prank(admin);
        presale.setPhaseMerkleRoot(0, newRoot);
    }

    function test_SetPhaseMerkleRoot_ClearWhitelist() public {
        // Deploy with a whitelist
        address[] memory whitelist = new address[](2);
        whitelist[0] = user1;
        whitelist[1] = user2;
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
        address presaleAddr = factory.deployPresale(phases, config, bFactoryParams, address(presaleToken));
        PresaleImplementation presale = PresaleImplementation(payable(presaleAddr));

        // user3 cannot deposit (not whitelisted)
        vm.prank(user3);
        presaleToken.approve(address(presale), type(uint256).max);
        vm.prank(user3);
        vm.expectRevert(IPresale.UserNotWhitelisted.selector);
        presale.deposit(0, 1 ether, new bytes32[](0));

        // Admin clears the whitelist
        vm.prank(admin);
        presale.setPhaseMerkleRoot(0, bytes32(0));

        // Now anyone can deposit
        vm.prank(user3);
        presale.deposit(0, 1 ether, new bytes32[](0));

        assertEq(presale.getUserDepositedAmount(user3, 0), 1 ether);
    }

    function test_SetPhaseMerkleRoot_RevertNonAdmin() public {
        PresaleImplementation presale = _deployPresaleNoWhitelist();

        vm.prank(user1);
        vm.expectRevert(IPresale.Unauthorized.selector);
        presale.setPhaseMerkleRoot(0, keccak256("root"));
    }

    function test_SetPhaseMerkleRoot_RevertInvalidPhaseId() public {
        PresaleImplementation presale = _deployPresaleNoWhitelist();

        vm.prank(admin);
        vm.expectRevert(IPresale.InvalidPhaseId.selector);
        presale.setPhaseMerkleRoot(5, keccak256("root"));
    }

    function test_SetPhaseMerkleRoot_RevertWhenFinalized() public {
        // Deploy with lower soft cap so 4 users * 10 ether = 40 ether >= 30 ether soft cap
        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](1);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp,
            endTime: block.timestamp + 7 days,
            totalPhaseCap: 100 ether,
            userAllocationCap: 10 ether,
            merkleRoot: bytes32(0)
        });

        IPresale.PresaleConfig memory config = IPresale.PresaleConfig({
            admin: admin,
            softCap: 30 ether,
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

        // Approve and deposit to reach soft cap
        vm.prank(user1);
        presaleToken.approve(address(presale), type(uint256).max);
        vm.prank(user2);
        presaleToken.approve(address(presale), type(uint256).max);
        vm.prank(user3);
        presaleToken.approve(address(presale), type(uint256).max);
        vm.prank(user4);
        presaleToken.approve(address(presale), type(uint256).max);

        vm.prank(user1);
        presale.deposit(0, 10 ether, new bytes32[](0));
        vm.prank(user2);
        presale.deposit(0, 10 ether, new bytes32[](0));
        vm.prank(user3);
        presale.deposit(0, 10 ether, new bytes32[](0));
        vm.prank(user4);
        presale.deposit(0, 10 ether, new bytes32[](0));

        // Warp past phase end
        vm.warp(block.timestamp + 8 days);

        vm.prank(admin);
        presale.finalizeSale(
            IPresale.FinalizeParams({
                name: "Test",
                symbol: "TST",
                initialActivePrice: 1 ether,
                initialBlvPrice: 0,
                claimMerkleRoot: bytes32(0),
                initialCollateral: 0,
                initialDebt: 0,
                acquisitionTreasury: address(0),
                bpsToTreasury: 0,
                feeRouter: address(0),
                baseline: address(0),
                salt: bytes32(0),
                circulatingSupplyRecipient: address(0)
            })
        );

        // Credit sale: pool created but not yet finalized, need to complete
        vm.prank(admin);
        presale.completeFinalization();

        vm.prank(admin);
        vm.expectRevert(IPresale.PresaleAlreadyFinalized.selector);
        presale.setPhaseMerkleRoot(0, keccak256("root"));
    }

    function test_SetPhaseMerkleRoot_RevertWhenCancelled() public {
        PresaleImplementation presale = _deployPresaleNoWhitelist();

        vm.prank(admin);
        presale.cancelSale();

        vm.prank(admin);
        vm.expectRevert(IPresale.PresaleAlreadyCancelled.selector);
        presale.setPhaseMerkleRoot(0, keccak256("root"));
    }
}
