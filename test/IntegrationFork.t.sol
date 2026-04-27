// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {AfterburnerUpgradeable} from "../src/AfterburnerUpgradeable.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IPresale} from "../src/interfaces/IPresale.sol";
import {PresaleFactory} from "../src/PresaleFactory.sol";
import {PresaleImplementation} from "../src/PresaleImplementation.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {NftMarketplace} from "../src/NftMarketplace.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {ProjectFeeRouterUpgradeable} from "../src/ProjectFeeRouterUpgradeable.sol";

// baseline deps
import {BFactory} from "../src/interfaces/IBFactory.sol";
import {IBController} from "../src/interfaces/IBController.sol";
import {IBSwap} from "../src/interfaces/IBSwap.sol";
import {IBLens} from "../src/interfaces/IBLens.sol";
import {IBCredit} from "../src/interfaces/IBCredit.sol";

import {Merkle} from "murky/Merkle.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockERC721} from "./mocks/MockERC721.sol";

contract IntegrationForkTest is Test {
    // Use WETH as reserve token
    IERC20 public reserveToken = IERC20(0xB85885897D297000A74eA2e4711C3Ca729461ABC);

    // TODO: swap `afterburner` with this!
    AfterburnerUpgradeable public afterburner;

    address public owner = address(0x1);
    address public funder = address(0x2);

    PresaleFactory public factory;
    PresaleImplementation public presaleImplementation;
    UpgradeableBeacon public beacon;

    address baseline = address(0xf020C709fe9Ae902e3CDED1E50CA01021ce968E8); // latest sepolia base deployment (block 38018695)
    address baselineAdmin = address(0xe5393AA43106210e50CF8540Bab4F764079bE355);
    // Use WETH as presale token
    IERC20 public presaleToken = IERC20(0xB85885897D297000A74eA2e4711C3Ca729461ABC);
    BFactory bFactory = BFactory(baseline);
    IBController bController = IBController(baseline);

    Merkle public merkle;

    ProjectFeeRouterUpgradeable public router;

    address public treasury = address(0x2);
    address public royalties = address(0x3);
    address public team = address(0x4);
    address public blvModule = address(0x6);

    IERC20 public loopBToken;
    IERC20 public lstBToken;

    MockERC721 public mockERC721;
    NftMarketplace public nftMarketplaceImplementation;
    NftMarketplace public nftMarketplace;
    address public adminAddress = address(0x11);
    uint256 auctionDuration = 7 days;
    uint256 placeholderTokenId = 888;

    PresaleImplementation public loopPresale;
    PresaleImplementation public lstPresale;

    uint256 private saltCounter;

    function setUp() public {
        vm.createSelectFork("https://sepolia.base.org", 38018750);

        mockERC721 = new MockERC721("Test ERC721", "TEST721");

        // Deploy implementation
        presaleImplementation = new PresaleImplementation();

        // Deploy beacon pointing to implementation
        beacon = new UpgradeableBeacon(address(presaleImplementation), adminAddress);

        // Deploy factory with beacon, bFactory, and admin
        PresaleFactory factoryImpl = new PresaleFactory();
        ERC1967Proxy factoryProxy = new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeCall(factoryImpl.initialize, (beacon, bFactory, adminAddress))
        );
        factory = PresaleFactory(address(factoryProxy));

        merkle = new Merkle();

        // Deploy fee router so presales can use it as feeRecipient
        ProjectFeeRouterUpgradeable feeRouterImplementation = new ProjectFeeRouterUpgradeable();
        bytes memory FeeRouterInitData = abi.encodeCall(feeRouterImplementation.initialize, (owner));
        ERC1967Proxy feeRouterProxy = new ERC1967Proxy(address(feeRouterImplementation), FeeRouterInitData);
        router = ProjectFeeRouterUpgradeable(address(feeRouterProxy));

        // deploy presale, have users buy, and finalize sale
        loopPresale = _test_integration_EndToEnd_SuccessfulPresale(presaleToken);

        // record deployed token
        loopBToken = IERC20(loopPresale.createdToken());

        // allow loop token as reserve
        vm.prank(baselineAdmin);
        bController.setReserveApproval(address(loopBToken), true);

        // deploy presale, have users buy, and finalize sale
        lstPresale = _test_integration_EndToEnd_SuccessfulPresale(loopBToken);

        // record deployed token
        lstBToken = IERC20(lstPresale.createdToken());

        // set up afterburner
        // Deploy implementation + proxy
        AfterburnerUpgradeable afterburnerImplementation = new AfterburnerUpgradeable();
        // address owner_, address bToken_, address reserveToken_, address baseline_
        bytes memory afterburnerInitData = abi.encodeCall(
            afterburnerImplementation.initialize, (owner, address(loopBToken), address(reserveToken), baseline)
        );
        ERC1967Proxy afterBurnerProxy = new ERC1967Proxy(address(afterburnerImplementation), afterburnerInitData);
        afterburner = AfterburnerUpgradeable(address(afterBurnerProxy));

        // Authorize funder
        vm.prank(owner);
        afterburner.setAuthorizedFunder(funder, true);

        // Register bTokens and configure
        vm.startPrank(owner);

        router.registerBToken(address(loopBToken), address(reserveToken));
        router.registerBToken(address(lstBToken), address(loopBToken));

        // LST: 6667 treasury, 3333 royalties
        router.setConfig(
            address(lstBToken),
            ProjectFeeRouterUpgradeable.FeeConfig({
                bpsToAcquisitionTreasury: 6667, bpsToRoyalties: 3333, bpsToTeam: 0, bpsToAfterburner: 0, bpsToBLV: 0
            }),
            ProjectFeeRouterUpgradeable.Recipients({
                acquisitionTreasury: treasury,
                royaltyRecipient: royalties,
                team: team,
                afterburner: address(afterburner),
                blvModule: blvModule
            })
        );

        // LOOP: 10000 team
        router.setConfig(
            address(loopBToken),
            ProjectFeeRouterUpgradeable.FeeConfig({
                bpsToAcquisitionTreasury: 0, bpsToRoyalties: 0, bpsToTeam: 10000, bpsToAfterburner: 0, bpsToBLV: 0
            }),
            ProjectFeeRouterUpgradeable.Recipients({
                acquisitionTreasury: address(0),
                royaltyRecipient: address(0),
                team: team,
                afterburner: address(afterburner),
                blvModule: blvModule
            })
        );

        vm.stopPrank();

        nftMarketplaceImplementation = new NftMarketplace();
        bytes memory marketplaceInitializationData = abi.encodeWithSelector(
            NftMarketplace.initialize.selector,
            loopBToken, // IERC20 _offerToken,
            router, // address _feeRouter,
            adminAddress, // address initialOwner,
            baseline, // IBSwap _bSwap,
            adminAddress // address _swapper
        );
        nftMarketplace = NftMarketplace(
            address(
                new TransparentUpgradeableProxy({
                    _logic: address(nftMarketplaceImplementation),
                    initialOwner: adminAddress,
                    _data: marketplaceInitializationData
                })
            )
        );

        NftMarketplace.BTokenFeeConfig memory feeConfig =
            NftMarketplace.BTokenFeeConfig({bpsToAfterburner: 7000, bpsToBLV: 3000});
        NftMarketplace.BTokenRecipients memory recipients =
            NftMarketplace.BTokenRecipients({afterburner: address(afterburner), blvModule: blvModule});

        vm.expectEmit(true, true, true, true, address(nftMarketplace));
        emit NftMarketplace.CollectionForBTokenSet(address(lstBToken), address(mockERC721));
        vm.prank(adminAddress);
        nftMarketplace.setCollectionForBToken({
            bToken: address(lstBToken),
            nftCollection: address(mockERC721),
            _auctionDuration: auctionDuration,
            _maxOfferIncreaseRate: 1e15,
            _minAuctionPrice: 1e12,
            feeConfig: feeConfig,
            recipients: recipients
        });
        require(
            nftMarketplace.auctionDuration(address(mockERC721)) == auctionDuration, "auctionDuration set incorrectly"
        );
        require(
            nftMarketplace.collectionForBToken(address(lstBToken)) == address(mockERC721),
            "collectionForBToken set incorrectly"
        );
        require(
            nftMarketplace.bTokenForCollection(address(mockERC721)) == address(lstBToken),
            "bTokenForCollection set incorrectly"
        );
        require(
            nftMarketplace.lastCheckpointTimestamp(address(mockERC721)) == block.timestamp,
            "lastCheckpointTimestamp set incorrectly"
        );
    }

    function test_foo() public {}

    /// @dev Construct a claim merkle leaf using the Baseline nested abi.encode pattern
    /// leaf = keccak256(bytes.concat(keccak256(abi.encode(user, abi.encode(collateral, debt)))))
    function _claimLeaf(address user, uint128 collateral, uint128 debt) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(user, abi.encode(collateral, debt)))));
    }

    function _createClaimMerkleRoot(address[] memory users, uint128[] memory collaterals, uint128[] memory debts)
        internal
        view
        returns (bytes32)
    {
        bytes32[] memory leaves = new bytes32[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            leaves[i] = _claimLeaf(users[i], collaterals[i], debts[i]);
        }
        return merkle.getRoot(leaves);
    }

    function _getClaimProof(address[] memory users, uint128[] memory collaterals, uint128[] memory debts, uint256 index)
        internal
        view
        returns (bytes32[] memory)
    {
        bytes32[] memory leaves = new bytes32[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            leaves[i] = _claimLeaf(users[i], collaterals[i], debts[i]);
        }
        return merkle.getProof(leaves, index);
    }

    // copied from PresaleIntegrationTest
    function _hashLeaf(address account) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(account));
    }

    // copied from PresaleIntegrationTest
    function _createMerkleRoot(address[] memory accounts) internal view returns (bytes32) {
        bytes32[] memory leaves = new bytes32[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            leaves[i] = _hashLeaf(accounts[i]);
        }
        return merkle.getRoot(leaves);
    }

    // copied from PresaleIntegrationTest
    function _getProof(address[] memory accounts, uint256 index) internal view returns (bytes32[] memory) {
        bytes32[] memory leaves = new bytes32[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            leaves[i] = _hashLeaf(accounts[i]);
        }
        return merkle.getProof(leaves, index);
    }

    function test_integration_EndToEnd_SuccessfulPresale() public returns (PresaleImplementation presale) {
        return _test_integration_EndToEnd_SuccessfulPresale(presaleToken);
    }

    // copied from PresaleIntegrationTest, with modifications
    // modified to return the created presale
    // modified to accept a _presaleToken input instead of using stored variable
    function _test_integration_EndToEnd_SuccessfulPresale(IERC20 _presaleToken)
        internal
        returns (PresaleImplementation presale)
    {
        // Create 10 users
        address[] memory users = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            users[i] = address(uint160(0x100 + i));
            // modified to use cheatcode instead of minting
            deal(address(_presaleToken), users[i], 100 ether);
            vm.prank(users[i]);
            // end modified section
            _presaleToken.approve(address(factory), type(uint256).max);
        }

        // Create whitelists for each phase
        // Phase 0: First 5 users
        address[] memory whitelist0 = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            whitelist0[i] = users[i];
        }
        bytes32 merkleRoot0 = _createMerkleRoot(whitelist0);

        // Phase 1: Users 5-9
        address[] memory whitelist1 = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            whitelist1[i] = users[i + 5];
        }
        bytes32 merkleRoot1 = _createMerkleRoot(whitelist1);

        // Phase 2: All users
        bytes32 merkleRoot2 = bytes32(0);

        // Deploy presale with 3 phases
        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](3);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp,
            endTime: block.timestamp + 2 days,
            totalPhaseCap: 50 ether,
            userAllocationCap: 5 ether,
            merkleRoot: merkleRoot0
        });
        phases[1] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp + 2 days,
            endTime: block.timestamp + 5 days,
            totalPhaseCap: 100 ether,
            userAllocationCap: 10 ether,
            merkleRoot: merkleRoot1
        });
        phases[2] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp + 5 days,
            endTime: block.timestamp + 10 days,
            totalPhaseCap: 150 ether,
            userAllocationCap: 15 ether,
            merkleRoot: merkleRoot2
        });

        IPresale.PresaleConfig memory config = IPresale.PresaleConfig({
            admin: adminAddress,
            softCap: 100 ether,
            hardCap: 300 ether,
            saleType: IPresale.SaleType.Credit,
            circulatingSupplyBps: 500
        });

        IPresale.BFactoryParams memory bFactoryParams = IPresale.BFactoryParams({
            bToken: address(0),
            initialPoolBTokens: 1000000 ether,
            creator: adminAddress,
            creatorFeePct: 100,
            createHook: false,
            claimMerkleRoot: bytes32(0),
            initialCollateral: 0,
            initialDebt: 0,
            initialBLV: 0,
            swapFeePct: 0.01 ether
        });

        vm.prank(adminAddress);
        address presaleAddr = factory.deployPresale(phases, config, bFactoryParams, address(_presaleToken));
        // next line modified to set return value instead of creating new memory object
        presale = PresaleImplementation(payable(presaleAddr));

        // Approve presale contract for all users
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(users[i]);
            _presaleToken.approve(address(presale), type(uint256).max);
        }

        // Phase 0: First 5 users deposit with proofs
        for (uint256 i = 0; i < 5; i++) {
            bytes32[] memory proof = _getProof(whitelist0, i);
            vm.prank(users[i]);
            presale.deposit(0, 5 ether, proof);
        }
        assertEq(presale.getTotalRaised(), 25 ether);

        // Warp to phase 1
        vm.warp(block.timestamp + 2 days);

        // Phase 1: Next 5 users deposit with proofs, some make multiple deposits
        for (uint256 i = 5; i < 10; i++) {
            bytes32[] memory proof = _getProof(whitelist1, i - 5);

            vm.prank(users[i]);
            presale.deposit(1, 6 ether, proof);

            vm.prank(users[i]);
            presale.deposit(1, 4 ether, proof);
        }
        assertEq(presale.getTotalRaised(), 75 ether);

        // Warp to phase 2
        vm.warp(block.timestamp + 3 days);

        // Phase 2: All users deposit more with empty proof
        for (uint256 i = 0; i < 10; i++) {
            bytes32[] memory proof = new bytes32[](0);
            vm.prank(users[i]);
            presale.deposit(2, 10 ether, proof);
        }
        assertEq(presale.getTotalRaised(), 175 ether);

        // Verify user deposits across phases
        assertEq(presale.getUserDepositedAmount(users[0], 0), 5 ether);
        assertEq(presale.getUserDepositedAmount(users[0], 1), 0 ether);
        assertEq(presale.getUserDepositedAmount(users[0], 2), 10 ether);

        assertEq(presale.getUserDepositedAmount(users[5], 0), 0 ether);
        assertEq(presale.getUserDepositedAmount(users[5], 1), 10 ether);
        assertEq(presale.getUserDepositedAmount(users[5], 2), 10 ether);

        // Finalize presale
        // inputs modified from test
        uint16 bpsToTreasury = 1000;
        uint256 initialDebt = 0;
        uint256 initialPoolBTokens = presale.getBFactoryParams().initialPoolBTokens;
        uint256 initialCollateral = 1 ether;
        uint256 totalSupply = ((initialPoolBTokens + initialCollateral) * 105) / 100;
        uint256 initialCirculatingSupply = totalSupply - initialPoolBTokens - initialCollateral;
        // Get the reserve token balance (all presale tokens held by the presale contract)
        uint256 reserveBalance = _presaleToken.balanceOf(address(presale));

        // Split funds: send portion to acquisitions treasury
        uint256 treasuryAmount = 0;
        if (bpsToTreasury > 0) {
            treasuryAmount = (reserveBalance * bpsToTreasury) / 10_000;
        }

        // Remainder goes to pool
        uint256 poolReserves = reserveBalance - treasuryAmount;

        // Calculate book price and derive initial active price as book price + 5%
        uint256 bookPrice = ((poolReserves + initialDebt) * 1e18) / initialCirculatingSupply;
        uint256 initialActivePrice = (bookPrice * 105) / 100;
        // emit log_named_uint("reserveBalance", reserveBalance);
        // emit log_named_uint("poolReserves", poolReserves);

        vm.warp(block.timestamp + 11 days);

        vm.prank(adminAddress);
        presale.finalizeSale(
            IPresale.FinalizeParams({
                name: "Test Token",
                symbol: "TEST",
                initialActivePrice: initialActivePrice,
                initialBlvPrice: 0,
                claimMerkleRoot: bytes32(0),
                initialCollateral: initialCollateral,
                initialDebt: initialDebt,
                acquisitionTreasury: address(1111),
                bpsToTreasury: bpsToTreasury,
                feeRouter: address(router),
                baseline: baseline,
                salt: bytes32(++saltCounter),
                circulatingSupplyRecipient: address(0)
            })
        );

        // Credit sale: complete finalization
        vm.prank(adminAddress);
        presale.completeFinalization();

        // Verify finalization
        assertTrue(presale.isFinalized(), "presale not marked finalized");
        assertTrue(presale.getCreatedToken() != address(0), "token creation failed");
        assertTrue(presale.getCreatedPool() != bytes32(0), "pool creation failed");

        // --- Final balance assertions ---
        address bToken = presale.getCreatedToken();

        // Presale: zero reserve tokens (all went to pool + treasury)
        assertEq(_presaleToken.balanceOf(address(presale)), 0, "presale should have zero reserve tokens");

        // Reserve accounting: treasury + pool == total raised
        assertEq(treasuryAmount + poolReserves, reserveBalance, "reserve split doesn't sum to total");

        // Reserves went to Baseline (pool lives inside the Baseline contract)
        assertTrue(_presaleToken.balanceOf(baseline) >= poolReserves, "baseline should hold pool reserves");

        // bToken total supply should match calculated value
        assertEq(IERC20(bToken).totalSupply(), totalSupply, "bToken total supply mismatch");

        // Credit sale with no circulatingSupplyRecipient: presale holds circulating supply bTokens
        uint256 presaleBTokenBalance = IERC20(bToken).balanceOf(address(presale));
        assertEq(presaleBTokenBalance, initialCirculatingSupply, "presale should hold circulating supply");

        // end modified section
    }

    function test_integration_EndToEnd_SuccessfulPresale_CreditPositionsClaimed() public {
        // Set up claim users
        address[] memory claimUsers = new address[](3);
        claimUsers[0] = address(0xC1);
        claimUsers[1] = address(0xC2);
        claimUsers[2] = address(0xC3);

        uint128[] memory claimCollaterals = new uint128[](3);
        claimCollaterals[0] = 0.3 ether;
        claimCollaterals[1] = 0.4 ether;
        claimCollaterals[2] = 0.3 ether;

        uint128[] memory claimDebts = new uint128[](3);
        claimDebts[0] = 0.001 ether;
        claimDebts[1] = 0.001 ether;
        claimDebts[2] = 0.001 ether;

        // Build claim merkle tree and proofs
        bytes32 claimRoot = _createClaimMerkleRoot(claimUsers, claimCollaterals, claimDebts);
        bytes32[][] memory claimProofs = new bytes32[][](3);
        for (uint256 i = 0; i < 3; i++) {
            claimProofs[i] = _getClaimProof(claimUsers, claimCollaterals, claimDebts, i);
        }

        // Deploy presale with 1 public phase
        address[] memory depositors = new address[](3);
        for (uint256 i = 0; i < 3; i++) {
            depositors[i] = address(uint160(0x200 + i));
            deal(address(presaleToken), depositors[i], 100 ether);
            vm.prank(depositors[i]);
            presaleToken.approve(address(factory), type(uint256).max);
        }

        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](1);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp,
            endTime: block.timestamp + 7 days,
            totalPhaseCap: 300 ether,
            userAllocationCap: 100 ether,
            merkleRoot: bytes32(0)
        });

        uint128 totalClaimCollateral = 1 ether;

        IPresale.BFactoryParams memory bfp = IPresale.BFactoryParams({
            bToken: address(0),
            initialPoolBTokens: 1000000 ether,
            creator: adminAddress,
            creatorFeePct: 100,
            createHook: false,
            claimMerkleRoot: bytes32(0),
            initialCollateral: 0,
            initialDebt: 0,
            initialBLV: 0,
            swapFeePct: 0.01 ether
        });

        vm.prank(adminAddress);
        address presaleAddr = factory.deployPresale(
            phases,
            IPresale.PresaleConfig({
                admin: adminAddress,
                softCap: 50 ether,
                hardCap: 300 ether,
                saleType: IPresale.SaleType.Credit,
                circulatingSupplyBps: 500
            }),
            bfp,
            address(presaleToken)
        );
        PresaleImplementation presale = PresaleImplementation(payable(presaleAddr));

        // Depositors deposit
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(depositors[i]);
            presaleToken.approve(address(presale), type(uint256).max);
            vm.prank(depositors[i]);
            presale.deposit(0, 60 ether, new bytes32[](0));
        }

        // Calculate pricing (same pattern as existing fork test)
        uint256 initialPoolBTokens = presale.getBFactoryParams().initialPoolBTokens;
        uint256 totalSupply = ((initialPoolBTokens + totalClaimCollateral) * 105) / 100;
        uint256 initialCirculatingSupply = totalSupply - initialPoolBTokens - totalClaimCollateral;
        uint256 reserveBalance = presaleToken.balanceOf(address(presale));
        uint256 bookPrice = ((reserveBalance + 0.003 ether) * 1e18) / initialCirculatingSupply;
        uint256 initialActivePrice = (bookPrice * 105) / 100;

        // Authorize the presale as a credit deployer on baseline
        vm.prank(baselineAdmin);
        bController.setApprovedCreditDeployer(address(factory), true);

        vm.warp(block.timestamp + 8 days);

        // Finalize (creates pool, enters intermediate state)
        vm.prank(adminAddress);
        presale.finalizeSale(
            IPresale.FinalizeParams({
                name: "ClaimTest",
                symbol: "CT",
                initialActivePrice: initialActivePrice,
                initialBlvPrice: 0,
                claimMerkleRoot: claimRoot,
                initialCollateral: totalClaimCollateral,
                initialDebt: 0.003 ether,
                acquisitionTreasury: address(0),
                bpsToTreasury: 0,
                feeRouter: address(router),
                baseline: baseline,
                salt: bytes32(++saltCounter),
                circulatingSupplyRecipient: address(0)
            })
        );

        // Claim credit positions in a batch
        vm.prank(adminAddress);
        presale.claimCreditBatch(claimUsers, claimCollaterals, claimDebts, claimProofs);

        // Complete finalization
        vm.prank(adminAddress);
        presale.completeFinalization();

        assertTrue(presale.isFinalized(), "presale not finalized");

        address bToken = presale.getCreatedToken();
        assertTrue(bToken != address(0), "bToken not created");

        // Verify credit positions via IBLens
        IBLens lens = IBLens(baseline);
        for (uint256 i = 0; i < 3; i++) {
            (uint256 collateral, uint256 debt) = lens.creditAccount(bToken, claimUsers[i]);
            assertEq(collateral, claimCollaterals[i], "wrong collateral for claim user");
            assertEq(debt, claimDebts[i], "wrong debt for claim user");
        }

        // --- Swap test: buy bTokens from the pool ---
        address swapper = address(0xF00);
        uint256 buyAmount = 1 ether;
        deal(address(presaleToken), swapper, buyAmount);

        IBSwap bSwap = IBSwap(baseline);

        // Quote the buy
        (uint256 expectedOut,,) = bSwap.quoteBuyExactIn(bToken, buyAmount);
        assertTrue(expectedOut > 0, "buy quote should return nonzero bTokens");

        // Execute buy
        vm.startPrank(swapper);
        presaleToken.approve(baseline, buyAmount);
        (uint256 bTokensReceived,) = bSwap.buyTokensExactIn(bToken, buyAmount, 0);
        vm.stopPrank();

        assertEq(bTokensReceived, expectedOut, "buy output mismatch vs quote");
        assertEq(IERC20(bToken).balanceOf(swapper), bTokensReceived, "swapper bToken balance wrong after buy");
        assertEq(presaleToken.balanceOf(swapper), 0, "swapper should have spent all reserve");

        // --- Swap test: sell bTokens back to the pool ---
        uint256 sellAmount = bTokensReceived / 2;

        (uint256 expectedReserveOut,,) = bSwap.quoteSellExactIn(bToken, sellAmount);
        assertTrue(expectedReserveOut > 0, "sell quote should return nonzero reserve");

        vm.startPrank(swapper);
        IERC20(bToken).approve(baseline, sellAmount);
        (uint256 reserveReceived,) = bSwap.sellTokensExactIn(bToken, sellAmount, 0);
        vm.stopPrank();

        assertEq(reserveReceived, expectedReserveOut, "sell output mismatch vs quote");
        assertEq(presaleToken.balanceOf(swapper), reserveReceived, "swapper reserve balance wrong after sell");
        assertEq(
            IERC20(bToken).balanceOf(swapper), bTokensReceived - sellAmount, "swapper bToken balance wrong after sell"
        );

        // --- Credit position redemption test ---
        // claimUsers[0] has a credit position with 0.3 ether collateral (bTokens) and 0.001 ether debt
        address creditUser = claimUsers[0];
        IBCredit bCredit = IBCredit(baseline);
        IBLens lens2 = IBLens(baseline);

        (uint256 collBefore, uint256 debtBefore) = lens2.creditAccount(bToken, creditUser);
        assertTrue(collBefore > 0, "credit user should have collateral");
        assertTrue(debtBefore > 0, "credit user should have debt");

        // Deleverage: sell some collateral bTokens on the pool to repay debt
        uint256 collateralToSell = collBefore / 2;
        vm.prank(creditUser);
        (uint256 collRedeemed, uint256 debtRepaid,) = bCredit.deleverage(bToken, collateralToSell, 0);

        assertTrue(collRedeemed > 0, "should have redeemed some collateral");

        // Verify position reduced
        (uint256 collAfter, uint256 debtAfter) = lens2.creditAccount(bToken, creditUser);
        assertLt(collAfter, collBefore, "collateral should have decreased");
        assertEq(collAfter, collBefore - collRedeemed, "collateral decrease should match redeemed amount");
        assertEq(debtAfter, debtBefore - debtRepaid, "debt decrease should match repaid amount");
    }

    function test_integration_EndToEnd_SpotSale() public {
        // Deploy spot presale with 1 public phase
        address[] memory depositors = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            depositors[i] = address(uint160(0x300 + i));
            deal(address(presaleToken), depositors[i], 100 ether);
            vm.prank(depositors[i]);
            presaleToken.approve(address(factory), type(uint256).max);
        }

        IPresale.PresalePhaseConfig[] memory phases = new IPresale.PresalePhaseConfig[](1);
        phases[0] = IPresale.PresalePhaseConfig({
            startTime: block.timestamp,
            endTime: block.timestamp + 7 days,
            totalPhaseCap: 500 ether,
            userAllocationCap: 100 ether,
            merkleRoot: bytes32(0)
        });

        IPresale.BFactoryParams memory bfp = IPresale.BFactoryParams({
            bToken: address(0),
            initialPoolBTokens: 1000000 ether,
            creator: adminAddress,
            creatorFeePct: 100,
            createHook: false,
            claimMerkleRoot: bytes32(0),
            initialCollateral: 0,
            initialDebt: 0,
            initialBLV: 0,
            swapFeePct: 0.01 ether
        });

        vm.prank(adminAddress);
        address presaleAddr = factory.deployPresale(
            phases,
            IPresale.PresaleConfig({
                admin: adminAddress,
                softCap: 50 ether,
                hardCap: 500 ether,
                saleType: IPresale.SaleType.Spot,
                circulatingSupplyBps: 1000 // 10%
            }),
            bfp,
            address(presaleToken)
        );
        PresaleImplementation presale = PresaleImplementation(payable(presaleAddr));

        // Depositors deposit varying amounts
        uint256[] memory deposits = new uint256[](5);
        deposits[0] = 50 ether;
        deposits[1] = 30 ether;
        deposits[2] = 80 ether;
        deposits[3] = 20 ether;
        deposits[4] = 70 ether;
        uint256 totalDeposited = 250 ether;

        for (uint256 i = 0; i < 5; i++) {
            vm.prank(depositors[i]);
            presaleToken.approve(address(presale), type(uint256).max);
            vm.prank(depositors[i]);
            presale.deposit(0, deposits[i], new bytes32[](0));
        }
        assertEq(presale.getTotalRaised(), totalDeposited, "total raised mismatch");

        // Calculate pricing
        uint256 initialPoolBTokens = presale.getBFactoryParams().initialPoolBTokens;
        uint256 totalSupply = ((initialPoolBTokens + 0) * (10_000 + 1000)) / 10_000;
        uint256 initialCirculatingSupply = totalSupply - initialPoolBTokens;
        uint256 reserveBalance = presaleToken.balanceOf(address(presale));
        uint256 bookPrice = ((reserveBalance + 0) * 1e18) / initialCirculatingSupply;
        uint256 initialActivePrice = (bookPrice * 105) / 100;

        vm.warp(block.timestamp + 8 days);

        // Finalize spot sale
        vm.prank(adminAddress);
        presale.finalizeSale(
            IPresale.FinalizeParams({
                name: "Spot Test",
                symbol: "STEST",
                initialActivePrice: initialActivePrice,
                initialBlvPrice: 0,
                claimMerkleRoot: bytes32(0),
                initialCollateral: 0,
                initialDebt: 0,
                acquisitionTreasury: address(0),
                bpsToTreasury: 0,
                feeRouter: address(router),
                baseline: baseline,
                salt: bytes32(++saltCounter),
                circulatingSupplyRecipient: address(0)
            })
        );

        // Spot sale should be immediately finalized
        assertTrue(presale.isFinalized(), "spot sale should be finalized immediately");
        assertTrue(presale.getCreatedToken() != address(0), "bToken not created");
        assertTrue(presale.getCreatedPool() != bytes32(0), "pool not created");

        address bToken = presale.getCreatedToken();
        uint256 totalClaimable = presale.getTotalClaimableTokens();

        // Validate circulating supply matches expected
        assertEq(totalClaimable, initialCirculatingSupply, "totalClaimable mismatch");
        assertEq(totalClaimable, 100_000 ether, "10% of 1M should be 100K");

        // Presale should hold the claimable bTokens
        assertTrue(IERC20(bToken).balanceOf(address(presale)) >= totalClaimable, "presale should hold claimable tokens");

        // All depositors claim and verify pro-rata distribution
        uint256 totalClaimed = 0;
        for (uint256 i = 0; i < 5; i++) {
            uint256 expectedClaim = (deposits[i] * initialCirculatingSupply) / totalDeposited;
            assertEq(presale.getClaimableAmount(depositors[i]), expectedClaim, "wrong claimable amount");
            assertTrue(expectedClaim > 0, "claim should be nonzero");

            vm.prank(depositors[i]);
            presale.claimSpot();

            assertEq(IERC20(bToken).balanceOf(depositors[i]), expectedClaim, "wrong bToken balance after claim");
            totalClaimed += expectedClaim;
        }

        // Verify invariants
        assertLe(totalClaimed, totalClaimable, "claimed more than available");
        assertLe(totalClaimable - totalClaimed, 5, "too much rounding dust");

        // Verify double claim reverts
        vm.prank(depositors[0]);
        vm.expectRevert(IPresale.AlreadyClaimed.selector);
        presale.claimSpot();

        // Verify non-depositor reverts
        vm.prank(address(0xDEAD));
        vm.expectRevert(IPresale.NothingToClaim.selector);
        presale.claimSpot();

        // --- Final balance assertions for all addresses ---

        // Presale: should hold only unclaimed bToken dust, zero reserve tokens
        uint256 presaleBTokenBalance = IERC20(bToken).balanceOf(address(presale));
        uint256 presaleReserveBalance = presaleToken.balanceOf(address(presale));
        assertEq(presaleReserveBalance, 0, "presale should have zero reserve tokens");
        assertEq(presaleBTokenBalance, totalClaimable - totalClaimed, "presale bToken remainder should be dust only");
        assertLe(presaleBTokenBalance, 5, "presale bToken dust too large");

        // Reserves went to Baseline (pool lives inside the Baseline contract)
        assertTrue(presaleToken.balanceOf(baseline) >= totalDeposited, "baseline should hold pool reserves");

        // Depositors: each should have (initial reserve - deposit) reserve tokens, and their pro-rata bTokens
        for (uint256 i = 0; i < 5; i++) {
            uint256 expectedBTokens = (deposits[i] * initialCirculatingSupply) / totalDeposited;
            uint256 expectedReserve = 100 ether - deposits[i]; // started with 100 ether, deposited some

            assertEq(IERC20(bToken).balanceOf(depositors[i]), expectedBTokens, "depositor bToken balance wrong");
            assertEq(presaleToken.balanceOf(depositors[i]), expectedReserve, "depositor reserve balance wrong");
        }

        // bToken total supply accounting: pool tokens + circulating should equal totalSupply
        uint256 bTokenTotalSupply = IERC20(bToken).totalSupply();
        assertEq(bTokenTotalSupply, totalSupply, "bToken total supply mismatch");

        // All bTokens accounted for: pool holds poolBTokens, depositors hold claims, presale holds dust
        uint256 accountedBTokens = initialPoolBTokens + totalClaimed + presaleBTokenBalance;
        assertEq(accountedBTokens, bTokenTotalSupply, "bTokens not fully accounted for");

        // --- Swap test: buy bTokens from the pool ---
        address swapper = address(0xF00);
        uint256 buyAmount = 1 ether;
        deal(address(presaleToken), swapper, buyAmount);

        IBSwap bSwap = IBSwap(baseline);

        // Quote the buy
        (uint256 expectedOut,,) = bSwap.quoteBuyExactIn(bToken, buyAmount);
        assertTrue(expectedOut > 0, "buy quote should return nonzero bTokens");

        // Execute buy
        vm.startPrank(swapper);
        presaleToken.approve(baseline, buyAmount);
        (uint256 bTokensReceived,) = bSwap.buyTokensExactIn(bToken, buyAmount, 0);
        vm.stopPrank();

        assertEq(bTokensReceived, expectedOut, "buy output mismatch vs quote");
        assertEq(IERC20(bToken).balanceOf(swapper), bTokensReceived, "swapper bToken balance wrong after buy");
        assertEq(presaleToken.balanceOf(swapper), 0, "swapper should have spent all reserve");

        // --- Swap test: sell bTokens back to the pool ---
        uint256 sellAmount = bTokensReceived / 2;

        (uint256 expectedReserveOut,,) = bSwap.quoteSellExactIn(bToken, sellAmount);
        assertTrue(expectedReserveOut > 0, "sell quote should return nonzero reserve");

        vm.startPrank(swapper);
        IERC20(bToken).approve(baseline, sellAmount);
        (uint256 reserveReceived,) = bSwap.sellTokensExactIn(bToken, sellAmount, 0);
        vm.stopPrank();

        assertEq(reserveReceived, expectedReserveOut, "sell output mismatch vs quote");
        assertEq(presaleToken.balanceOf(swapper), reserveReceived, "swapper reserve balance wrong after sell");
        assertEq(
            IERC20(bToken).balanceOf(swapper), bTokensReceived - sellAmount, "swapper bToken balance wrong after sell"
        );
    }

    function test_fuzz_informOfFeeDistribution(uint256 amountFees) public {
        uint256 offerAtCheckpoint = nftMarketplace.offerPrice(address(mockERC721));

        // modified to use cheatcode instead of minting
        deal(address(loopBToken), address(nftMarketplace), amountFees);
        // modified to use loopBToken instead of mockERC20
        uint256 expectedNewCheckpointBalance = loopBToken.balanceOf(address(nftMarketplace));
        vm.expectEmit(true, true, true, true, address(nftMarketplace));
        emit NftMarketplace.Checkpoint(address(mockERC721), offerAtCheckpoint, expectedNewCheckpointBalance);
        // TODO: actually use router here!
        vm.prank(address(router));
        // modified to use lstBToken instead of mockERC20
        nftMarketplace.informOfFeeDistribution(address(lstBToken), amountFees);

        uint256 checkpointBalanceAfter = nftMarketplace.checkpointBalance(address(mockERC721));
        uint256 lastCheckpointTimestampAfter = nftMarketplace.lastCheckpointTimestamp(address(mockERC721));
        require(checkpointBalanceAfter == expectedNewCheckpointBalance, "checkpointBalance did not update correctly");
        require(lastCheckpointTimestampAfter == block.timestamp, "lastCheckpointTimestamp did not update correctly");
    }

    function _test_sellNftToVault(address seller, uint256 amountFees, uint256 tokenId) internal {
        test_fuzz_informOfFeeDistribution(amountFees);

        vm.warp(block.timestamp + 200);
        uint256 offerPriceBefore = nftMarketplace.offerPrice(address(mockERC721));
        uint256 checkpointBalanceBefore = nftMarketplace.checkpointBalance(address(mockERC721));

        require(mockERC721.ownerOf(tokenId) == seller, "bad test setup");

        uint256 minSalePrice = offerPriceBefore - 1e4;
        // modified to use loopBToken instead of mockERC20
        uint256 sellerBalanceBefore = loopBToken.balanceOf(seller);

        uint256 marketplaceNftsBefore = mockERC721.balanceOf(address(nftMarketplace));

        vm.prank(seller);
        mockERC721.setApprovalForAll(address(nftMarketplace), true);
        vm.expectEmit(false, false, false, false);
        emit IERC721.Transfer(address(this), address(nftMarketplace), tokenId);
        vm.expectEmit(true, true, true, true, address(nftMarketplace));
        emit NftMarketplace.NftAcquired(address(mockERC721), seller, tokenId, offerPriceBefore);
        if (nftMarketplace.auctionStartTimestamp(address(mockERC721)) == 0) {
            vm.expectEmit(true, true, true, true, address(nftMarketplace));
            emit NftMarketplace.AuctionStarted(address(mockERC721));
        }
        vm.expectEmit(false, false, false, false);
        emit IERC20.Transfer(address(nftMarketplace), address(this), offerPriceBefore);
        vm.prank(seller);
        nftMarketplace.sellNftToVault(address(mockERC721), tokenId, minSalePrice);

        uint256 marketplaceNftsAfter = mockERC721.balanceOf(address(nftMarketplace));
        assertEq(marketplaceNftsAfter, marketplaceNftsBefore + 1, "marketplace should have one more NFT");

        require(
            nftMarketplace.auctionStartTimestamp(address(mockERC721)) == block.timestamp,
            "auction did not start automatically, when it should have"
        );
        require(mockERC721.ownerOf(tokenId) == address(nftMarketplace), "ERC721 not transferred appropriately");
        require(
            nftMarketplace.lastCheckpointTimestamp(address(mockERC721)) == block.timestamp,
            "lastCheckpointTimestamp not set correctly"
        );
        // modified to use loopBToken instead of mockERC20
        require(
            loopBToken.balanceOf(seller) == sellerBalanceBefore + offerPriceBefore,
            "tokens not transferred to seller appropriately"
        );
        uint256 checkpointBalanceAfter = nftMarketplace.checkpointBalance(address(mockERC721));
        require(
            checkpointBalanceAfter == checkpointBalanceBefore - offerPriceBefore,
            "checkpointBalance not updated correctly"
        );
        uint256 newMaxOffer = offerPriceBefore * 75 / 100;

        uint256 offerPriceAfter = nftMarketplace.offerPrice(address(mockERC721));
        if (newMaxOffer >= checkpointBalanceAfter) {
            require(offerPriceAfter == checkpointBalanceAfter, "incorrect new offerPrice");
        } else {
            require(offerPriceAfter == newMaxOffer, "incorrect new offerPrice");
        }
    }

    function test_fuzz_sellNftToVault(uint256 amountFees, uint256 tokenId) public {
        vm.assume(amountFees >= 1e4);
        vm.assume(amountFees < 1e36);
        address seller = address(this);
        mockERC721.mint(seller, tokenId);

        _test_sellNftToVault(seller, amountFees, tokenId);
    }

    function test_buyNftFromVault() public {
        test_fuzz_sellNftToVault(1e18, placeholderTokenId);
        _test_buyNftFromVault(placeholderTokenId);
    }

    function _test_buyNftFromVault(uint256 tokenId) internal {
        vm.warp(block.timestamp + auctionDuration - 100);

        // modified to use cheatcode instead of minting
        // modified to use lstBToken instead of mockERC20
        deal(address(lstBToken), address(nftMarketplace), 1e24);
        deal(address(lstBToken), address(this), 1e24);
        uint256 nftCost = nftMarketplace.nftCost(address(mockERC721));

        uint256 maxPrice = nftCost + 1e5;
        // modified to use lstBToken instead of mockERC20
        lstBToken.approve(address(nftMarketplace), maxPrice);
        uint256 purchaserBalanceBefore = lstBToken.balanceOf(address(this));

        uint256 nftsToSell = mockERC721.balanceOf(address(nftMarketplace));

        vm.expectEmit(true, true, true, true, address(nftMarketplace));
        emit NftMarketplace.NftSold(address(mockERC721), address(this), tokenId, nftCost);
        if (nftsToSell >= 2) {
            vm.expectEmit(true, true, true, true, address(nftMarketplace));
            emit NftMarketplace.AuctionStarted(address(mockERC721));
        }
        nftMarketplace.buyNftFromVault(address(mockERC721), tokenId, maxPrice);

        if (nftsToSell >= 2) {
            require(
                nftMarketplace.auctionStartTimestamp(address(mockERC721)) == block.timestamp,
                "new auction not started correctly"
            );
        } else {
            require(
                nftMarketplace.auctionStartTimestamp(address(mockERC721)) == 0,
                "auction start time not reset to zero correctly"
            );
        }

        // modified to use lstBToken instead of mockERC20
        require(lstBToken.balanceOf(address(this)) == purchaserBalanceBefore - nftCost, "purchaser paid wrong amount");
        require(mockERC721.balanceOf(address(nftMarketplace)) == nftsToSell - 1, "nft not transfered out");
    }

    function test_swapToLST() public returns (uint256) {
        address buyer = address(this);
        uint256 swapAmount = 10_000e18;
        deal(address(presaleToken), buyer, swapAmount);

        vm.startPrank(buyer);
        // swap from presaleToken to loop tokens
        presaleToken.approve(address(baseline), swapAmount);
        (uint256 amountOut_loop, uint256 feesReceived_loop) =
            IBSwap(baseline).buyTokensExactIn({_bToken: address(loopBToken), _amountIn: swapAmount, _limitAmount: 1});

        // swap from loop tokens to LST
        loopBToken.approve(address(baseline), amountOut_loop);
        (uint256 amountOut_LST, uint256 feesReceived_LST) =
            IBSwap(baseline).buyTokensExactIn({_bToken: address(lstBToken), _amountIn: amountOut_loop, _limitAmount: 1});
        vm.stopPrank();

        emit log_named_uint("amountOut_LST", amountOut_LST);
        return amountOut_LST;
    }

    function test_swapToLST_andBack() public returns (uint256) {
        address buyer = address(this);
        uint256 swapAmount = test_swapToLST();

        vm.startPrank(buyer);
        // swap from LST to loop
        lstBToken.approve(address(baseline), swapAmount);
        (uint256 amountOut_loop, uint256 feesReceived_loop) =
            IBSwap(baseline).sellTokensExactIn({_bToken: address(lstBToken), _amountIn: swapAmount, _limitAmount: 1});

        // swap from loop to WETH
        loopBToken.approve(address(baseline), amountOut_loop);
        (uint256 amountOut_weth, uint256 feesReceived_weth) = IBSwap(baseline)
            .sellTokensExactIn({_bToken: address(loopBToken), _amountIn: amountOut_loop, _limitAmount: 1});
        vm.stopPrank();

        emit log_named_uint("amountOut_weth", amountOut_weth);
        return amountOut_weth;
    }
}
