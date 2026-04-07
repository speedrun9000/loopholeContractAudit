// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface BFactory {
    type Currency is address;

    struct CreateParams {
        address bToken;
        uint256 initialPoolBTokens;
        address reserve;
        uint256 initialPoolReserves;
        uint256 initialActivePrice;
        uint256 initialBLV;
        address creator;
        address feeRecipient;
        uint256 creatorFeePct;
        uint256 swapFeePct;
        bool createHook;
        bytes32 claimMerkleRoot;
        uint256 initialCollateral;
        uint256 initialDebt;
    }

    struct PoolKey {
        Currency currency0;
        Currency currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    error InsufficientPoolBTokens();
    error InvalidBTokenDecimals();
    error InvalidCreatorFee();
    error InvalidCreator();
    error InvalidFeeRecipient();
    error InvalidName();
    error InvalidReserveDecimals();
    error InvalidSymbol();
    error NotApprovedReserve();
    error NotDeployer();
    error PoolAlreadyInitialized();
    error TotalSupplyTooLow();
    error TotalSupplyTooHigh();
    error UnauthorizedCreditPositionCreation();
    error InvalidInitialCollateralOrDebt();
    error InvalidInitialDebt();
    error InsolventInitialCreditPosition();
    error InvalidPoolSupply();
    error InvalidSalt();

    event BTokenCreated(
        address bTokenAddress, string name, string symbol, uint8 decimals, uint256 totalSupply, address creator
    );
    event PoolCreated(
        address bTokenAddress,
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

    function createBToken(string memory _name, string memory _symbol, uint256 _totalSupply, bytes32 _salt)
        external
        returns (address bToken_);

    function createPool(CreateParams memory _params) external;

    function precomputeBTokenAddress(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        bytes32 _salt,
        address _deployer
    ) external view returns (address computedAddress_);
}
