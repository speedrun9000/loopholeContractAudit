// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPresale} from "./interfaces/IPresale.sol";
import {IBCredit} from "./interfaces/IBCredit.sol";
import {BFactory} from "./interfaces/IBFactory.sol";
import {IPresaleFactory} from "./interfaces/IPresaleFactory.sol";

/**
 * @title PresaleImplementation
 * @notice Implementation contract for presale logic using beacon proxy pattern
 * @dev All presales share this implementation through the beacon.
 *      Supports two sale types:
 *      - Spot: Users claim bTokens pro-rata after finalization
 *      - Credit: Admin claims credit positions in batches after pool creation
 */
contract PresaleImplementation is IPresale, Initializable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Array of phase configurations
    PresalePhaseConfig[] public phases;

    /// @notice General presale configuration
    PresaleConfig public config;

    /// @notice Parameters for BFactory token and pool creation
    BFactoryParams public bFactoryParams;

    /// @notice Baseline's BFactory contract
    BFactory public bFactory;

    /// @notice ERC20 token used for presale deposits
    IERC20 public presaleToken;

    /// @notice User deposits per phase: user => phaseId => amount
    mapping(address => mapping(uint8 => uint256)) public userDeposits;

    /// @notice Total deposits per phase
    mapping(uint8 => uint256) public phaseDeposits;

    /// @notice User refund claims per phase: user => phaseId => claimed
    mapping(address => mapping(uint8 => bool)) public refundClaimed;

    /// @notice Total amount raised across all phases
    uint256 public totalRaised;

    /// @notice Address of the created token
    address public createdToken;

    /// @notice ID of the created pool
    bytes32 public createdPoolId;

    /// @notice Whether the presale is finalized
    bool public finalized;

    /// @notice Whether the presale is cancelled
    bool public cancelled;

    /// @notice Type of sale (Credit or Spot)
    SaleType public saleType;

    /// @notice Basis points of total supply reserved as circulating (min 500 = 5%)
    uint16 public circulatingSupplyBps;

    /// @notice Total bTokens available for spot sale claims
    uint256 public totalClaimableTokens;

    /// @notice Whether a user has claimed their spot bTokens
    mapping(address => bool) public spotClaimed;

    /// @notice Whether the pool has been created (intermediate state for credit sales)
    bool public poolCreated;

    /// @notice Timestamp at which finalizeSale created the pool (zero before finalization).
    /// @dev Used to gate the selfCreditClaim escape hatch behind a grace period.
    uint256 public poolCreatedAt;

    /// @notice Grace period after finalizeSale during which only the admin may drive credit claims.
    ///         After this window, depositors can permissionlessly self-rescue via selfCreditClaim.
    uint256 public constant RESCUE_GRACE_PERIOD = 24 hours;

    /// @notice Baseline relay address, stored during finalization for credit batch claims
    address public baseline;

    /// @notice PresaleFactory address, used to route pool creation through the factory
    address public presaleFactory;

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyAdmin() {
        if (msg.sender != config.admin) revert Unauthorized();
        _;
    }

    modifier whenNotFinalized() {
        if (finalized) revert PresaleAlreadyFinalized();
        _;
    }

    modifier whenNotCancelled() {
        if (cancelled) revert PresaleAlreadyCancelled();
        _;
    }

    modifier whenCancelled() {
        if (!cancelled) revert PresaleNotCancelled();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the presale contract
     * @param _phases Array of phase configurations
     * @param _config General presale configuration
     * @param _bFactoryParams Parameters for token and pool creation
     * @param _presaleFactory Address of the PresaleFactory (routes pool creation through factory)
     * @param _presaleToken Address of the ERC20 token used for presale deposits
     */
    function initialize(
        PresalePhaseConfig[] memory _phases,
        PresaleConfig memory _config,
        BFactoryParams memory _bFactoryParams,
        address _presaleFactory,
        address _presaleToken
    ) external initializer {
        __ReentrancyGuard_init();

        if (_phases.length == 0) revert InvalidPhaseConfiguration();
        if (_config.admin == address(0)) revert InvalidPresaleConfiguration();
        if (_config.hardCap == 0) revert InvalidPresaleConfiguration();
        if (_config.softCap > _config.hardCap) revert InvalidPresaleConfiguration();
        if (_presaleFactory == address(0)) revert InvalidPresaleConfiguration();
        if (_presaleToken == address(0)) revert InvalidPresaleConfiguration();
        if (_config.circulatingSupplyBps < 500) revert InvalidPresaleConfiguration();

        // Validate phases
        for (uint256 i = 0; i < _phases.length; i++) {
            if (_phases[i].endTime <= _phases[i].startTime) revert InvalidPhaseConfiguration();
            if (_phases[i].totalPhaseCap == 0) revert InvalidPhaseConfiguration();
            if (_phases[i].userAllocationCap == 0) revert InvalidPhaseConfiguration();
            if (_phases[i].userAllocationCap > _phases[i].totalPhaseCap) revert InvalidPhaseConfiguration();

            if (i > 0 && _phases[i].startTime < _phases[i - 1].endTime) {
                revert InvalidPhaseConfiguration();
            }

            phases.push(_phases[i]);
        }

        config = _config;
        bFactoryParams = _bFactoryParams;
        bFactory = BFactory(_presaleFactory); // deprecated slot, kept for storage layout compatibility
        presaleToken = IERC20(_presaleToken);
        saleType = _config.saleType;
        circulatingSupplyBps = _config.circulatingSupplyBps;
        presaleFactory = _presaleFactory;
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the phase merkle root (whitelist) after deployment, for the specified `phaseId` to `merkleRoot`
     * @param phaseId Phase ID to update
     * @param merkleRoot New merkle root
     */
    function setPhaseMerkleRoot(uint8 phaseId, bytes32 merkleRoot)
        external
        onlyAdmin
        whenNotFinalized
        whenNotCancelled
    {
        if (poolCreated) revert PoolAlreadyCreated();
        if (phaseId >= phases.length) revert InvalidPhaseId();

        bytes32 oldRoot = phases[phaseId].merkleRoot;
        phases[phaseId].merkleRoot = merkleRoot;

        emit PhaseMerkleRootUpdated(phaseId, oldRoot, merkleRoot);
    }

    /*//////////////////////////////////////////////////////////////
                          DEPOSIT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit funds into the presale
     * @param phaseId ID of the phase to deposit into
     * @param amount Amount of presale tokens to deposit
     * @param merkleProof Merkle proof for whitelist verification
     */
    function deposit(uint8 phaseId, uint256 amount, bytes32[] calldata merkleProof)
        external
        nonReentrant
        whenNotFinalized
        whenNotCancelled
    {
        if (poolCreated) revert PoolAlreadyCreated();
        if (amount == 0) revert InvalidAmount();
        if (phaseId >= phases.length) revert InvalidPhaseId();

        PresalePhaseConfig storage phase = phases[phaseId];

        if (block.timestamp < phase.startTime || block.timestamp > phase.endTime) {
            revert PhaseNotActive();
        }

        if (phase.merkleRoot != bytes32(0)) {
            bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
            if (!MerkleProof.verify(merkleProof, phase.merkleRoot, leaf)) {
                revert UserNotWhitelisted();
            }
        }

        // Check user allocation cap
        uint256 currentUserDeposit = userDeposits[msg.sender][phaseId];
        uint256 newUserDeposit = currentUserDeposit + amount;
        if (newUserDeposit > phase.userAllocationCap) revert UserAllocationExceeded();

        // Check phase cap
        uint256 currentPhaseDeposit = phaseDeposits[phaseId];
        uint256 newPhaseDeposit = currentPhaseDeposit + amount;
        if (newPhaseDeposit > phase.totalPhaseCap) revert PhaseCapExceeded();

        // Check hard cap
        uint256 newTotalRaised = totalRaised + amount;
        if (newTotalRaised > config.hardCap) revert HardCapExceeded();

        userDeposits[msg.sender][phaseId] = newUserDeposit;
        phaseDeposits[phaseId] = newPhaseDeposit;
        totalRaised = newTotalRaised;

        // Transfer tokens from user to this contract
        presaleToken.safeTransferFrom(msg.sender, address(this), amount);

        emit DepositReceived(msg.sender, amount, phaseId, newUserDeposit);

        // Check if this is the first deposit for the phase
        if (currentPhaseDeposit == 0) {
            emit PhaseStarted(phaseId, phase.startTime);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        FINALIZATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Finalize the presale: split funds, create token + pool, set fee routing
     * @dev For spot sales, this fully finalizes and holds bTokens for user claims.
     *      For credit sales, this creates the pool and enters an intermediate state
     *      where the admin must call claimCreditBatch() then completeFinalization().
     * @param params All finalization parameters (see FinalizeParams struct)
     */
    function finalizeSale(FinalizeParams memory params)
        external
        onlyAdmin
        whenNotFinalized
        whenNotCancelled
        nonReentrant
    {
        if (poolCreated) revert PoolAlreadyCreated();
        if (totalRaised < config.softCap) revert SoftCapNotReached();
        if (params.bpsToTreasury > 10_000) revert InvalidFundSplit();
        if (params.bpsToTreasury > 0 && params.acquisitionTreasury == address(0)) revert InvalidFundSplit();
        // feeRouter is set via CreateParams.feeRecipient at pool creation

        // Mark pool as created (intermediate state)
        poolCreated = true;
        poolCreatedAt = block.timestamp;

        // Store baseline address for credit batch claims
        baseline = params.baseline;

        // Calculate total supply using configurable circulating supply percentage
        uint256 totalSupply =
            ((bFactoryParams.initialPoolBTokens + params.initialCollateral) * (10_000 + circulatingSupplyBps)) / 10_000;
        uint256 initialCirculatingSupply = totalSupply - bFactoryParams.initialPoolBTokens - params.initialCollateral;

        // Get the reserve token balance (all presale tokens held by this contract)
        uint256 reserveBalance = presaleToken.balanceOf(address(this));

        // Split funds: send portion to acquisitions treasury
        uint256 treasuryAmount = 0;
        if (params.bpsToTreasury > 0) {
            treasuryAmount = (reserveBalance * params.bpsToTreasury) / 10_000;
            presaleToken.safeTransfer(params.acquisitionTreasury, treasuryAmount);
            emit TreasurySent(params.acquisitionTreasury, treasuryAmount);
        }

        // Remainder goes to pool
        uint256 poolReserves = reserveBalance - treasuryAmount;

        // Build pool creation params (bToken is set by the factory)
        BFactory.CreateParams memory createParams = BFactory.CreateParams({
            bToken: address(0),
            initialPoolBTokens: bFactoryParams.initialPoolBTokens,
            reserve: address(presaleToken),
            initialPoolReserves: poolReserves,
            initialActivePrice: params.initialActivePrice,
            initialBLV: bFactoryParams.initialBLV,
            feeRecipient: params.feeRouter,
            creator: bFactoryParams.creator,
            creatorFeePct: bFactoryParams.creatorFeePct,
            swapFeePct: bFactoryParams.swapFeePct,
            createHook: bFactoryParams.createHook,
            claimMerkleRoot: params.claimMerkleRoot,
            initialCollateral: params.initialCollateral,
            initialDebt: params.initialDebt
        });

        // Approve factory to pull reserve tokens, then create bToken + pool through factory
        // (factory is the only address that needs Baseline approval)
        presaleToken.safeIncreaseAllowance(presaleFactory, poolReserves);
        address bToken = IPresaleFactory(presaleFactory).createBTokenAndPool(
            params.name, params.symbol, totalSupply, params.salt, createParams, poolReserves
        );

        // Store created token
        createdToken = bToken;
        bFactoryParams.bToken = bToken;

        emit BTokenCreated(bToken, params.name, params.symbol, totalSupply);

        // Store pool ID
        createdPoolId = keccak256(abi.encode(bToken, address(presaleToken)));

        emit PoolCreated(bToken, createdPoolId);

        // Branch based on sale type
        if (saleType == SaleType.Spot) {
            _finalizeSpot(initialCirculatingSupply);
        } else {
            _finalizeCredit(bToken, initialCirculatingSupply, params.circulatingSupplyRecipient);
        }
    }

    /**
     * @notice Spot sale finalization helper: hold bTokens for user claims and mark finalized
     * @param initialCirculatingSupply Amount of bTokens available for claims
     */
    function _finalizeSpot(uint256 initialCirculatingSupply) internal {
        totalClaimableTokens = initialCirculatingSupply;
        finalized = true;

        emit PresaleFinalized(createdToken, createdPoolId, totalRaised);
    }

    /**
     * @notice Credit sale finalization helper: send circulating supply to recipient,
     *         enter intermediate state for paginated credit claims
     * @param bToken Address of the created bToken
     * @param initialCirculatingSupply Amount of bTokens not in pool or collateral
     * @param circulatingSupplyRecipient Address to receive circulating supply (can be zero)
     */
    function _finalizeCredit(address bToken, uint256 initialCirculatingSupply, address circulatingSupplyRecipient)
        internal
    {
        if (circulatingSupplyRecipient != address(0) && initialCirculatingSupply > 0) {
            IERC20(bToken).safeTransfer(circulatingSupplyRecipient, initialCirculatingSupply);
        }

        emit PoolCreatedAndPendingClaims(bToken, createdPoolId);
    }

    /**
     * @notice Claim credit positions for a batch of users (credit sales only)
     * @dev Can be called multiple times with different batches. Must be called after
     *      finalizeSale() and before completeFinalization().
     * @param claimUsers Array of user addresses to claim for
     * @param claimCollaterals Array of collateral amounts per user
     * @param claimDebts Array of debt amounts per user
     * @param claimProofs Array of merkle proofs per user
     */
    function claimCreditBatch(
        address[] calldata claimUsers,
        uint128[] calldata claimCollaterals,
        uint128[] calldata claimDebts,
        bytes32[][] calldata claimProofs
    ) external onlyAdmin nonReentrant {
        if (!poolCreated) revert NotPoolCreated();
        if (finalized) revert PresaleAlreadyFinalized();
        if (saleType != SaleType.Credit) revert InvalidSaleType();

        IBCredit(baseline).claimCredit(createdToken, claimUsers, claimCollaterals, claimDebts, claimProofs);

        emit CreditBatchClaimed(claimUsers.length);
    }

    /**
     * @notice Permissionless self-rescue for credit-sale depositors
     * @dev Escape hatch in case the admin abandons the presale in the intermediate state
     *      (poolCreated && !finalized) and never includes the caller in a claimCreditBatch.
     *      Callable only after the RESCUE_GRACE_PERIOD elapses since finalizeSale, giving
     *      the admin a window to drive batched claims before depositors self-rescue.
     *      Caller must supply their own (collateral, debt, proof) tuple matching the
     *      claimMerkleRoot set at pool creation. Authorization is enforced by Baseline's
     *      proof check; the leaf is bound to msg.sender.
     * @param collateral Caller's collateral amount as encoded in the merkle leaf
     * @param debt Caller's debt amount as encoded in the merkle leaf
     * @param proof Merkle proof for the caller's leaf
     */
    function selfCreditClaim(uint128 collateral, uint128 debt, bytes32[] calldata proof) external nonReentrant {
        if (!poolCreated) revert NotPoolCreated();
        if (finalized) revert PresaleAlreadyFinalized();
        if (saleType != SaleType.Credit) revert InvalidSaleType();
        if (block.timestamp < poolCreatedAt + RESCUE_GRACE_PERIOD) revert SelfCreditClaimGracePeriodActive();

        address[] memory users = new address[](1);
        users[0] = msg.sender;
        uint128[] memory collaterals = new uint128[](1);
        collaterals[0] = collateral;
        uint128[] memory debts = new uint128[](1);
        debts[0] = debt;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = proof;

        IBCredit(baseline).claimCredit(createdToken, users, collaterals, debts, proofs);

        emit CreditBatchClaimed(1);
    }

    /**
     * @notice Complete finalization after all credit batches have been claimed (credit sales only)
     * @dev Must be called after all claimCreditBatch() calls are done
     */
    function completeFinalization() external onlyAdmin {
        if (!poolCreated) revert NotPoolCreated();
        if (finalized) revert PresaleAlreadyFinalized();
        if (saleType != SaleType.Credit) revert InvalidSaleType();

        finalized = true;

        emit FinalizationCompleted();
        emit PresaleFinalized(createdToken, createdPoolId, totalRaised);
    }

    /**
     * @notice Cancel the presale and enable refunds
     * @dev Admin can cancel anytime. Anyone can cancel if soft cap not met AND all phases have ended.
     */
    function cancelSale() external whenNotFinalized whenNotCancelled {
        if (poolCreated) revert PoolAlreadyCreated();
        if (msg.sender != config.admin) {
            if (totalRaised >= config.softCap) revert Unauthorized();
            if (!allPhasesEnded()) revert Unauthorized();
        }

        cancelled = true;
        emit PresaleCancelled(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                          CLAIM FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claim bTokens pro-rata based on deposits (spot sales only)
     * @dev Claims across all phases in a single transaction.
     *      claimAmount = (totalUserDeposit / totalRaised) * totalClaimableTokens
     */
    function claimSpot() external nonReentrant {
        if (!finalized) revert PresaleNotFinalized();
        if (saleType != SaleType.Spot) revert InvalidSaleType();
        if (spotClaimed[msg.sender]) revert AlreadyClaimed();

        // Sum deposits across all phases
        uint256 totalUserDeposit = 0;
        for (uint8 i = 0; i < phases.length; i++) {
            totalUserDeposit += userDeposits[msg.sender][i];
        }
        if (totalUserDeposit == 0) revert NothingToClaim();

        spotClaimed[msg.sender] = true;

        uint256 claimAmount = (totalUserDeposit * totalClaimableTokens) / totalRaised;

        IERC20(createdToken).safeTransfer(msg.sender, claimAmount);

        emit SpotClaimed(msg.sender, claimAmount);
    }

    /*//////////////////////////////////////////////////////////////
                          REFUND FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claim refund after presale cancellation
     * @param phaseId Phase ID to claim refund from
     */
    function refund(uint8 phaseId) external nonReentrant whenCancelled {
        if (phaseId >= phases.length) revert InvalidPhaseId();
        if (refundClaimed[msg.sender][phaseId]) revert NoRefundAvailable();

        uint256 depositAmount = userDeposits[msg.sender][phaseId];
        if (depositAmount == 0) revert NoRefundAvailable();

        // Mark as claimed
        refundClaimed[msg.sender][phaseId] = true;

        // Transfer refund
        presaleToken.safeTransfer(msg.sender, depositAmount);

        emit RefundIssued(msg.sender, depositAmount, phaseId);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the total amount deposited by a user in a specific phase
     * @param user Address of the user
     * @param phaseId Phase ID
     * @return Total amount deposited by the user in the phase
     */
    function getUserDepositedAmount(address user, uint8 phaseId) external view returns (uint256) {
        return userDeposits[user][phaseId];
    }

    /**
     * @notice Get the remaining allocation for a user in a specific phase
     * @param user Address of the user
     * @param phaseId Phase ID
     * @return Remaining allocation for the user
     */
    function getUserRemainingAllocation(address user, uint8 phaseId) external view returns (uint256) {
        if (phaseId >= phases.length) return 0;
        uint256 deposited = userDeposits[user][phaseId];
        uint256 cap = phases[phaseId].userAllocationCap;
        return cap > deposited ? cap - deposited : 0;
    }

    /**
     * @notice Get information about a specific phase
     * @param phaseId Phase ID
     * @return Phase configuration
     */
    function getPhaseInfo(uint8 phaseId) external view returns (PresalePhaseConfig memory) {
        if (phaseId >= phases.length) revert InvalidPhaseId();
        return phases[phaseId];
    }

    /**
     * @notice Get the currently active phase
     * @return Phase ID of the active phase (reverts if no active phase)
     */
    function getCurrentPhase() external view returns (uint8) {
        for (uint8 i = 0; i < phases.length; i++) {
            if (block.timestamp >= phases[i].startTime && block.timestamp <= phases[i].endTime) {
                return i;
            }
        }
        revert PhaseNotActive();
    }

    /**
     * @notice Get the stored BFactory parameters
     * @return BFactory parameters
     */
    function getBFactoryParams() external view returns (BFactoryParams memory) {
        return bFactoryParams;
    }

    /**
     * @notice Get the address of the created token
     * @return Address of the created token (zero if not created)
     */
    function getCreatedToken() external view returns (address) {
        return createdToken;
    }

    /**
     * @notice Get the ID of the created pool
     * @return Pool ID (zero if not created)
     */
    function getCreatedPool() external view returns (bytes32) {
        return createdPoolId;
    }

    /**
     * @notice Get the total amount raised across all phases
     * @return Total amount raised
     */
    function getTotalRaised() external view returns (uint256) {
        return totalRaised;
    }

    /**
     * @notice Check if the presale is finalized
     * @return True if finalized
     */
    function isFinalized() external view returns (bool) {
        return finalized;
    }

    /**
     * @notice Check if the presale is cancelled
     * @return True if cancelled
     */
    function isCancelled() external view returns (bool) {
        return cancelled;
    }

    /**
     * @notice Get the total number of phases
     * @return Number of phases
     */
    function getPhaseCount() external view returns (uint256) {
        return phases.length;
    }

    /**
     * @notice Check if all phases have ended
     * @return True if all phases have ended
     */
    function allPhasesEnded() public view returns (bool) {
        return block.timestamp > phases[phases.length - 1].endTime;
    }

    /**
     * @notice Get the sale type (Credit or Spot)
     * @return The sale type enum value
     */
    function getSaleType() external view returns (SaleType) {
        return saleType;
    }

    /**
     * @notice Get total bTokens available for spot sale claims
     * @return Total claimable tokens (only meaningful for spot sales)
     */
    function getTotalClaimableTokens() external view returns (uint256) {
        return totalClaimableTokens;
    }

    /**
     * @notice Get the claimable bToken amount for a user (spot sales only)
     * @param user Address of the user
     * @return Claimable bToken amount, or 0 if not eligible
     */
    function getClaimableAmount(address user) external view returns (uint256) {
        if (!finalized || saleType != SaleType.Spot) return 0;
        if (spotClaimed[user]) return 0;
        if (totalRaised == 0) return 0;

        uint256 totalUserDeposit = 0;
        for (uint8 i = 0; i < phases.length; i++) {
            totalUserDeposit += userDeposits[user][i];
        }
        if (totalUserDeposit == 0) return 0;

        return (totalUserDeposit * totalClaimableTokens) / totalRaised;
    }
}
