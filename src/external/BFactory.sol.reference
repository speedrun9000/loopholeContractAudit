// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "solady/src/utils/SafeCastLib.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

import {Component} from "src/Component.sol";
import {BToken} from "src/BToken.sol";

import {State} from "src/libraries/StateLib.sol";
import {GuardLib} from "src/libraries/GuardLib.sol";
import {MakerLib} from "src/libraries/MakerLib.sol";
import {NativeLib} from "src/libraries/NativeLib.sol";

import {BCredit} from "src/components/BCredit.sol";

contract BFactory is Component {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for BToken;
    using PoolIdLibrary for PoolKey;
    using FixedPointMathLib for uint256;
    using SafeCastLib for uint256;
    using NativeLib for ERC20;

    uint8 constant BTOKEN_DECIMALS = 18;
    uint256 constant MAX_STRING_LENGTH = 30;
    uint256 constant MIN_TOTAL_SUPPLY = 10_000e18;

    error NotDeployer();
    error NotApprovedReserve();
    error PoolAlreadyInitialized();
    error TotalSupplyTooLow();
    error TotalSupplyTooHigh();
    error InvalidName();
    error InvalidSymbol();
    error InvalidFeeRecipient();
    error InvalidCreator();
    error InvalidCreatorFee();
    error UnauthorizedCreditPositionCreation();
    error InvalidInitialCollateralOrDebt();
    error InsolventInitialCreditPosition();
    error InvalidPoolSupply();
    error InvalidSalt();
    error InvalidConvexityExp();

    event BTokenCreated(
        BToken bTokenAddress,
        string name,
        string symbol,
        uint8 decimals,
        uint256 totalSupply,
        address creator
    );
    event PoolCreated(
        BToken bTokenAddress,
        address reserveAddress,
        address creator,
        address feeRecipient,
        uint256 creatorFeePct,
        uint256 initialActivePrice,
        uint256 initialBlvPrice,
        uint256 totalReserves,
        uint256 totalBTokens,
        uint256 totalCollateral,
        uint256 totalDebt,
        bytes32 poolId
    );

    struct CreateParams {
        // bToken parameters
        BToken bToken;
        uint256 initialPoolBTokens;
        // reserve parameters
        address reserve;
        uint256 initialPoolReserves;
        // pool parameters
        uint256 initialActivePrice;
        uint256 initialBLV; // Initial/minimum BLV floor price (WAD)
        address creator;
        address feeRecipient; // address that receives the creator fees
        // Percentage of fees that go to the feeRecipient after protocol fees are deducted and before staking fees are deducted
        // The remainder goes to staking.
        uint256 creatorFeePct;
        uint256 swapFeePct;
        bool createHook;
        // initial credit
        bytes32 claimMerkleRoot;
        uint256 initialCollateral;
        uint256 initialDebt;
    }

    //============================================================================================//
    //                                      COMPONENT SETUP                                       //
    //============================================================================================//

    function LABEL() public pure override returns (bytes32) {
        return toLabel(type(BFactory).name);
    }

    function VERSION() public pure override returns (uint256) {
        return 1;
    }

    function ROUTES() public pure override returns (bytes4[] memory routes_) {
        uint256 totalRoutes = 3;
        routes_ = new bytes4[](totalRoutes);
        routes_[--totalRoutes] = this.createBToken.selector;
        routes_[--totalRoutes] = this.createPool.selector;
        routes_[--totalRoutes] = this.precomputeBTokenAddress.selector;
        require(totalRoutes == 0, "BTokenFactory: totalRoutes != 0");
    }

    // #endregion Component Interface
    /////////////////////////////////////////////////////////////////////////////////

    /////////////////////////////////////////////////////////////////////////////////
    // #region Factory Functions

    function createBToken(string memory _name, string memory _symbol, uint256 _totalSupply, bytes32 _salt)
        external
        nonReentrant
        returns (BToken bToken_)
    {
        GuardLib.ensureProtocolNotPaused();
        _validateBTokenParams(_name, _symbol, _totalSupply);
        bToken_ = new BToken{salt: keccak256(abi.encode(msg.sender, _salt))}(_name, _symbol, BTOKEN_DECIMALS, _totalSupply);
        bToken_.safeTransfer(msg.sender, _totalSupply);

        State.meta().deployer[bToken_] = msg.sender;

        State.pool(bToken_).totalSupply = _totalSupply;

        emit BTokenCreated(bToken_, _name, _symbol, BTOKEN_DECIMALS, _totalSupply, msg.sender);
    }

    function createPool(CreateParams calldata params) public payable nonReentrant {
        State.Meta storage meta = State.meta();
        State.Pool storage pool = State.pool(params.bToken);
        GuardLib.ensureNotPaused(pool);
        require(params.creatorFeePct <= 1e18, InvalidCreatorFee());
        require(meta.deployer[params.bToken] == msg.sender, NotDeployer());
        require(meta.approvedReserves[ERC20(params.reserve)], NotApprovedReserve());
        require(pool.reserve == ERC20(address(0)), PoolAlreadyInitialized());
        require(params.creator != address(0), InvalidCreator());
        require(params.feeRecipient != address(0), InvalidFeeRecipient());
        require(
            (params.claimMerkleRoot == bytes32(0) && params.initialCollateral == 0 && params.initialDebt == 0) ||
            (params.claimMerkleRoot != bytes32(0) && params.initialCollateral > 0 && params.initialDebt > 0),
            InvalidInitialCollateralOrDebt()
        );

        // validate merkle credit positions
        uint256 totalReserves = params.initialPoolReserves;
        bool hasCreditPosition = params.claimMerkleRoot != bytes32(0);
        if (hasCreditPosition) {
            // validate that the caller has permission to create merkle credit positions
            require(meta.approvedCreditDeployers[msg.sender], UnauthorizedCreditPositionCreation());
            totalReserves += params.initialDebt;
        }

        // clear deployer
        meta.deployer[params.bToken] = address(0);

        // initialize the hook
        if (params.createHook) _createHook(params, meta);

        // initialize the pool
        pool.reserve = ERC20(params.reserve);
        pool.reserveDecimals = ERC20(params.reserve).decimals();
        pool.bTokenDecimals = params.bToken.decimals();
        pool.totalReserves = totalReserves.toUint128();
        pool.creatorFeePct = params.creatorFeePct.toUint128();
        pool.creator = params.creator;
        pool.feeRecipient = params.feeRecipient;

        pool.totalBTokens = params.initialPoolBTokens.toUint128();
        require(pool.totalSupply >= pool.totalBTokens, InvalidPoolSupply());

        // initialize the staking defaults
        State.staking(params.bToken).lastUpdated = block.timestamp.toUint32();

        // initialize BSwap
        MakerLib.initialize(params.bToken, params.initialActivePrice, params.initialBLV, params.swapFeePct);

        // only executor can create high convexity pools
        require(State.maker(params.bToken).convexityExp == 2e18 || _isExecutor(msg.sender), InvalidConvexityExp());

        // initialize the credit position if it exists
        if (hasCreditPosition) _initializeCreditPosition(params);

        // transfer initial bTokens from caller to the factory
        params.bToken.safeTransferFrom(msg.sender, address(this), params.initialPoolBTokens + params.initialCollateral.toUint128());

        pool.reserve.handleIncoming(msg.sender, params.initialPoolReserves);

        _emitPoolCreated(params);
    }

    function precomputeBTokenAddress(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        bytes32 _salt,
        address _deployer
    ) external view returns (address computedAddress_) {
        _validateBTokenParams(_name, _symbol, _totalSupply);

        bytes32 initcodeHash = keccak256(
            abi.encodePacked(
                type(BToken).creationCode,
                abi.encode(
                    _name,
                    _symbol,
                    BTOKEN_DECIMALS,
                    _totalSupply
                )
            )
        );

        bytes32 salt = keccak256(abi.encode(_deployer, _salt));

        computedAddress_ = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            salt,
                            initcodeHash
                        )
                    )
                )
            )
        );

        require(computedAddress_.code.length == 0, InvalidSalt());
    }

    function _validateBTokenParams(string memory _name, string memory _symbol, uint256 _totalSupply) internal pure {
        require(bytes(_name).length <= MAX_STRING_LENGTH, InvalidName());
        require(bytes(_symbol).length <= MAX_STRING_LENGTH, InvalidSymbol());
        require(_totalSupply >= MIN_TOTAL_SUPPLY, TotalSupplyTooLow());
        require(_totalSupply <= type(uint128).max, TotalSupplyTooHigh());
    }

    function _createHook(CreateParams calldata _params, State.Meta storage _meta) private {
        IPoolManager poolManager = _meta.poolManager;
        State.Hook storage hook = State.hook(_params.bToken);

        bool bTokenIsZero = address(_params.bToken) < address(_params.reserve);

        // construct the pool key
        PoolKey memory poolKey = PoolKey({
            currency0: bTokenIsZero ? Currency.wrap(address(_params.bToken)) : Currency.wrap(address(_params.reserve)),
            currency1: bTokenIsZero ? Currency.wrap(address(_params.reserve)) : Currency.wrap(address(_params.bToken)),
            fee: 0,
            tickSpacing: 1,
            hooks: IHooks(address(this))
        });

        // initialize the pool
        poolManager.initialize(poolKey, TickMath.getSqrtPriceAtTick(0));

        // update the state
        _meta.poolToBToken[PoolId.unwrap(poolKey.toId())] = _params.bToken;
        hook.poolKey = poolKey;
    }

    function _initializeCreditPosition(CreateParams calldata _params) private {
        State.Credit storage credit = State.credit(_params.bToken);

        credit.claimMerkleRoot = _params.claimMerkleRoot;

        // add initial collateral and debt to the proxy credit account (for claiming later)
        credit.accounts[address(this)].collateral = _params.initialCollateral.toUint128();
        credit.accounts[address(this)].debt = _params.initialDebt.toUint128();


        credit.totalCollateral += _params.initialCollateral.toUint128();
        credit.totalDebt += _params.initialDebt.toUint128();

        // ensure that the initial credit position is valid
        (uint256 maxBorrow,uint256 fee) = BCredit(address(this)).getBorrowForCollateral(_params.bToken, _params.initialCollateral);
        require(
            maxBorrow + fee >= _params.initialDebt,
            InsolventInitialCreditPosition()
        );
    }

    function _emitPoolCreated(CreateParams calldata _params) private {
        emit PoolCreated(
            _params.bToken,
            _params.reserve,
            _params.creator,
            _params.feeRecipient,
            _params.creatorFeePct,
            _params.initialActivePrice,
            State.maker(_params.bToken).blvPrice,
            _params.initialPoolReserves,
            _params.initialPoolBTokens,
            _params.initialCollateral,
            _params.initialDebt,
            PoolId.unwrap(State.hook(_params.bToken).poolKey.toId())
        );
    }

    // #endregion Factory Functions
    /////////////////////////////////////////////////////////////////////////////////
}
