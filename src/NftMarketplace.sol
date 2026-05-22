// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {IBSwap} from "./interfaces/IBswap.sol";
import {IBStaking} from "./interfaces/IBStaking.sol";

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

    /// @dev Used for distributing bTokens from NFT sales
    struct BTokenRecipients {
        address afterburner;
        address blvModule;
    }

    struct PurchaseHistoryAggregators {
        // cumulative number of NFTs purchased from the collection
        uint256 numPurchases;
        // cumulative total of `bTokenForCollection[collection]` paid for the above NFTs
        uint256 cumulativeWethValuePaid;
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
    event StakingRewardsClaimed(address indexed bToken, address indexed collection, uint256 amount);

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
    error SalePriceCannotBeZero();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice ERC20 accepted by this contract in exchange for NFTs
    IERC20 public WETH;

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

    /// @notice Mapping: NFT collection address => The amount of `bTokenForCollection[collection]` held by this contract
    ///        at `lastCheckpointTimestamp[collection]`, which are specifically from fees credited to the collection
    mapping(address => uint256) public checkpointBalance;

    /// @notice Mapping: NFT collection address => the amount of `bTokenForCollection[collection]` which was offered by this contract
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

    /// @notice Mapping: NFT collection address => sales proceeds in `WETH` made from selling NFTs from the collection
    mapping(address => uint256) public nftSalesProceeds;

    /// @notice Fee split config per bToken
    mapping(address => BTokenFeeConfig) internal _feeConfig;

    /// @notice Recipient addresses per bToken
    mapping(address => BTokenRecipients) internal _recipients;

    /// @notice Mapping: NFT collection address => summary of purchases
    mapping(address => PurchaseHistoryAggregators) internal _purchaseHistoryAggregators;

    /// @dev Storage gap for future upgrades
    uint256[50] private __gap;

    /*//////////////////////////////////////////////////////////////
                              INITIALIZER
    //////////////////////////////////////////////////////////////*/
    constructor() {
        _disableInitializers();
    }

    function initialize(IERC20 _WETH, address _feeRouter, address initialOwner, IBSwap _bSwap, address _swapper)
        external
        initializer
    {
        WETH = _WETH;
        feeRouter = _feeRouter;
        __Ownable_init(initialOwner);
        __Pausable_init();
        bSwap = _bSwap;
        _setSwapper(_swapper);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice The current amount of `bTokenForCollection[collection]` offered by this contract for an NFT from `nftCollection`, at the present time.
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

    /// @dev Returns 20x the maximum of (observed mean price, current min price)
    function _startingPrice(address nftCollection) internal view returns (uint256) {
        PurchaseHistoryAggregators storage pha = _purchaseHistoryAggregators[nftCollection];
        return 20 * Math.max(pha.cumulativeWethValuePaid / pha.numPurchases, minAuctionPrice[nftCollection]);
    }

    /*//////////////////////////////////////////////////////////////
                            STATE-MODIFYING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Sells the `tokenId` of `nftCollection` to this contract for `offerPrice(nftCollection)` in `bTokenForCollection[nftCollection]`
    /// @dev Will revert if `minPrice > offerPrice(nftCollection)`, ensuring the user receives *at least* `minPrice`
    function sellNftToVault(address nftCollection, uint256 tokenId, uint256 minPrice) external whenNotPaused {
        uint256 _currentOffer = offerPrice(nftCollection);
        require(_currentOffer != 0, SalePriceCannotBeZero());
        /// taking a minPrice input + reverting here deals with a potential race condition where one user sells this contract an NFT
        /// after another user sends a tx but before the second user's tx lands
        require(minPrice <= _currentOffer, InvalidSalePriceInput());

        IERC721(nftCollection).transferFrom(msg.sender, address(this), tokenId);

        lastCheckpointTimestamp[nftCollection] = block.timestamp;
        // reduce checkpoint balance by the outgoing amount
        checkpointBalance[nftCollection] -= _currentOffer;
        // set offer to the minimum of (a) 75% of the price being paid and (b) the token balance of this contract after the payment
        offerAtCheckpoint[nftCollection] = Math.min(_currentOffer * 75 / 100, checkpointBalance[nftCollection]);

        // update purchase aggregators for the collection
        PurchaseHistoryAggregators storage pha = _purchaseHistoryAggregators[nftCollection];
        pha.numPurchases += 1;
        // convert bToken value to WETH for tracking purposes
        // TODO: look at manipulability of this -- perhaps consider reversion if bSwap address is "hot" when this fnc is called
        (
            uint256 wethValue,
            /* uint256 feesReceived_ */, /* uint256 slippage_ */
        ) = bSwap.quoteSellExactIn({_bToken: bTokenForCollection[nftCollection], _amountIn: _currentOffer});
        pha.cumulativeWethValuePaid += wethValue;

        // update the min auction price for the collection
        uint256 updatedMeanAcquisitionPrice = pha.cumulativeWethValuePaid / pha.numPurchases;
        uint256 existingMinAuctionPrice = minAuctionPrice[nftCollection];
        // in this case, simply increase minAuctionPrice to the new mean acquisition price
        if (updatedMeanAcquisitionPrice > existingMinAuctionPrice) {
            _modifyMinAuctionPrice(nftCollection, updatedMeanAcquisitionPrice);
            /// in this case, we will decrease the min auction price, but want it to be stickier, so we
            /// sum 95% of the old minimum with 5% of the new mean acquisition, which caps the decrease at 5% of the current value
            /// The realized decrease should be 5% of the difference between the new mean and the existing min.
        } else {
            uint256 newAuctionMin = (existingMinAuctionPrice * 0.95e18 + updatedMeanAcquisitionPrice * 0.05e18) / 1e18;
            // use Math.min to address the edge case where newAuctionMin would be less than the startingPrice
            _modifyMinAuctionPrice(nftCollection, newAuctionMin);
        }

        emit NftAcquired(nftCollection, msg.sender, tokenId, _currentOffer);
        // start auction for the NFT if one is not already ongoing
        startAuction(nftCollection);
        IBStaking(address(bSwap)).withdraw(bTokenForCollection[nftCollection], _currentOffer);
        IERC20(bTokenForCollection[nftCollection]).safeTransfer(msg.sender, _currentOffer);
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

    /// @notice Buys the `tokenId` of `nftCollection` from this contract, for `nftCost(nftCollection)` in `WETH`
    /// @dev Caller will make payment in `WETH`
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

        nftSalesProceeds[nftCollection] += _currentPrice;

        WETH.safeTransferFrom(msg.sender, address(this), _currentPrice);

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
        // _modifyMaxOfferIncreaseRate performs the first checkpoint, which initializes lastCheckpointTimestamp
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
                // calculate the appropriate elapsed time for the same current price
                uint256 currentPrice = nftCost(nftCollection);
                PurchaseHistoryAggregators storage pha = _purchaseHistoryAggregators[nftCollection];
                // emulate the behavior of the `startingPrice()` function but using the new `_minAuctionPrice` instead of the current one
                uint256 newStartingPrice =
                    20 * Math.max(pha.cumulativeWethValuePaid / pha.numPurchases, _minAuctionPrice);
                uint256 adjustedElapsedTime = newStartingPrice > currentPrice
                    ? (newStartingPrice - currentPrice) * auctionDuration[nftCollection]
                        / (newStartingPrice - _minAuctionPrice)
                    : 0;
                // calculate and set the modified 'start time' of the auction, so the new elapsed time is correctly reflected in the `nftCost` calculation
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

    /// @notice Called by the `feeRouter` to inform this contract of a fee distribution being performed for the `bToken`, of `amountFees` of the `bToken`
    function informOfFeeDistribution(address bToken, uint256 amountFees) external whenNotPaused {
        require(msg.sender == feeRouter, OnlyFeeRouter());
        address nftCollection = collectionForBToken[bToken];
        require(nftCollection != address(0), NftCollectionNotSetForBToken());

        _performCheckpoint(nftCollection, amountFees);
        _stakeBToken(bToken, amountFees);
    }

    /// @notice Permissionless function, allowing the caller to donate `amount` of `bToken`, to be treated like fees for the `bToken`
    function donate(address bToken, uint256 amount) external whenNotPaused {
        address nftCollection = collectionForBToken[bToken];
        require(nftCollection != address(0), NftCollectionNotSetForBToken());

        _performCheckpoint(nftCollection, amount);
        IERC20(bToken).safeTransferFrom(msg.sender, address(this), amount);
        _stakeBToken(bToken, amount);
    }

    function claimStakingRewards(address bToken) external returns (uint256 earned) {
        address nftCollection = collectionForBToken[bToken];
        require(nftCollection != address(0), NftCollectionNotSetForBToken());

        earned = IBStaking(address(bSwap)).claim(bToken, address(this), false);
        nftSalesProceeds[nftCollection] += earned;
        emit StakingRewardsClaimed(bToken, nftCollection, earned);
    }

    function _performCheckpoint(address nftCollection, uint256 amountFees) internal {
        offerAtCheckpoint[nftCollection] = offerPrice(nftCollection);
        lastCheckpointTimestamp[nftCollection] = block.timestamp;
        checkpointBalance[nftCollection] += amountFees;
        emit Checkpoint(nftCollection, offerAtCheckpoint[nftCollection], checkpointBalance[nftCollection]);
    }

    function _stakeBToken(address bToken, uint256 amount) internal {
        if (amount == 0) return;
        IERC20(bToken).forceApprove(address(bSwap), amount);
        IBStaking(address(bSwap)).deposit(bToken, address(this), amount);
    }

    /// @notice Called by the `swapper` to exchange `WETH` tokens earned from NFT sales for bTokens and distribute the proceeds
    /// @dev Proceeds are automatically split according to the fee config for the bToken
    function performSwap(address bToken, uint256 tokensIn, uint256 minOut) external {
        require(msg.sender == swapper, OnlySwapper());
        require(bToken != address(WETH), CannotSwapOfferToken());
        address nftCollection = collectionForBToken[bToken];
        nftSalesProceeds[nftCollection] -= tokensIn;
        IERC20(WETH).approve(address(bSwap), tokensIn);
        (
            uint256 amountOut, /*uint256 feesReceived_*/
        ) = bSwap.buyTokensExactIn({_bToken: bToken, _amountIn: tokensIn, _limitAmount: minOut});
        emit SwapPerformed(bToken, tokensIn, amountOut);
        BTokenFeeConfig storage feeConfig = _feeConfig[address(bToken)];
        BTokenRecipients storage recipients = _recipients[address(bToken)];
        uint256 toAfterburner = (amountOut * feeConfig.bpsToAfterburner) / 10_000;
        uint256 toBLV = (amountOut * feeConfig.bpsToBLV) / 10_000;
        if (toAfterburner > 0) IERC20(bToken).safeTransfer(recipients.afterburner, toAfterburner);
        if (toBLV > 0) IERC20(bToken).safeTransfer(recipients.blvModule, toBLV);
    }
}
