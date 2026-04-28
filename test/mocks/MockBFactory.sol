// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BFactory} from "../../src/interfaces/IBFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./MockERC20.sol";

/**
 * @title MockBFactory
 * @notice Mock implementation of BFactory for testing. Mirrors real BFactory's
 *         deployer-salted CREATE2 so precomputeBTokenAddress is meaningful.
 */
contract MockBFactory is BFactory {
    uint256 public tokenCounter;
    mapping(address => bool) public isToken;

    function createBToken(string memory _name, string memory _symbol, uint256 _totalSupply, bytes32 _salt)
        external
        override
        returns (address bToken_)
    {
        bytes32 finalSalt = keccak256(abi.encode(msg.sender, _salt));
        bToken_ = address(new MockERC20{salt: finalSalt}(_name, _symbol, 18));
        isToken[bToken_] = true;

        // Mint totalSupply to the caller so the presale contract holds bTokens
        MockERC20(bToken_).mint(msg.sender, _totalSupply);

        emit BTokenCreated(bToken_, _name, _symbol, 18, _totalSupply, msg.sender);
    }

    function createPool(CreateParams memory _params) external override {
        bytes32 poolId = keccak256(abi.encode(_params.bToken, address(_params.reserve)));

        // Create a deterministic mock pool address
        address mockPool = address(uint160(uint256(poolId)));

        // Transfer reserve tokens from caller to mock pool
        if (_params.initialPoolReserves > 0 && _params.reserve != address(0)) {
            IERC20(_params.reserve).transferFrom(msg.sender, mockPool, _params.initialPoolReserves);
        }

        emit PoolCreated(
            _params.bToken,
            _params.reserve,
            _params.creator,
            _params.feeRecipient,
            _params.creatorFeePct,
            _params.initialActivePrice,
            _params.initialBLV,
            _params.initialPoolReserves,
            _params.initialPoolBTokens,
            _params.initialCollateral,
            _params.initialDebt,
            poolId
        );
    }

    function precomputeBTokenAddress(
        string memory _name,
        string memory _symbol,
        uint256, /* _totalSupply */
        bytes32 _salt,
        address _deployer
    ) external view override returns (address computedAddress_) {
        bytes32 finalSalt = keccak256(abi.encode(_deployer, _salt));
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(type(MockERC20).creationCode, abi.encode(_name, _symbol, uint8(18)))
        );
        computedAddress_ = address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), address(this), finalSalt, initCodeHash))
                )
            )
        );
    }
}
