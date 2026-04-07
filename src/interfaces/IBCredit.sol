// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IBCredit {
    function leverage(address _bToken, uint256 _totalCollateral, uint256 _collateralIn, uint256 _maxSwapReservesIn)
        external
        returns (uint256 debt_);

    function deleverage(address _bToken, uint256 _collateralToSell, uint256 _minSwapReservesOut)
        external
        returns (uint256 collateralRedeemed_, uint256 debtRepaid_, uint256 refund_);

    function borrow(address _bToken, uint256 _amount, address _recipient) external;

    function borrowNative(address _bToken, uint256 _amount, address _recipient) external;

    function repay(address _bToken, uint256 _reservesIn, address _recipient) external;

    function repayWithNative(address _bToken, address _recipient) external payable;

    function claimCredit(
        address _bToken,
        address[] calldata _users,
        uint128[] calldata _collaterals,
        uint128[] calldata _debts,
        bytes32[][] calldata _proofs
    ) external;

    function defaultSelf(address _bToken) external;

    function getMaxBorrow(address _bToken, address _user) external view returns (uint256 maxBorrow_);

    function getBorrowForCollateral(address _bToken, uint256 _collateral)
        external
        view
        returns (uint256 borrowAmount_, uint256 fee_);

    function previewBorrow(address _bToken, address _user, uint256 _borrowAmount)
        external
        view
        returns (uint256 collateral_, uint256 debt_, uint256 fee_);

    function previewDepositAndBorrow(address _bToken, address _user, uint256 _depositAmount, uint256 _borrowAmount)
        external
        view
        returns (uint256 collateral_, uint256 debt_, uint256 fee_);

    function previewRepay(address _bToken, address _recipient, uint256 _reservesIn)
        external
        view
        returns (uint256 collateralRedeemed_);
}
