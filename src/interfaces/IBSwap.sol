// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IBSwap {
    // Swap functions

    function buyTokensExactIn(address _bToken, uint256 _amountIn, uint256 _limitAmount)
        external
        returns (uint256 amountOut_, uint256 feesReceived_);

    function buyTokensExactOut(address _bToken, uint256 _amountOut, uint256 _limitAmount)
        external
        payable
        returns (uint256 amountIn_, uint256 feesReceived_);

    function sellTokensExactIn(address _bToken, uint256 _amountIn, uint256 _limitAmount)
        external
        returns (uint256 amountOut_, uint256 feesReceived_);

    function sellTokensExactOut(address _bToken, uint256 _amountOut, uint256 _limitAmount)
        external
        returns (uint256 amountIn_, uint256 feesReceived_);

    // Quote functions

    function quoteBuyExactIn(address _bToken, uint256 _reservesIn)
        external
        view
        returns (uint256 tokensOut_, uint256 feesReceived_, uint256 slippage_);

    function quoteBuyExactOut(address _bToken, uint256 _amountOut)
        external
        view
        returns (uint256 amountIn_, uint256 feesReceived_, uint256 slippage_);

    function quoteSellExactIn(address _bToken, uint256 _amountIn)
        external
        view
        returns (uint256 amountOut_, uint256 feesReceived_, uint256 slippage_);

    function quoteSellExactOut(address _bToken, uint256 _reservesOut)
        external
        view
        returns (uint256 tokensIn_, uint256 feesReceived_, uint256 slippage_);
}
