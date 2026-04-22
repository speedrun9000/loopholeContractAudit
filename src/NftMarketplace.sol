// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {IBSwap} from "./interfaces/IBswap.sol";

contract NftMarketplace is OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    /// @dev Used for distributing bTokens from NFT sales
    struct BTokenFeeConfig {
        uint16 bpsToAfterburner;
        uint16 bpsToBLV;
    }

    // TODO: verify which recipients are needed
    /// @dev Used for distributing bTokens from NFT sales
    struct BTokenRecipients {
        address afterburner;
        address blvModule;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event NftAcquired(address indexed collection, address indexed seller, uint256 indexed tokenId, uint256 pricePaid);
    event Checkpoint(address indexed collection, uint256 currentOffer, uint256 offerTokenBalance);
    event NftSold(address indexed collection, address indexed buyer, uint256 indexed tokenId, uint256 pricePaid);
    event AuctionStarted(address indexed collection);
    event CollectionForBTokenSet(address indexed bToken, address indexed collection);
    event AuctionDurationModified(address indexed collection, uint256 newAuctionDuration);
    event MaxOfferIncreaseRateSet(address indexed collection, uint256 newMaxOfferIncreaseRate);
    event MinAuctionPriceSet(address indexed collection, uint256 newMinAuctionPrice);
    event ConfigSet(address indexed bToken, BTokenFeeConfig feeConfig, BTokenRecipients recipients);
    event SwapperSet(address indexed newSwapper);
    event SwapPerformed(address indexed bToken, uint256 amountIn, uint256 amountOut);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidSalePriceInput();
    error InvalidPurchasePriceInput();
    error NoNftToAuction();
    error OnlyFeeRouter();
    error NftCollectionNotSetForBToken();
    error InvalidAuctionDuration();
    error BTokenNotRegistered();
    error InvalidBpSum();
    error ZeroRecipientForNonZeroBps();
    error OnlySwapper();
    error CannotSwapOfferToken();
    error CollectionNotRegistered();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice ERC20 offered by this contract in exchange for NFTs
    IERC20 public offerToken;

    /// @notice Address trusted by this contract to forward it fees and inform it of the bToken the fees were earned by
    address public feeRouter;

    /// @notice Address used to swap tokens earned from NFT sales
    IBSwap public bSwap;

    /// @notice Address allowed to perform swaps
    address public swapper;

    /// @notice Mapping: NFT collection address => the max rate at which the amount offered by this contract can increase
    /// @dev Expressed as a not scaled (i.e. "wei") amount, with a timescale of 1 second
    mapping(address => uint256) public maxOfferIncreaseRate;

    /// @notice Mapping: NFT collection address => absolute floor on the auction price
    /// @dev A dutch auction that reaches this price will stay at this price indefinitely
    mapping(address => uint256) public minAuctionPrice;

    /// @notice Mapping: NFT collection address => The UTC timestamp at which a checkpoint was last performed for the collection
    mapping(address => uint256) public lastCheckpointTimestamp;

    /// @notice Mapping: NFT collection address => The amount of `offerToken` held by this contract
    ///        at `lastCheckpointTimestamp[collection]`, which are specifically from fees credited to the collection
    mapping(address => uint256) public checkpointBalance;

    /// @notice Mapping: NFT collection address => the amount of `offerToken` which was offered by this contract
    ///        for an NFT from the collection, at `lastCheckpointTimestamp[collection]`
    mapping(address => uint256) public offerAtCheckpoint;

    /// @notice Mapping: NFT collection address => The UTC timestamp at which the current Dutch auction sale for an NFT from the collection started
    /// @dev A value of `0` indicates that no sale is ongoing
    mapping(address => uint256) public auctionStartTimestamp;

    /// @notice Mapping: NFT collection address => The duration over which the Dutch auction price for an NFT falls to the minimum value
    mapping(address => uint256) public auctionDuration;

    /// @notice Mapping: bToken => corresponding NFT collection address
    mapping(address => address) public collectionForBToken;

    /// @notice Mapping: NFT collection address => corresponding bToken
    mapping(address => address) public bTokenForCollection;

    /// @notice Fee split config per bToken
    mapping(address => BTokenFeeConfig) internal _feeConfig;

    /// @notice Recipient addresses per bToken
    mapping(address => BTokenRecipients) internal _recipients;

    /// @dev Storage gap for future upgrades
    uint256[50] private __gap;

    /*//////////////////////////////////////////////////////////////
                              INITIALIZER
    //////////////////////////////////////////////////////////////*/
    constructor() {
        _disableInitializers();
    }

    function initialize(IERC20 _offerToken, address _feeRouter, address initialOwner, IBSwap _bSwap, address _swapper)
        external
        initializer
    {
        offerToken = _offerToken;
        feeRouter = _feeRouter;
        __Ownable_init(initialOwner);
        bSwap = _bSwap;
        _setSwapper(_swapper);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice The current amount of `offerToken` offered by this contract for an NFT from `nftCollection`, at the present time.
    /// @dev Capped at `checkpointBalance[nftCollection]`.
    function offerPrice(address nftCollection) public view returns (uint256) {
        uint256 maxOffer = offerAtCheckpoint[nftCollection] + (block.timestamp - lastCheckpointTimestamp[nftCollection])
            * maxOfferIncreaseRate[nftCollection];
        return Math.min(maxOffer, checkpointBalance[nftCollection]);
    }

    /// @notice The current cost at which a caller can purchase an NFT from `nftCollection`, from this contract
    /// @dev The caller must pay the cost in `bTokenForCollection[nftCollection]`
    function nftCost(address nftCollection) public view returns (uint256) {
        uint256 _auctionStartTimestamp = auctionStartTimestamp[nftCollection];
        if (_auctionStartTimestamp == 0) {
            return type(uint256).max;
        } else {
            uint256 _auctionDuration = auctionDuration[nftCollection];
            uint256 elapsedTime = block.timestamp - _auctionStartTimestamp;
            if (elapsedTime >= _auctionDuration) {
                return minAuctionPrice[nftCollection];
            } else {
                uint256 startingPrice = _startingPrice(nftCollection);
                return startingPrice - (startingPrice - minAuctionPrice[nftCollection]) * elapsedTime / _auctionDuration;
            }
        }
    }

    function _startingPrice(address nftCollection) internal view returns (uint256) {
        return IERC20(bTokenForCollection[nftCollection]).totalSupply();
    }

    /*//////////////////////////////////////////////////////////////
                            STATE-MODIFYING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Sells the `tokenId` of `nftCollection` to this contract for `offerPrice(nftCollection)` in `offerToken`
    /// @dev Will revert if `minPrice > offerPrice(nftCollection)`, ensuring the user receives *at least* `minPrice`
    function sellNftToVault(address nftCollection, uint256 tokenId, uint256 minPrice) external whenNotPaused {
        uint256 _currentOffer = offerPrice(nftCollection);
        /// taking a minPrice input + reverting here deals with a potential race condition where one user sells this contract an NFT
        /// after another user sends a tx but before the second user's tx lands
        require(minPrice <= _currentOffer, InvalidSalePriceInput());

        IERC721(nftCollection).transferFrom(msg.sender, address(this), tokenId);

        lastCheckpointTimestamp[nftCollection] = block.timestamp;
        // reduce checkpoint balance by the outgoing amount
        checkpointBalance[nftCollection] -= _currentOffer;
        // set offer to the minimum of (a) 75% of the price being paid and (b) the token balance of this contract after the payment
        offerAtCheckpoint[nftCollection] = Math.min(_currentOffer * 75 / 100, checkpointBalance[nftCollection]);

        emit NftAcquired(nftCollection, msg.sender, tokenId, _currentOffer);
        // start auction for the NFT if one is not already ongoing
        startAuction(nftCollection);
        offerToken.safeTransfer(msg.sender, _currentOffer);
    }

    /// @notice If applicable / possible, starts a new Dutch auction for an NFT from `nftCollection`
    /// @dev If an auction is already ongoing then this is a no-op
    /// @dev This will revert if no auction is ongoing *AND* this contract has no NFT to auction from the `nftCollection`
    function startAuction(address nftCollection) public whenNotPaused {
        if (auctionStartTimestamp[nftCollection] == 0) {
            require(auctionDuration[nftCollection] != 0, CollectionNotRegistered());
            require(IERC721(nftCollection).balanceOf(address(this)) != 0, NoNftToAuction());

            auctionStartTimestamp[nftCollection] = block.timestamp;
            emit AuctionStarted(nftCollection);
        }
    }

    /// @notice Buys the `tokenId` of `nftCollection` to this contract, for `nftCost(nftCollection)` in `bTokenForCollection[nftCollection]`
    /// @dev Caller will make payment in `bTokenForCollection[nftCollection]`
    /// @dev Will revert if `nftCost(nftCollection) > maxPrice`
    function buyNftFromVault(address nftCollection, uint256 tokenId, uint256 maxPrice) external whenNotPaused {
        uint256 _currentPrice = nftCost(nftCollection);
        /// taking a maxPrice input + reverting here deals with a potential race condition where one user buys an NFT from this contract
        /// after another user sends a tx but before the second user's tx lands
        require(_currentPrice <= maxPrice, InvalidPurchasePriceInput());

        emit NftSold(nftCollection, msg.sender, tokenId, _currentPrice);

        // immediately start a new auction, if possible
        if (IERC721(nftCollection).balanceOf(address(this)) >= 2) {
            auctionStartTimestamp[nftCollection] = block.timestamp;
            emit AuctionStarted(nftCollection);
        } else {
            auctionStartTimestamp[nftCollection] = 0;
        }

        IERC20(bTokenForCollection[nftCollection]).safeTransferFrom(msg.sender, address(this), _currentPrice);

        IERC721(nftCollection).transferFrom(address(this), msg.sender, tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                            PERMISSIONED / ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Allows the owner of this contract to set values of the bToken <> nftCollection mappings
    /// @dev And configures auction and fee parameters
    function setCollectionForBToken(
        address bToken,
        address nftCollection,
        uint256 _auctionDuration,
        uint256 _maxOfferIncreaseRate,
        uint256 _minAuctionPrice,
        BTokenFeeConfig calldata feeConfig,
        BTokenRecipients calldata recipients
    ) external onlyOwner {
        require(_auctionDuration != 0, InvalidAuctionDuration());
        collectionForBToken[bToken] = nftCollection;
        bTokenForCollection[nftCollection] = bToken;
        emit CollectionForBTokenSet(bToken, nftCollection);
        // initialize checkpoint timestamp for the collection
        lastCheckpointTimestamp[nftCollection] = block.timestamp;
        // this also performs the first checkpoint
        _modifyMaxOfferIncreaseRate(nftCollection, _maxOfferIncreaseRate);
        _modifyMinAuctionPrice(nftCollection, _minAuctionPrice);
        _modifyAuctionDuration(nftCollection, _auctionDuration);
        _setConfig(bToken, feeConfig, recipients);
    }

    /**
     * @notice Set the fee config and recipients for a bToken.
     * @param bToken The bToken address (must be registered)
     * @param feeConfig Fee split in basis points (must sum to 10000)
     * @param recipients Recipient addresses
     */
    function setConfig(address bToken, BTokenFeeConfig calldata feeConfig, BTokenRecipients calldata recipients)
        external
        onlyOwner
    {
        _setConfig(bToken, feeConfig, recipients);
    }

    function _setConfig(address bToken, BTokenFeeConfig calldata feeConfig, BTokenRecipients calldata recipients)
        internal
    {
        uint256 sum = uint256(feeConfig.bpsToAfterburner) + uint256(feeConfig.bpsToBLV);
        if (sum != 10_000) revert InvalidBpSum();

        if (feeConfig.bpsToAfterburner > 0 && recipients.afterburner == address(0)) {
            revert ZeroRecipientForNonZeroBps();
        }
        if (feeConfig.bpsToBLV > 0 && recipients.blvModule == address(0)) {
            revert ZeroRecipientForNonZeroBps();
        }

        _feeConfig[bToken] = feeConfig;
        _recipients[bToken] = recipients;

        emit ConfigSet(bToken, feeConfig, recipients);
    }

    function modifyAuctionDuration(address nftCollection, uint256 _auctionDuration) external onlyOwner {
        _modifyAuctionDuration(nftCollection, _auctionDuration);
    }

    function _modifyAuctionDuration(address nftCollection, uint256 _auctionDuration) internal {
        require(_auctionDuration != 0, InvalidAuctionDuration());
        // if auction is ongoing *and* duration is decreasing, then modify the start time to avoid sudden decrease in auction price
        if (_auctionDuration < auctionDuration[nftCollection]) {
            uint256 _auctionStartTimestamp = auctionStartTimestamp[nftCollection];
            if (_auctionStartTimestamp != 0) {
                uint256 elapsedTime = block.timestamp - _auctionStartTimestamp;
                // calculate the appropriate elapsed time for the same fraction of the auction duration to have occurred
                uint256 adjustedElapsedTime = elapsedTime * _auctionDuration / auctionDuration[nftCollection];
                // calculate at set the modified 'start time' of the auction, so the new elapsed time is correctly reflected in the `nftCost` calculation
                auctionStartTimestamp[nftCollection] = (block.timestamp - adjustedElapsedTime);
            }
        }
        auctionDuration[nftCollection] = _auctionDuration;
        emit AuctionDurationModified(nftCollection, _auctionDuration);
    }

    function modifyMinAuctionPrice(address nftCollection, uint256 _minAuctionPrice) external onlyOwner {
        _modifyMinAuctionPrice(nftCollection, _minAuctionPrice);
    }

    function _modifyMinAuctionPrice(address nftCollection, uint256 _minAuctionPrice) internal {
        // if auction is ongoing *and* minAuctionPrice is decreasing, then modify the start time to avoid sudden decrease in auction price
        uint256 previousMinPrice = minAuctionPrice[nftCollection];
        if (_minAuctionPrice < previousMinPrice) {
            uint256 _auctionStartTimestamp = auctionStartTimestamp[nftCollection];
            if (_auctionStartTimestamp != 0) {
                uint256 elapsedTime = block.timestamp - _auctionStartTimestamp;
                // calculate the appropriate elapsed time for the same current price
                uint256 startingPrice = _startingPrice(nftCollection);
                // should be less time because price now falls faster -- divide by larger number, multiply by smaller number
                uint256 adjustedElapsedTime =
                    elapsedTime * (startingPrice - previousMinPrice) / (startingPrice - _minAuctionPrice);
                // calculate at set the modified 'start time' of the auction, so the new elapsed time is correctly reflected in the `nftCost` calculation
                auctionStartTimestamp[nftCollection] = (block.timestamp - adjustedElapsedTime);
            }
        }
        minAuctionPrice[nftCollection] = _minAuctionPrice;
        emit MinAuctionPriceSet(nftCollection, _minAuctionPrice);
    }

    function modifyMaxOfferIncreaseRate(address nftCollection, uint256 _maxOfferIncreaseRate) external onlyOwner {
        _modifyMaxOfferIncreaseRate(nftCollection, _maxOfferIncreaseRate);
    }

    function _modifyMaxOfferIncreaseRate(address nftCollection, uint256 _maxOfferIncreaseRate) internal {
        _performCheckpoint(nftCollection, 0);
        maxOfferIncreaseRate[nftCollection] = _maxOfferIncreaseRate;
        emit MaxOfferIncreaseRateSet(nftCollection, _maxOfferIncreaseRate);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setSwapper(address newSwapper) external onlyOwner {
        _setSwapper(newSwapper);
    }

    function _setSwapper(address newSwapper) internal {
        emit SwapperSet(newSwapper);
        swapper = newSwapper;
    }

    /// @notice Called by the `feeRouter` to inform this contract of a fee distribution being performed for the `bToken`, of `amountFees` of the `offerToken`
    function informOfFeeDistribution(address bToken, uint256 amountFees) external {
        require(msg.sender == feeRouter, OnlyFeeRouter());
        address nftCollection = collectionForBToken[bToken];
        require(nftCollection != address(0), NftCollectionNotSetForBToken());

        _performCheckpoint(nftCollection, amountFees);
    }

    function _performCheckpoint(address nftCollection, uint256 amountFees) internal {
        offerAtCheckpoint[nftCollection] = offerPrice(nftCollection);
        lastCheckpointTimestamp[nftCollection] = block.timestamp;
        checkpointBalance[nftCollection] += amountFees;
        emit Checkpoint(nftCollection, offerAtCheckpoint[nftCollection], checkpointBalance[nftCollection]);
    }

    /// @notice Called by the `swapper` to exchange tokens earned from NFT sales for `offerToken` and distribute the proceeds
    /// @dev Proceeds are automatically split according to the fee config for the bToken
    function performSwap(address bToken, uint256 tokensIn, uint256 minOut) external {
        require(msg.sender == swapper, OnlySwapper());
        require(bToken != address(offerToken), CannotSwapOfferToken());
        IERC20(bToken).approve(address(bSwap), tokensIn);
        (
            uint256 amountOut, /*uint256 fee_*/
        ) = bSwap.sellTokensExactIn({_bToken: bToken, _amountIn: tokensIn, _limitAmount: minOut});
        emit SwapPerformed(bToken, tokensIn, amountOut);
        BTokenFeeConfig storage feeConfig = _feeConfig[address(bToken)];
        BTokenRecipients storage recipients = _recipients[address(bToken)];
        uint256 toAfterburner = (amountOut * feeConfig.bpsToAfterburner) / 10_000;
        uint256 toBLV = (amountOut * feeConfig.bpsToBLV) / 10_000;
        if (toAfterburner > 0) IERC20(offerToken).safeTransfer(recipients.afterburner, toAfterburner);
        if (toBLV > 0) IERC20(offerToken).safeTransfer(recipients.blvModule, toBLV);
    }
}
