// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IBStaking {
    function deposit(address _bToken, address _user, uint256 _amount) external;

    function withdraw(address _bToken, uint256 _amount) external;

    function withdrawMax(address _bToken) external;

    function withdrawAndClaim(address _bToken, uint256 _amount) external;

    function claim(address _bToken, address _user, bool _asNative) external returns (uint256 amount_);

    function getEarned(address _bToken, address _user) external view returns (uint256);

    function getAccumulator(address _bToken)
        external
        view
        returns (uint256 accumulator_, uint256 newYield_, uint256 tokensPerSecond_);

    function getCurrentRate(address _bToken) external view returns (uint256);
}
