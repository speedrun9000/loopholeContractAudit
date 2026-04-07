// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {NftMarketplace} from "../src/NftMarketplace.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBSwap} from "../src/interfaces/IBswap.sol";

contract NftMarketplaceManualTester {
    NftMarketplace public nftMarketplace;
    MockERC20 public mockERC20;
    MockERC721 public mockERC721;

    address public feeRouter = address(this);
    address public initialOwner = address(this);
    uint256 public placeholderTokenId = 1;
    uint256 public auctionDuration = 1 weeks;
    address public afterburner = address(2222);
    address public blvModule = address(3333);
    IBSwap public bSwap = IBSwap(address(0xf020C709fe9Ae902e3CDED1E50CA01021ce968E8));
    address public swapper = address(this);

    function setUp() public {
        mockERC20 = new MockERC20("Test ERC20", "TEST20", 18);
        mockERC721 = new MockERC721("Test ERC721", "TEST721");

        nftMarketplace = new NftMarketplace();
        nftMarketplace.initialize({
            _offerToken: mockERC20, _feeRouter: feeRouter, initialOwner: initialOwner, _bSwap: bSwap, _swapper: swapper
        });

        NftMarketplace.BTokenFeeConfig memory feeConfig =
            NftMarketplace.BTokenFeeConfig({bpsToAfterburner: 5000, bpsToBLV: 5000});
        NftMarketplace.BTokenRecipients memory recipients =
            NftMarketplace.BTokenRecipients({afterburner: afterburner, blvModule: blvModule});

        nftMarketplace.setCollectionForBToken({
            bToken: address(mockERC20),
            nftCollection: address(mockERC721),
            _auctionDuration: auctionDuration,
            _maxOfferIncreaseRate: 1e15,
            _minAuctionPrice: 1e12,
            feeConfig: feeConfig,
            recipients: recipients
        });
    }

    // @notice mint `amountFees` to marketplace and inform it of distribution
    function test_informOfFeeDistribution(uint256 amountFees) public {
        mockERC20.mint(address(nftMarketplace), amountFees);
        nftMarketplace.informOfFeeDistribution(address(mockERC20), amountFees);
    }

    // @notice sell `tokenId` of mockERC721 to the marketplace, which is minted `amountFees`
    function test_sellNftToVault(uint256 amountFees, uint256 tokenId, uint256 minSalePrice) public {
        mockERC721.mint(address(this), tokenId);
        test_informOfFeeDistribution(amountFees);
        mockERC721.setApprovalForAll(address(nftMarketplace), true);
        nftMarketplace.sellNftToVault(address(mockERC721), tokenId, minSalePrice);
    }

    function test_buyNftFromVault(uint256 amountFees, uint256 tokenId) public {
        test_sellNftToVault(amountFees, tokenId, 1);

        mockERC20.mint(address(nftMarketplace), 1e24);
        mockERC20.mint(address(this), 1e24);
        uint256 nftCost = nftMarketplace.nftCost(address(mockERC721));

        uint256 maxPrice = nftCost + 1e5;
        mockERC20.approve(address(nftMarketplace), maxPrice);
        nftMarketplace.buyNftFromVault(address(mockERC721), tokenId, maxPrice);
    }

    function test_modifyAuctionDuration(uint256 newAuctionDuration) public {
        nftMarketplace.modifyAuctionDuration(address(mockERC721), newAuctionDuration);
    }

    function test_modifyMinAuctionPrice(uint256 newMinAuctionPrice) public {
        nftMarketplace.modifyMinAuctionPrice(address(mockERC721), newMinAuctionPrice);
    }

    function test_setSwapper(address newSwapper) public {
        nftMarketplace.setSwapper(newSwapper);
    }

    function test_transferOwnership(address newOwner) public {
        nftMarketplace.transferOwnership(newOwner);
    }

    /// @notice Called to exchange tokens earned from NFT sales for `offerToken` and distribute the proceeds
    /// @dev Proceeds are automatically split according to the fee config for the bToken
    function test_performSwap(address bToken, uint256 tokensIn, uint256 minOut) public {
        nftMarketplace.performSwap(bToken, tokensIn, minOut);
    }
}
