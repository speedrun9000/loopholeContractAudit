// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {MerkleProofLib} from "solady/src/utils/MerkleProofLib.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "solady/src/utils/SafeCastLib.sol";

import {Component} from "src/Component.sol";

import {BSwap} from "src/components/BSwap.sol";
import {BStaking} from "src/components/BStaking.sol";

import {State} from "src/libraries/StateLib.sol";
import {FeeLib} from "src/libraries/FeeLib.sol";
import {CollateralLib} from "src/libraries/CollateralLib.sol";
import {NormalizeLib} from "src/libraries/NormalizeLib.sol";
import {SwapContextLib} from "src/libraries/SwapContextLib.sol";
import {CurveLib} from "src/libraries/CurveLib.sol";
import {MakerLib} from "src/libraries/MakerLib.sol";
import {GuardLib} from "src/libraries/GuardLib.sol";
import {NativeLib} from "src/libraries/NativeLib.sol";

import {BToken} from "src/BToken.sol";

contract BCredit is Component {
    using SafeCastLib for uint256;
    using SafeCastLib for int256;
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for uint128;
    using FixedPointMathLib for int256;
    using NativeLib for ERC20;
    using FeeLib for State.Pool;
    using CollateralLib for State.Staking;

    /////////////////////////////////////////////////////////////////////////////////
    // #region Events

    event Borrow(BToken bToken, address user, uint256 borrowed, uint256 fee, State.CreditAccount post);
    event Repay(BToken bToken, address user, uint256 collateralRedeemed, uint256 debtRepaid, State.CreditAccount post);
    event CreditClaim(BToken bToken, address[] users, uint128[] collaterals, uint128[] debts);

    event Leverage(
        BToken bToken,
        address user,
        uint256 collateralAdded,
        uint256 debtAdded,
        uint256 collateralIn,
        uint256 reservesIn,
        State.CreditAccount post
    );
    event Deleverage(
        BToken bToken,
        address user,
        uint256 collateralRedeemed,
        uint256 debtRepaid,
        uint256 collateralSold,
        uint256 refund,
        State.CreditAccount post
    );

    // #endregion Events
    /////////////////////////////////////////////////////////////////////////////////

    /////////////////////////////////////////////////////////////////////////////////
    // #region Errors

    error BCredit_InsufficientCollateral();
    error BCredit_RepaidMoreThanDebt();
    error BCredit_NoClaimMerkleRoot();
    error BCredit_InvalidClaim();
    error BCredit_InvalidClaimLength();
    error BCredit_AlreadyClaimed();
    error BCredit_InvalidProof();
    error BCredit_CannotRepayContract();
    error BCredit_Leverage_ZeroCollateral();
    error BCredit_Leverage_InvalidStakedAmount();
    error BCredit_Leverage_BorrowAmountTooLow();
    error BCredit_Deleverage_InvalidCollateralToSell();
    error BCredit_Deleverage_Undercollateralized();
    error BCredit_SystemClaim_Undercollateralized();
    error BCredit_UserClaim_Undercollateralized();

    // #endregion Errors
    /////////////////////////////////////////////////////////////////////////////////

    /////////////////////////////////////////////////////////////////////////////////
    // #region Component Interface

    function LABEL() public pure override returns (bytes32) {
        return toLabel(type(BCredit).name);
    }

    function VERSION() public pure override returns (uint256) {
        return 1;
    }

    function ROUTES() public pure override returns (bytes4[] memory routes_) {
        uint256 totalRoutes = 12;
        routes_ = new bytes4[](totalRoutes);

        routes_[--totalRoutes] = this.borrow.selector;
        routes_[--totalRoutes] = this.borrowNative.selector;
        routes_[--totalRoutes] = this.repay.selector;
        routes_[--totalRoutes] = this.repayWithNative.selector;
        routes_[--totalRoutes] = this.leverage.selector;
        routes_[--totalRoutes] = this.deleverage.selector;
        routes_[--totalRoutes] = this.getMaxBorrow.selector;
        routes_[--totalRoutes] = this.previewBorrow.selector;
        routes_[--totalRoutes] = this.previewRepay.selector;
        routes_[--totalRoutes] = this.getBorrowForCollateral.selector;
        routes_[--totalRoutes] = this.claimCredit.selector;
        routes_[--totalRoutes] = this.previewDepositAndBorrow.selector;

        require(totalRoutes == 0, "totalRoutes != 0");
    }

    // #endregion Component Interface
    /////////////////////////////////////////////////////////////////////////////////

    /////////////////////////////////////////////////////////////////////////////////
    // #region Lending Functions

    function borrow(BToken _bToken, uint256 _amount, address _recipient) public nonReentrant whenNotPaused(_bToken) {
        if (_amount == 0) return;
        ERC20 reserve = State.pool(_bToken).reserve;
        _borrow(_bToken, msg.sender, _amount);
        reserve.handleOutgoing(_recipient, _amount, false);
    }

    function borrowNative(
        BToken _bToken,
        uint256 _amount,
        address _recipient
    ) public nonReentrant whenNotPaused(_bToken) {
        if (_amount == 0) return;
        ERC20 reserve = State.pool(_bToken).reserve;
        _borrow(_bToken, msg.sender, _amount);
        reserve.handleOutgoing(_recipient, _amount, true);
    }

    function repay(BToken _bToken, uint256 _reservesIn, address _recipient) public nonReentrant whenNotPaused(_bToken) {
        if (_reservesIn == 0) return;
        ERC20 reserve = State.pool(_bToken).reserve;
        _repay(_bToken, _recipient, _reservesIn);
        reserve.handleIncoming(msg.sender, _reservesIn);
    }

    function repayWithNative(BToken _bToken, address _recipient) public payable nonReentrant whenNotPaused(_bToken) {
        if (msg.value == 0) return;
        ERC20 reserve = State.pool(_bToken).reserve;
        _repay(_bToken, _recipient, msg.value);
        reserve.handleIncoming(msg.sender, msg.value);
    }

    struct ClaimCreditCache {
        uint256 totalUsers;
        bytes32 root;
        uint128 totalCollateral;
        uint128 totalDebt;
    }

    struct ProcessClaimParams {
        address user;
        uint128 collateral;
        uint128 debt;
        bytes32[] proofs;
    }

    /// @dev only one user per leaf in the merkle tree
    function claimCredit(
        BToken _bToken,
        address[] calldata _users,
        uint128[] calldata _collaterals,
        uint128[] calldata _debts,
        bytes32[][] calldata _proofs
    ) public nonReentrant whenNotPaused(_bToken) {
        State.Credit storage credit = State.credit(_bToken);
        State.Staking storage staking = State.staking(_bToken);
        ClaimCreditCache memory cache;

        cache.root = credit.claimMerkleRoot;
        cache.totalUsers = _users.length;

        require(cache.root != bytes32(0), BCredit_NoClaimMerkleRoot());
        require(
            cache.totalUsers == _collaterals.length
            && cache.totalUsers == _debts.length
            && cache.totalUsers == _proofs.length, 
            BCredit_InvalidClaimLength()
        );

        for (uint256 i; i < cache.totalUsers; i++) {

            ProcessClaimParams memory params = ProcessClaimParams({
                user: _users[i],
                collateral: _collaterals[i],
                debt: _debts[i],
                proofs: _proofs[i]
            });
            _processClaim(_bToken, staking, credit, params, cache.root);
            cache.totalCollateral += params.collateral;
            cache.totalDebt += params.debt;
        }

        // batch update the system credit account
        credit.accounts[address(this)].collateral -= cache.totalCollateral;
        credit.accounts[address(this)].debt -= cache.totalDebt;

        // ensure the system credit account is not undercollateralized
        (uint256 borrowableAmount, uint256 fee) = getBorrowForCollateral(_bToken, credit.accounts[address(this)].collateral);
        require(credit.accounts[address(this)].debt <= borrowableAmount + fee, BCredit_SystemClaim_Undercollateralized());

        GuardLib.ensureStakingSupply(_bToken);

        emit CreditClaim(_bToken, _users, _collaterals, _debts);
    }

    function _processClaim(
        BToken _bToken,
        State.Staking storage staking,
        State.Credit storage credit,
        ProcessClaimParams memory params,
        bytes32 _root
    ) internal {
        require(params.user != address(0) && params.user != address(this), BCredit_InvalidClaim());
        require(!credit.claimed[params.user], BCredit_AlreadyClaimed());

        bytes32 leaf = keccak256(
            bytes.concat(
                keccak256(
                    abi.encode(params.user, abi.encode(params.collateral, params.debt))
                )
            )
        );
        require(MerkleProofLib.verify(params.proofs, _root, leaf), BCredit_InvalidProof());

        credit.claimed[params.user] = true;

        BStaking(address(this)).deposit(_bToken, params.user, params.collateral);
        staking.lockCollateral(params.user, params.collateral);

        uint256 newUserCollateral = credit.accounts[params.user].collateral += params.collateral;
        uint256 newUserDebt = credit.accounts[params.user].debt += params.debt;
        (uint256 borrowableAmount, uint256 fee) = getBorrowForCollateral(_bToken, newUserCollateral);

        require(newUserDebt <= borrowableAmount + fee, BCredit_UserClaim_Undercollateralized());
    }

    // #endregion Lending Functions
    /////////////////////////////////////////////////////////////////////////////////

    /////////////////////////////////////////////////////////////////////////////////
    // #region Leverage Functions


    function leverage(
        BToken _bToken,
        uint256 _totalCollateral,
        uint256 _collateralIn,
        uint256 _maxSwapReservesIn
    ) external nonReentrant whenNotPaused(_bToken) returns (uint256 debt_){
        State.Credit storage credit = State.credit(_bToken);
        State.CreditAccount memory account = credit.accounts[msg.sender];

        // sanity check user input
        require(_totalCollateral > 0, BCredit_Leverage_ZeroCollateral());
        require(_collateralIn < _totalCollateral, BCredit_Leverage_InvalidStakedAmount());

        // calculate the debt to be borrowed given the _totalCollateral
        (uint256 borrowableAmount,) = getBorrowForCollateral(_bToken, _totalCollateral);

        // calculate amount of collateral to buy from swap and pre-deposit it
        uint256 collateralFromSwap = _totalCollateral - _collateralIn;
        BStaking(address(this)).deposit(_bToken, msg.sender, collateralFromSwap);
        State.staking(_bToken).lockCollateral(msg.sender, _totalCollateral);

        // set caller as user for the swap event
        SwapContextLib.setCaller(msg.sender);

        // buy the collateral that will back the newly borrowed debt (funded by the borrow)
        (uint256 reservesIn,) = BSwap(address(this)).buyTokensExactOut({
            _bToken: _bToken,
            _amountOut: collateralFromSwap,
            _limitAmount: _maxSwapReservesIn
        });

        // ensure the swap didn't consume more reserves than were available.
        require(reservesIn <= borrowableAmount, BCredit_Leverage_BorrowAmountTooLow());

        // compute the fee and the debt being added to the user's account
        debt_ = reservesIn.divWadUp(1e18 - State.meta().originationFee);
        uint256 fee = debt_ - reservesIn;

        // Update user credit account
        account.collateral += _totalCollateral.toUint128();
        account.debt += debt_.toUint128();
        credit.accounts[msg.sender] = account;

        // Update totals
        credit.totalCollateral += _totalCollateral.toUint128();
        credit.totalDebt += debt_.toUint128();

        // distribute the fee portion of the borrow
        State.pool(_bToken).distributeFees(_bToken, fee);

        GuardLib.ensureSolvent(_bToken);
        GuardLib.ensureStakingSupply(_bToken);

        emit Leverage(_bToken, msg.sender, _totalCollateral, debt_, _collateralIn, reservesIn, account);
    }
  
    function deleverage(
        BToken _bToken,
        uint256 _collateralToSell,
        uint256 _minSwapReservesOut
    ) external nonReentrant whenNotPaused(_bToken) returns (
        uint256 collateralRedeemed_,
        uint256 debtRepaid_,
        uint256 refund_
    ) {
        State.Credit storage credit = State.credit(_bToken);
        State.CreditAccount memory account = credit.accounts[msg.sender];

        require(_collateralToSell > 0 && _collateralToSell <= account.collateral, BCredit_Deleverage_InvalidCollateralToSell());

        // set caller as user for the swap event
        SwapContextLib.setCaller(msg.sender);

        // sell the collateral to repay the debt
        (uint256 reservesOut,) = BSwap(address(this)).sellTokensExactIn({
            _bToken: _bToken,
            _amountIn: _collateralToSell,
            _limitAmount: _minSwapReservesOut
        });

        if (reservesOut >= account.debt) {

            // the user has completely deleveraged so we can zero out their collateral and debt
            collateralRedeemed_ = account.collateral;
            debtRepaid_ = account.debt;

            // when reservesOut is greater than account.debt the user receives a refund in reserve tokens
            refund_ = reservesOut - account.debt;

        } else {

            // the user has only partially deleveraged so we need to calculate the amount of collateral and debt to redeem
            collateralRedeemed_ = _collateralToSell;
            debtRepaid_ = reservesOut;

            // ensure the user's new position after deleveraging is fully collateralized
            (uint256 maxBorrow, uint256 fee) = getBorrowForCollateral(_bToken, account.collateral - _collateralToSell);
            require(maxBorrow + fee >= account.debt - reservesOut, BCredit_Deleverage_Undercollateralized());
        }

        // update the user's account state
        account.collateral -= collateralRedeemed_.toUint128();
        account.debt -= debtRepaid_.toUint128();
        credit.accounts[msg.sender] = account;

        // update the total credit account state
        credit.totalCollateral -= collateralRedeemed_.toUint128();
        credit.totalDebt -= debtRepaid_.toUint128();

        // unlock redeemed collateral (all collateral on full deleverage, sold amount on partial)
        State.staking(_bToken).unlockCollateral(msg.sender, collateralRedeemed_);

        // remove the collateral that was used in the swap from the user's account
        // the difference between collateralRedeemed_ and _tokenDelta is the users profit in bTokens
        BStaking(address(this)).liquidate(_bToken, msg.sender, _collateralToSell);

        GuardLib.ensureSolvent(_bToken);
        GuardLib.ensureStakingSupply(_bToken);

        if (refund_ > 0) State.pool(_bToken).reserve.handleOutgoing(msg.sender, refund_, true);

        emit Deleverage(_bToken, msg.sender, collateralRedeemed_, debtRepaid_, _collateralToSell, refund_, account);
    }

    // #endregion Leverage Functions
    /////////////////////////////////////////////////////////////////////////////////

    /////////////////////////////////////////////////////////////////////////////////
    // #region Internal Functions

    /// @param _bToken The BToken contract address
    /// @param _user The user address to borrow for
    /// @param _amount The amount of tokens to borrow
    function _borrow(BToken _bToken, address _user, uint256 _amount) internal {
        State.Staking storage staking = State.staking(_bToken);
        State.Credit storage credit = State.credit(_bToken);

        State.CreditAccount memory account = credit.accounts[_user];
        uint256 unlocked = staking.unlocked(_user);

        (uint256 collateral, uint256 debt, uint256 fee) = _previewBorrow(_bToken, account, unlocked, _amount);

        if (collateral > 0) {
            account.collateral += collateral.toUint128();
            credit.totalCollateral += collateral.toUint128();
            staking.lockCollateral(_user, collateral);
        }

        account.debt += debt.toUint128();
        credit.totalDebt += debt.toUint128();

        credit.accounts[_user] = account;

        State.pool(_bToken).distributeFees(_bToken, fee);

        GuardLib.ensureSolvent(_bToken);
        GuardLib.ensureStakingSupply(_bToken);

        emit Borrow(_bToken, _user, _amount, fee, account);
    }

    function _repay(BToken _bToken, address _recipient, uint256 _reservesIn) internal {
        require(_recipient != address(this), BCredit_CannotRepayContract());
        State.Staking storage staking = State.staking(_bToken);
        State.Credit storage credit = State.credit(_bToken);
        State.CreditAccount memory account = credit.accounts[_recipient];

        require(_reservesIn <= account.debt, BCredit_RepaidMoreThanDebt());

        uint256 collateralRedeemed = _previewRepay(account, _reservesIn);

        // Update state
        account.collateral -= collateralRedeemed.toUint128();
        account.debt -= _reservesIn.toUint128();
        credit.accounts[_recipient] = account;

        credit.totalCollateral -= collateralRedeemed.toUint128();
        credit.totalDebt -= _reservesIn.toUint128();

        // Return collateral to stake
        staking.unlockCollateral(_recipient, collateralRedeemed);

        emit Repay(_bToken, _recipient, collateralRedeemed, _reservesIn, account);
    }

    // #endregion Internal Functions
    /////////////////////////////////////////////////////////////////////////////////

    /////////////////////////////////////////////////////////////////////////////////
    // #region View Functions

    // Expects amount of collateral to be used, calculates debt out and the fee charged.
    function getBorrowForCollateral(BToken _bToken, uint256 _collateral) public view returns (uint256 borrowAmount_, uint256 fee_) {
        State.Pool storage pool = State.pool(_bToken);
        // Convert collateral to debt using WAD-stored blvPrice
        uint8 bDec = pool.bTokenDecimals;
        uint8 rDec = pool.reserveDecimals;
        uint256 blv = State.maker(_bToken).blvPrice;  // WAD
        uint256 feeRate = State.meta().originationFee;

        uint256 collateralWad = NormalizeLib.normalizeWad(_collateral, bDec);
        uint256 debtWad = blv.mulWad(collateralWad);
        uint256 debt = NormalizeLib.denormalizeWad(debtWad, rDec);

        fee_ = debt.mulWadUp(feeRate);
        borrowAmount_ = debt - fee_;
    }

    /// @notice Get maximum borrowable amount by a user
    function getMaxBorrow(BToken _bToken, address _user) external view returns (uint256 maxBorrow_) {
        State.Pool storage pool = State.pool(_bToken);
        State.CreditAccount memory account = State.credit(_bToken).accounts[_user];
        uint256 unlocked = State.staking(_bToken).unlocked(_user);

        // Convert collateral to debt capacity using WAD-stored blvPrice
        uint8 bDec = pool.bTokenDecimals;
        uint8 rDec = pool.reserveDecimals;
        uint256 blv = State.maker(_bToken).blvPrice;  // WAD
        uint256 collateralWad = NormalizeLib.normalizeWad(unlocked + account.collateral, bDec);
        uint256 debtWad = blv.mulWad(collateralWad);
        uint256 maxDebt = NormalizeLib.denormalizeWad(debtWad, rDec);  // floor for conservative limit

        // borrow and leverage have slightly different rounding behavior, so we need to handle this edge case
        uint256 availableDebt = maxDebt - account.debt;

        maxBorrow_ = availableDebt.mulWad(1e18 - State.meta().originationFee);
    }

    function previewBorrow(BToken _bToken, address _user, uint256 _borrowAmount) external view returns (uint256 collateral_, uint256 debt_, uint256 fee_) {
        State.CreditAccount memory account = State.credit(_bToken).accounts[_user];
        uint256 unlocked = State.staking(_bToken).unlocked(_user);
        (collateral_, debt_, fee_) = _previewBorrow(_bToken, account, unlocked, _borrowAmount);
    }

    function previewDepositAndBorrow(BToken _bToken, address _user, uint256 _depositAmount, uint256 _borrowAmount) external view returns (uint256 collateral_, uint256 debt_, uint256 fee_) {
        State.CreditAccount memory account = State.credit(_bToken).accounts[_user];
        uint256 unlocked = State.staking(_bToken).unlocked(_user) + _depositAmount;
        (collateral_, debt_, fee_) = _previewBorrow(_bToken, account, unlocked, _borrowAmount);
    }

    function previewRepay(
        BToken _bToken,
        address _recipient,
        uint256 _reservesIn
    ) public view returns (
        uint256 collateralRedeemed_,
        uint256 debtRepaid_
    ) {
        State.CreditAccount memory account = State.credit(_bToken).accounts[_recipient];
        debtRepaid_ = FixedPointMathLib.min(_reservesIn, account.debt);
        collateralRedeemed_ = _previewRepay(account, debtRepaid_);
    }

    function _previewRepay(
        State.CreditAccount memory _account,
        uint256 _reservesIn
    ) internal pure returns (
        uint256 collateralRedeemed_
    ) {
        if (_account.debt == 0) return 0;

        // calculate the collateral to be redeemed
        collateralRedeemed_ = uint256(_account.collateral).mulDiv(_reservesIn, _account.debt);
    }

    function _previewBorrow(
        BToken _bToken,
        State.CreditAccount memory _account,
        uint256 _unlockedStake,
        uint256 _borrowAmount
    ) internal view returns (
        uint256 collateral_,
        uint256 debt_,
        uint256 fee_
    ) {
        State.Pool storage pool = State.pool(_bToken);
        // debt = borrow amount + fee
        debt_ = _borrowAmount.divWadUp(1e18 - State.meta().originationFee);

        uint256 newTotalDebt = _account.debt + debt_;
        uint256 maxCollateral = _account.collateral + _unlockedStake;

        // Convert collateral to debt capacity using WAD-stored blvPrice
        uint256 blv = State.maker(_bToken).blvPrice;  // WAD
        uint256 collateralWad = NormalizeLib.normalizeWad(maxCollateral, pool.bTokenDecimals);
        uint256 debtWad = blv.mulWad(collateralWad);
        uint256 maxDebt = NormalizeLib.denormalizeWad(debtWad, pool.reserveDecimals);  // floor for conservative limit

        // get the current ratio of debt to the max possible debt
        uint256 debtRatio = newTotalDebt.divWadUp(maxDebt);

        // use debt ratio to find out how much of the max collateral is needed to cover the debt
        uint256 collateralRequired = maxCollateral.mulWadUp(debtRatio);

        // set the collateral_ to the amount of collateral needed to cover the new debt
        if (collateralRequired > _account.collateral) {
            collateral_ = collateralRequired - _account.collateral;
        }

        fee_ = debt_ - _borrowAmount;
    }

    // #endregion View Functions
    /////////////////////////////////////////////////////////////////////////////////

}