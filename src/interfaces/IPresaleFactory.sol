// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BFactory} from "./IBFactory.sol";

interface IPresaleFactory {
    function createBTokenAndPool(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        bytes32 salt,
        BFactory.CreateParams memory createParams,
        uint256 poolReserves
    ) external returns (address bToken);

    function bFactory() external view returns (BFactory);
}
