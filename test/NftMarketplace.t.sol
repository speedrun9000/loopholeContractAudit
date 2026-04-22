// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {NftMarketplace} from "../src/NftMarketplace.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBSwap} from "../src/interfaces/IBswap.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract NftMarketplaceTests is Test {
    NftMarketplace public nftMarketplace;
    MockERC20 public mockERC20;
    MockERC721 public mockERC721;

    address public feeRouter = address(1111);
    address public initialOwner = address(this);
    uint256 public placeholderTokenId = 1;
    uint256 public auctionDuration = 1 weeks;
    address public afterburner = address(2222);
    address public blvModule = address(3333);
    IBSwap public bSwap = IBSwap(address(4444));
    address public swapper = address(this);

    function setUp() public {
        mockERC20 = new MockERC20("Test ERC20", "TEST20", 18);
        mockERC721 = new MockERC721("Test ERC721", "TEST721");

        NftMarketplace nftMarketplaceImplementation = new NftMarketplace();
        bytes memory marketplaceInitializationData = abi.encodeWithSelector(
            NftMarketplace.initialize.selector,
            mockERC20, // IERC20 _offerToken,
            feeRouter, // address _feeRouter,
            initialOwner, // address initialOwner,
            bSwap, // IBSwap _bSwap,
            swapper // address _swapper
        );
        nftMarketplace = NftMarketplace(
            address(
                new TransparentUpgradeableProxy({
                    _logic: address(nftMarketplaceImplementation),
                    initialOwner: initialOwner,
                    _data: marketplaceInitializationData
                })
            )
        );

        NftMarketplace.BTokenFeeConfig memory feeConfig =
            NftMarketplace.BTokenFeeConfig({bpsToAfterburner: 5000, bpsToBLV: 5000});
        NftMarketplace.BTokenRecipients memory recipients =
            NftMarketplace.BTokenRecipients({afterburner: afterburner, blvModule: blvModule});

        vm.expectEmit(true, true, true, true, address(nftMarketplace));
        emit NftMarketplace.CollectionForBTokenSet(address(mockERC20), address(mockERC721));
        nftMarketplace.setCollectionForBToken({
            bToken: address(mockERC20),
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
            nftMarketplace.collectionForBToken(address(mockERC20)) == address(mockERC721),
            "collectionForBToken set incorrectly"
        );
        require(
            nftMarketplace.bTokenForCollection(address(mockERC721)) == address(mockERC20),
            "bTokenForCollection set incorrectly"
        );
        require(
            nftMarketplace.lastCheckpointTimestamp(address(mockERC721)) == block.timestamp,
            "lastCheckpointTimestamp set incorrectly"
        );
    }

    function test_fuzz_informOfFeeDistribution(uint256 amountFees) public {
        uint256 offerAtCheckpoint = nftMarketplace.offerPrice(address(mockERC721));

        mockERC20.mint(address(nftMarketplace), amountFees);
        uint256 expectedNewCheckpointBalance = mockERC20.balanceOf(address(nftMarketplace));
        vm.expectEmit(true, true, true, true, address(nftMarketplace));
        emit NftMarketplace.Checkpoint(address(mockERC721), offerAtCheckpoint, expectedNewCheckpointBalance);
        vm.prank(feeRouter);
        nftMarketplace.informOfFeeDistribution(address(mockERC20), amountFees);

        uint256 checkpointBalanceAfter = nftMarketplace.checkpointBalance(address(mockERC721));
        uint256 lastCheckpointTimestampAfter = nftMarketplace.lastCheckpointTimestamp(address(mockERC721));
        require(checkpointBalanceAfter == expectedNewCheckpointBalance, "checkpointBalance did not update correctly");
        require(lastCheckpointTimestampAfter == block.timestamp, "lastCheckpointTimestamp did not update correctly");
    }

    function test_fuzz_informOfFeeDistribution_revert_OnlyFeeRouter(address caller) public {
        vm.assume(caller != feeRouter);

        vm.expectRevert(NftMarketplace.OnlyFeeRouter.selector);

        vm.prank(caller);
        nftMarketplace.informOfFeeDistribution(address(mockERC20), 0);
    }

    function test_offerPrice() public {
        uint256 maxOfferIncreaseRate = nftMarketplace.maxOfferIncreaseRate(address(mockERC721));
        uint256 amountFees = 1e18;
        test_fuzz_informOfFeeDistribution(amountFees);

        require(nftMarketplace.offerPrice(address(mockERC721)) == 0, "incorrect offerPrice 1");

        vm.warp(block.timestamp + 1);
        require(nftMarketplace.offerPrice(address(mockERC721)) == maxOfferIncreaseRate, "incorrect offerPrice 2");

        vm.warp(block.timestamp + 1e36);
        require(nftMarketplace.offerPrice(address(mockERC721)) == amountFees, "incorrect offerPrice 3");
    }

    function test_fuzz_offerPrice(uint256 amountFees, uint256 timeToWarpForward) public {
        // filter out unreasonable inputs to prevent under-/over-flow
        vm.assume(type(uint256).max - timeToWarpForward > block.timestamp);
        uint256 maxOfferIncreaseRate = nftMarketplace.maxOfferIncreaseRate(address(mockERC721));
        if (timeToWarpForward != 0) {
            vm.assume(type(uint256).max / timeToWarpForward > maxOfferIncreaseRate);
        }
        test_fuzz_informOfFeeDistribution(amountFees);

        require(nftMarketplace.offerPrice(address(mockERC721)) == 0, "incorrect offerPrice pre-check");

        vm.warp(block.timestamp + timeToWarpForward);
        uint256 timeToMaxOffer = amountFees / maxOfferIncreaseRate + (amountFees % maxOfferIncreaseRate != 0 ? 1 : 0);
        if (timeToWarpForward >= timeToMaxOffer) {
            assertEq(nftMarketplace.offerPrice(address(mockERC721)), amountFees, "offerPrice should be max");
        } else {
            assertEq(
                nftMarketplace.offerPrice(address(mockERC721)),
                timeToWarpForward * maxOfferIncreaseRate,
                "offerPrice should be timeToWarpForward * maxOfferIncreaseRate"
            );
        }
    }

    function test_nftCost() public {
        require(nftMarketplace.nftCost(address(mockERC721)) == type(uint256).max, "incorrect nftCost 1");

        mockERC20.mint(address(this), 1e24);
        uint256 totalSupply = mockERC20.totalSupply();
        require(totalSupply != 0, "bad test setup");

        mockERC721.mint(address(nftMarketplace), placeholderTokenId);
        vm.expectEmit(true, true, true, true, address(nftMarketplace));
        emit NftMarketplace.AuctionStarted(address(mockERC721));
        nftMarketplace.startAuction(address(mockERC721));
        require(
            nftMarketplace.auctionStartTimestamp(address(mockERC721)) == block.timestamp,
            "auctionStartTimestamp not set correctly"
        );
        require(nftMarketplace.nftCost(address(mockERC721)) == totalSupply, "incorrect nftCost 2");

        vm.warp(block.timestamp + auctionDuration / 2);
        uint256 _nftCost = nftMarketplace.nftCost(address(mockERC721));
        uint256 minAuctionPrice = nftMarketplace.minAuctionPrice(address(mockERC721));
        uint256 approxCost = totalSupply - (totalSupply - minAuctionPrice) / 2;
        uint256 tolerance = 1e6;
        require(_nftCost >= approxCost - tolerance, "incorrect nftCost 3 - nftCost too low");
        require(_nftCost <= approxCost + tolerance, "incorrect nftCost 3 - nftCost too high");

        vm.warp(block.timestamp - auctionDuration / 2);
        vm.warp(block.timestamp + auctionDuration - 1);
        require(nftMarketplace.nftCost(address(mockERC721)) > minAuctionPrice, "incorrect nftCost 4");

        vm.warp(block.timestamp + 1);
        require(nftMarketplace.nftCost(address(mockERC721)) == minAuctionPrice, "incorrect nftCost 5");

        vm.warp(block.timestamp + 1e5);
        require(nftMarketplace.nftCost(address(mockERC721)) == minAuctionPrice, "incorrect nftCost 6");
    }

    function test_fuzz_nftCost(uint256 startingSupply, uint256 timeToWarpForward) public {
        // sanity
        vm.assume(startingSupply != 0);
        vm.assume(type(uint256).max - timeToWarpForward > block.timestamp);
        // prevent under-/over-flows
        uint256 minAuctionPrice = nftMarketplace.minAuctionPrice(address(mockERC721));
        vm.assume(startingSupply >= minAuctionPrice);
        if (timeToWarpForward != 0) {
            vm.assume(type(uint256).max / timeToWarpForward > startingSupply - minAuctionPrice);
        }

        require(nftMarketplace.nftCost(address(mockERC721)) == type(uint256).max, "incorrect nftCost 1");

        mockERC20.mint(address(this), startingSupply);
        uint256 totalSupply = mockERC20.totalSupply();
        require(totalSupply != 0, "bad test setup");

        mockERC721.mint(address(nftMarketplace), placeholderTokenId);
        vm.expectEmit(true, true, true, true, address(nftMarketplace));
        emit NftMarketplace.AuctionStarted(address(mockERC721));
        nftMarketplace.startAuction(address(mockERC721));
        require(
            nftMarketplace.auctionStartTimestamp(address(mockERC721)) == block.timestamp,
            "auctionStartTimestamp not set correctly"
        );
        require(nftMarketplace.nftCost(address(mockERC721)) == totalSupply, "incorrect nftCost 2");

        vm.warp(block.timestamp + timeToWarpForward);
        uint256 _nftCost = nftMarketplace.nftCost(address(mockERC721));
        if (timeToWarpForward >= auctionDuration) {
            assertEq(_nftCost, minAuctionPrice, "nftCost should be minAuctionPrice");
        } else {
            uint256 expectedCost = totalSupply - (totalSupply - minAuctionPrice) * timeToWarpForward / auctionDuration;
            assertEq(_nftCost, expectedCost, "nftCost should be expectedCost");
        }
    }

    function test_fuzz_sellNftToVault(uint256 amountFees, uint256 tokenId) public {
        vm.assume(amountFees >= 1e4);
        vm.assume(amountFees < 1e36);
        address seller = address(this);
        mockERC721.mint(seller, tokenId);

        _test_sellNftToVault(seller, amountFees, tokenId);
    }

    function test_sellNftToVault_multipleNfts() public {
        address seller = address(this);
        mockERC721.mint(seller, 1);
        mockERC721.mint(seller, 2);
        mockERC721.mint(seller, 3);

        _test_sellNftToVault(seller, 1e18, 1);
        _test_sellNftToVault(seller, 1e20, 2);
        _test_sellNftToVault(seller, 1e19, 3);
    }

    function _test_sellNftToVault(address seller, uint256 amountFees, uint256 tokenId) internal {
        test_fuzz_informOfFeeDistribution(amountFees);

        vm.warp(block.timestamp + 200);
        uint256 offerPriceBefore = nftMarketplace.offerPrice(address(mockERC721));
        uint256 checkpointBalanceBefore = nftMarketplace.checkpointBalance(address(mockERC721));

        require(mockERC721.ownerOf(tokenId) == seller, "bad test setup");

        uint256 minSalePrice = offerPriceBefore - 1e4;
        uint256 sellerBalanceBefore = mockERC20.balanceOf(seller);

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
        require(
            mockERC20.balanceOf(seller) == sellerBalanceBefore + offerPriceBefore,
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

    function test_buyNftFromVault() public {
        test_fuzz_sellNftToVault(1e18, placeholderTokenId);
        _test_buyNftFromVault(placeholderTokenId);
    }

    function test_buyNftFromVault_multipleNftsSoldFirst() public {
        test_sellNftToVault_multipleNfts();
        _test_buyNftFromVault(2);
    }

    function _test_buyNftFromVault(uint256 tokenId) internal {
        vm.warp(block.timestamp + auctionDuration - 100);

        mockERC20.mint(address(nftMarketplace), 1e24);
        mockERC20.mint(address(this), 1e24);
        uint256 nftCost = nftMarketplace.nftCost(address(mockERC721));

        uint256 maxPrice = nftCost + 1e5;
        mockERC20.approve(address(nftMarketplace), maxPrice);
        uint256 purchaserBalanceBefore = mockERC20.balanceOf(address(this));

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

        require(mockERC20.balanceOf(address(this)) == purchaserBalanceBefore - nftCost, "purchaser paid wrong amount");
        require(mockERC721.balanceOf(address(nftMarketplace)) == nftsToSell - 1, "nft not transfered out");
    }

    function test_modifyAuctionDuration_auctionNotOngoing() public {
        uint256 newAuctionDuration = 3 weeks;
        nftMarketplace.modifyAuctionDuration(address(mockERC721), newAuctionDuration);
        require(
            nftMarketplace.auctionDuration(address(mockERC721)) == newAuctionDuration, "auctionDuration set incorrectly"
        );
    }

    function test_modifyAuctionDuration_auctionOngoing() public {
        uint256 oldAuctionDuration = 4 weeks;
        nftMarketplace.modifyAuctionDuration(address(mockERC721), oldAuctionDuration);
        require(
            nftMarketplace.auctionDuration(address(mockERC721)) == oldAuctionDuration, "auctionDuration set incorrectly"
        );

        test_fuzz_sellNftToVault(1e18, placeholderTokenId);
        vm.warp(block.timestamp + oldAuctionDuration - 100);

        mockERC20.mint(address(nftMarketplace), 1e24);
        mockERC20.mint(address(this), 1e24);
        uint256 nftCostBefore = nftMarketplace.nftCost(address(mockERC721));

        uint256 elapsedTimeBefore = block.timestamp - nftMarketplace.auctionStartTimestamp(address(mockERC721));

        uint256 newAuctionDuration = 1 weeks;
        nftMarketplace.modifyAuctionDuration(address(mockERC721), newAuctionDuration);
        require(
            nftMarketplace.auctionDuration(address(mockERC721)) == newAuctionDuration, "auctionDuration set incorrectly"
        );

        uint256 elapsedTimeAfter = block.timestamp - nftMarketplace.auctionStartTimestamp(address(mockERC721));
        require(elapsedTimeBefore > elapsedTimeAfter, "elapsed time should have been reduced");
        require(nftMarketplace.nftCost(address(mockERC721)) == nftCostBefore, "nft cost decreased inappropriately");
    }

    function test_fuzz_modifyAuctionDuration_auctionOngoing(uint256 oldAuctionDuration, uint256 newAuctionDuration)
        public
    {
        vm.warp(block.timestamp + 1e36);
        vm.assume(oldAuctionDuration <= 1e36);
        vm.assume(newAuctionDuration <= 1e36);
        vm.assume(oldAuctionDuration != 0);
        vm.assume(newAuctionDuration != 0);
        nftMarketplace.modifyAuctionDuration(address(mockERC721), oldAuctionDuration);
        require(
            nftMarketplace.auctionDuration(address(mockERC721)) == oldAuctionDuration, "auctionDuration set incorrectly"
        );

        test_fuzz_sellNftToVault(1e18, placeholderTokenId);
        vm.warp(block.timestamp + oldAuctionDuration - 1);

        mockERC20.mint(address(nftMarketplace), 1e24);
        mockERC20.mint(address(this), 1e24);
        uint256 nftCostBefore = nftMarketplace.nftCost(address(mockERC721));

        uint256 elapsedTimeBefore = block.timestamp - nftMarketplace.auctionStartTimestamp(address(mockERC721));

        nftMarketplace.modifyAuctionDuration(address(mockERC721), newAuctionDuration);
        require(
            nftMarketplace.auctionDuration(address(mockERC721)) == newAuctionDuration, "auctionDuration set incorrectly"
        );

        uint256 elapsedTimeAfter = block.timestamp - nftMarketplace.auctionStartTimestamp(address(mockERC721));
        if (newAuctionDuration < oldAuctionDuration) {
            require(elapsedTimeBefore > elapsedTimeAfter, "elapsed time should have been reduced");
        } else {
            require(elapsedTimeBefore == elapsedTimeAfter, "elapsed time should not have changed");
        }
        assertGe(nftMarketplace.nftCost(address(mockERC721)), nftCostBefore, "nft cost decreased inappropriately");
    }

    function test_modifyMinAuctionPrice_auctionNotOngoing() public {
        uint256 newMinAuctionPrice = 1e17;
        test_fuzz_modifyMinAuctionPrice_auctionNotOngoing(newMinAuctionPrice);
    }

    function test_fuzz_modifyMinAuctionPrice_auctionNotOngoing(uint256 newMinAuctionPrice) public {
        vm.expectEmit(true, true, true, true, address(nftMarketplace));
        emit NftMarketplace.MinAuctionPriceSet(address(mockERC721), newMinAuctionPrice);

        nftMarketplace.modifyMinAuctionPrice(address(mockERC721), newMinAuctionPrice);

        assertEq(
            nftMarketplace.minAuctionPrice(address(mockERC721)),
            newMinAuctionPrice,
            "minAuctionPrice not updated correctly"
        );
    }

    function test_fuzz_modifyMinAuctionPrice_auctionOngoing(
        uint256 minAuctionPriceBefore,
        uint256 minAuctionPriceAfter,
        uint256 auctionTimeElapsed
    ) public {
        vm.assume(minAuctionPriceBefore <= 1e36);
        vm.assume(minAuctionPriceAfter <= 1e36);
        uint256 oldAuctionDuration = 4 weeks;
        auctionTimeElapsed = bound(auctionTimeElapsed, 0, oldAuctionDuration * 2);

        // avoid time underflow
        vm.warp(block.timestamp + oldAuctionDuration);

        test_fuzz_modifyMinAuctionPrice_auctionNotOngoing(minAuctionPriceBefore);

        nftMarketplace.modifyAuctionDuration(address(mockERC721), oldAuctionDuration);

        test_fuzz_sellNftToVault(1e18, placeholderTokenId);
        vm.warp(block.timestamp + auctionTimeElapsed);

        mockERC20.mint(address(nftMarketplace), 1e40);
        mockERC20.mint(address(this), 1e40);
        uint256 nftCostBefore = nftMarketplace.nftCost(address(mockERC721));
        uint256 elapsedTimeBefore = block.timestamp - nftMarketplace.auctionStartTimestamp(address(mockERC721));

        vm.expectEmit(true, true, true, true, address(nftMarketplace));
        emit NftMarketplace.MinAuctionPriceSet(address(mockERC721), minAuctionPriceAfter);

        nftMarketplace.modifyMinAuctionPrice(address(mockERC721), minAuctionPriceAfter);

        assertEq(
            nftMarketplace.minAuctionPrice(address(mockERC721)),
            minAuctionPriceAfter,
            "minAuctionPrice not updated correctly"
        );

        uint256 nftCostAfter = nftMarketplace.nftCost(address(mockERC721));
        uint256 elapsedTimeAfter = block.timestamp - nftMarketplace.auctionStartTimestamp(address(mockERC721));
        assertLe(
            elapsedTimeAfter,
            elapsedTimeBefore,
            "elapsed time should never increase as a result of calling `modifyMinAuctionPrice`"
        );
        if (nftCostAfter != minAuctionPriceAfter) {
            assertGe(
                nftCostAfter,
                nftCostBefore,
                "nft cost should not decrease as a result of calling `modifyMinAuctionPrice` unless it is equal to the min price"
            );
        }
    }

    function test_fuzz_setSwapper(address newSwapper) public {
        vm.expectEmit(true, true, true, true, address(nftMarketplace));
        emit NftMarketplace.SwapperSet(newSwapper);
        nftMarketplace.setSwapper(newSwapper);
    }
}
