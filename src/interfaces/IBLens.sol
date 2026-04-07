// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IBLens {
    function quoteLeverage(address _bToken, uint256 _collateralIn, uint256 _leverageFactor)
        external
        view
        returns (uint256 targetCollateral_, uint256 maxSwapReservesIn_, uint256 expectedDebt_, uint256 slippage_);

    function stakedPosition(address _bToken, address _user)
        external
        view
        returns (uint256 amount_, uint256 locked_, uint256 earned_, uint256 userAccumulator_);

    function creditAccount(address _bToken, address _user) external view returns (uint256 collateral_, uint256 debt_);
}
