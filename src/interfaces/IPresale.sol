// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/**
 * @title IPresale
 * @notice Interface for the Presale system
 * @dev Defines all structs, events, errors, and functions for the presale implementation
 */
interface IPresale {
    /*//////////////////////////////////////////////////////////////
                                 ENUMS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sale type: Credit (0) for credit positions, Spot (1) for bToken claims
    /// @dev Credit = 0 so existing proxies default to credit behavior on upgrade
    enum SaleType {
        Credit,
        Spot
    }

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Configuration for a presale phase
     * @param startTime Timestamp when the phase starts
     * @param endTime Timestamp when the phase ends
     * @param totalPhaseCap Maximum total deposits allowed in this phase
     * @param userAllocationCap Maximum amount a single user can deposit in this phase (uniform for all users)
     * @param merkleRoot Merkle root for whitelisted addresses in this phase
     */
    struct PresalePhaseConfig {
        uint256 startTime;
        uint256 endTime;
        uint256 totalPhaseCap;
        uint256 userAllocationCap;
        bytes32 merkleRoot;
    }

    /**
     * @notice Parameters for BFactory token and pool creation
     * @dev Stored at initialization and used during finalization
     * @dev reserve, initialPoolReserves, initialActivePrice and initialBlvPrice are set at finalization
     */
    struct BFactoryParams {
        address bToken; // Zero initially, set at finalization
        uint256 initialPoolBTokens;
        address creator;
        uint256 creatorFeePct;
        bool createHook;
        bytes32 claimMerkleRoot;
        uint256 initialCollateral;
        uint256 initialDebt;
        uint256 initialBLV;
        uint256 swapFeePct;
    }

    /**
     * @notice General presale configuration
     * @param admin Address with administrative privileges
     * @param softCap Minimum amount to raise for presale to succeed
     * @param hardCap Maximum amount to raise across all phases
     * @param saleType Whether this is a Spot or Credit sale
     * @param circulatingSupplyBps Basis points of total supply reserved as circulating (min 500 = 5%)
     */
    struct PresaleConfig {
        address admin;
        uint256 softCap;
        uint256 hardCap;
        SaleType saleType;
        uint16 circulatingSupplyBps;
    }

    /**
     * @notice Finalization parameters for fund splitting and fee routing
     * @param name Token name
     * @param symbol Token symbol
     * @param initialActivePrice Initial active price for the pool
     * @param initialBlvPrice Initial BLV price
     * @param claimMerkleRoot Merkle root for BCredit.claimCredit
     * @param initialCollateral Total collateral allocated to presalers
     * @param initialDebt Total debt allocated to presalers
     * @param acquisitionTreasury Address to receive portion of raised funds
     * @param bpsToTreasury Basis points of raised funds to treasury (remainder to pool)
     * @param feeRouter ProjectFeeRouterUpgradeable proxy (set as pool feeRecipient)
     * @param baseline Baseline relay address (for calling setFeeRecipient and claimCredit)
     * @param salt Salt for the bToken creation
     * @param circulatingSupplyRecipient Address to receive circulating supply on credit sales (ignored for spot)
     */
    struct FinalizeParams {
        string name;
        string symbol;
        uint256 initialActivePrice;
        uint256 initialBlvPrice;
        bytes32 claimMerkleRoot;
        uint256 initialCollateral;
        uint256 initialDebt;
        address acquisitionTreasury;
        uint16 bpsToTreasury;
        address feeRouter;
        address baseline;
        bytes32 salt;
        address circulatingSupplyRecipient;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event DepositReceived(address indexed user, uint256 amount, uint8 indexed phaseId, uint256 cumulativeDeposit);
    event BTokenCreated(address indexed bToken, string name, string symbol, uint256 totalSupply);
    event PoolCreated(address indexed bToken, bytes32 indexed poolId);
    event PresaleFinalized(address indexed bToken, bytes32 indexed poolId, uint256 totalRaised);
    event PresaleCancelled(address indexed presale);
    event RefundIssued(address indexed user, uint256 amount, uint8 indexed phaseId);
    event PhaseStarted(uint8 indexed phaseId, uint256 startTime);
    event PhaseEnded(uint8 indexed phaseId, uint256 endTime);
    event TreasurySent(address indexed treasury, uint256 amount);
    event FeeRecipientSet(address indexed bToken, address indexed feeRouter);
    event PhaseMerkleRootUpdated(uint8 indexed phaseId, bytes32 oldRoot, bytes32 newRoot);
    event SpotClaimed(address indexed user, uint256 bTokenAmount);
    event CreditBatchClaimed(uint256 batchSize);
    event FinalizationCompleted();
    event PoolCreatedAndPendingClaims(address indexed bToken, bytes32 indexed poolId);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidPhaseConfiguration();
    error InvalidPhaseId();
    error PhaseNotActive();
    error UserNotWhitelisted();
    error UserAllocationExceeded();
    error PhaseCapExceeded();
    error HardCapExceeded();
    error InvalidAmount();
    error PresaleNotFinalized();
    error PresaleAlreadyFinalized();
    error PresaleNotCancelled();
    error PresaleAlreadyCancelled();
    error SoftCapNotReached();
    error Unauthorized();
    error NoRefundAvailable();
    error TransferFailed();
    error InvalidPresaleConfiguration();
    error InvalidFundSplit();
    error InvalidFeeRouting();
    error FeeRecipientSetFailed();
    error AlreadyClaimed();
    error NothingToClaim();
    error InvalidSaleType();
    error NotPoolCreated();
    error PoolAlreadyCreated();

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function initialize(
        PresalePhaseConfig[] memory phases,
        PresaleConfig memory config,
        BFactoryParams memory bFactoryParams,
        address presaleFactory,
        address presaleToken
    ) external;

    function deposit(uint8 phaseId, uint256 amount, bytes32[] calldata merkleProof) external;

    function setPhaseMerkleRoot(uint8 phaseId, bytes32 merkleRoot) external;

    function finalizeSale(FinalizeParams memory params) external;

    function claimCreditBatch(
        address[] calldata claimUsers,
        uint128[] calldata claimCollaterals,
        uint128[] calldata claimDebts,
        bytes32[][] calldata claimProofs
    ) external;

    function completeFinalization() external;

    function claimSpot() external;

    function cancelSale() external;

    function refund(uint8 phaseId) external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getUserDepositedAmount(address user, uint8 phaseId) external view returns (uint256);

    function getUserRemainingAllocation(address user, uint8 phaseId) external view returns (uint256);

    function getPhaseInfo(uint8 phaseId) external view returns (PresalePhaseConfig memory);

    function getCurrentPhase() external view returns (uint8);

    function getBFactoryParams() external view returns (BFactoryParams memory);

    function getCreatedToken() external view returns (address);

    function getCreatedPool() external view returns (bytes32);

    function getTotalRaised() external view returns (uint256);

    function isFinalized() external view returns (bool);

    function isCancelled() external view returns (bool);

    function getSaleType() external view returns (SaleType);

    function getTotalClaimableTokens() external view returns (uint256);

    function getClaimableAmount(address user) external view returns (uint256);
}
