// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {NftMarketplace} from "./NftMarketplace.sol";
import {BTokenFeeForwarder} from "./BTokenFeeForwarder.sol";

/**
 * @title ProjectFeeRouterUpgradeable
 * @notice UUPS upgradeable fee router that receives ERC20 creator-fee tokens
 *         and splits them per bToken configuration.
 * @dev    Each registered bToken gets a dedicated `BTokenFeeForwarder` deployed by
 *         this router. Pools are configured with that forwarder as `feeRecipient`,
 *         so creator fees for different bToken pools land at distinct addresses
 *         even when they share the same reserve token. The forwarder calls
 *         `receiveFees(bToken, amount)` to credit `accrued[bToken]`; `sweep`
 *         distributes from that per-bToken accumulator.
 *
 *      LST bTokens: total swap fee 4%, staking 1% (25%), creator stream 3% (75%)
 *        -> Router splits creator stream: 6667 bps treasury, 3333 bps royalties
 *      LOOP bToken: total swap fee 2%, staking 1% (50%), creator stream 1% (50%)
 *        -> Router splits creator stream: 10000 bps team
 */
contract ProjectFeeRouterUpgradeable is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct FeeConfig {
        uint16 bpsToAcquisitionTreasury;
        uint16 bpsToRoyalties;
        uint16 bpsToTeam;
        uint16 bpsToAfterburner;
        uint16 bpsToBLV;
    }

    struct Recipients {
        address acquisitionTreasury;
        address royaltyRecipient;
        address team;
        address afterburner;
        address blvModule;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Reserve token address per bToken
    mapping(address => address) public reserve;

    /// @notice Pending fees per bToken, credited via receiveFees() and zeroed on sweep()
    mapping(address => uint256) public accrued;

    /// @notice Fee split config per bToken
    mapping(address => FeeConfig) internal _cfg;

    /// @notice Recipient addresses per bToken
    mapping(address => Recipients) internal _recips;

    /// @notice Per-bToken fee forwarder (deployed by registerBToken). This is the
    ///         address that should be passed to BFactory as the pool's feeRecipient.
    mapping(address => address) public forwarderOf;

    /// @dev Storage gap for future upgrades
    uint256[50] private __gap;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Registered(address indexed bToken, address indexed reserveToken, address indexed forwarder);

    event ConfigSet(address indexed bToken, FeeConfig cfg, Recipients recips);

    event FeesReceived(address indexed bToken, uint256 amount);

    /// there is a custom function to call to send funds here to the treasury
    event Swept(
        address indexed bToken,
        uint256 amountIn,
        uint256 toTreasury,
        uint256 toRoyalties,
        uint256 toTeam,
        uint256 toAfterburner,
        uint256 toBLV,
        uint256 remainder
    );

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error BTokenNotRegistered();
    error BTokenAlreadyRegistered();
    error InvalidBpSum();
    error ZeroRecipientForNonZeroBps();
    error ZeroReserve();
    error NothingToSweep();
    error OnlyForwarder();

    /*//////////////////////////////////////////////////////////////
                             INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner_) external initializer {
        __Ownable_init(owner_);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
    }

    /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register a bToken and deploy its dedicated fee forwarder.
     * @dev    One-shot per bToken: re-registration is forbidden because the deployed
     *         forwarder address is baked into the pool's `feeRecipient` at pool
     *         creation; swapping it would orphan in-flight fees.
     * @param  bToken The bToken address
     * @param  reserveToken The ERC20 reserve token for this bToken's pool
     * @return forwarder The address of the deployed forwarder (use as pool.feeRecipient)
     */
    function registerBToken(address bToken, address reserveToken)
        external
        onlyOwner
        returns (address forwarder)
    {
        if (reserveToken == address(0)) revert ZeroReserve();
        if (forwarderOf[bToken] != address(0)) revert BTokenAlreadyRegistered();

        reserve[bToken] = reserveToken;
        forwarder = address(new BTokenFeeForwarder(bToken, IERC20(reserveToken), address(this)));
        forwarderOf[bToken] = forwarder;

        emit Registered(bToken, reserveToken, forwarder);
    }

    /**
     * @notice Set the fee config and recipients for a bToken.
     * @param bToken The bToken address (must be registered)
     * @param cfg Fee split in basis points (must sum to 10000)
     * @param recips Recipient addresses
     */
    function setConfig(address bToken, FeeConfig calldata cfg, Recipients calldata recips) external onlyOwner {
        if (reserve[bToken] == address(0)) revert BTokenNotRegistered();

        uint256 sum = uint256(cfg.bpsToAcquisitionTreasury) + uint256(cfg.bpsToRoyalties) + uint256(cfg.bpsToTeam)
            + uint256(cfg.bpsToAfterburner) + uint256(cfg.bpsToBLV);
        if (sum != 10_000) revert InvalidBpSum();

        if (cfg.bpsToAcquisitionTreasury > 0 && recips.acquisitionTreasury == address(0)) {
            revert ZeroRecipientForNonZeroBps();
        }
        if (cfg.bpsToRoyalties > 0 && recips.royaltyRecipient == address(0)) {
            revert ZeroRecipientForNonZeroBps();
        }
        if (cfg.bpsToTeam > 0 && recips.team == address(0)) {
            revert ZeroRecipientForNonZeroBps();
        }
        if (cfg.bpsToAfterburner > 0 && recips.afterburner == address(0)) {
            revert ZeroRecipientForNonZeroBps();
        }
        if (cfg.bpsToBLV > 0 && recips.blvModule == address(0)) {
            revert ZeroRecipientForNonZeroBps();
        }

        _cfg[bToken] = cfg;
        _recips[bToken] = recips;

        emit ConfigSet(bToken, cfg, recips);
    }

    /**
     * @notice Credit fees forwarded by a bToken's dedicated forwarder.
     * @dev    Only callable by `forwarderOf[bToken]`. The forwarder transfers tokens
     *         to this contract first, then calls this to record attribution. The
     *         fee router never reads its own `balanceOf` for accounting — credits
     *         are explicit per bToken.
     */
    function receiveFees(address bToken, uint256 amount) external {
        if (msg.sender != forwarderOf[bToken]) revert OnlyForwarder();
        accrued[bToken] += amount;
        emit FeesReceived(bToken, amount);
    }

    /**
     * @notice Distribute pending creator-fee tokens for a bToken.
     * @dev    Reads `accrued[bToken]` (set by receiveFees), zeroes it, then splits
     *         per FeeConfig. Permissionless.
     * @param bToken The bToken whose fees to sweep
     */
    function sweep(address bToken) external nonReentrant {
        address r = reserve[bToken];
        if (r == address(0)) revert BTokenNotRegistered();

        uint256 delta = accrued[bToken];
        if (delta == 0) revert NothingToSweep();
        accrued[bToken] = 0;

        IERC20 token = IERC20(r);

        FeeConfig memory cfg = _cfg[bToken];
        Recipients memory recips = _recips[bToken];

        uint256 toTreasury = (delta * cfg.bpsToAcquisitionTreasury) / 10_000;
        uint256 toRoyalties = (delta * cfg.bpsToRoyalties) / 10_000;
        uint256 toTeam = (delta * cfg.bpsToTeam) / 10_000;
        uint256 toAfterburner = (delta * cfg.bpsToAfterburner) / 10_000;
        uint256 toBLV = (delta * cfg.bpsToBLV) / 10_000;

        uint256 distributed = toTreasury + toRoyalties + toTeam + toAfterburner + toBLV;
        uint256 remainder = delta - distributed;

        // Transfer slices
        if (toTreasury > 0) {
            token.safeTransfer(recips.acquisitionTreasury, toTreasury);
            // TODO: note that `NftMarketplace` assumes the incoming token matches its fixed `offerToken`
            NftMarketplace(recips.acquisitionTreasury).informOfFeeDistribution({bToken: bToken, amountFees: toTreasury});
        }
        if (toRoyalties > 0) token.safeTransfer(recips.royaltyRecipient, toRoyalties);
        if (toTeam > 0) token.safeTransfer(recips.team, toTeam);
        if (toAfterburner > 0) token.safeTransfer(recips.afterburner, toAfterburner);
        if (toBLV > 0) token.safeTransfer(recips.blvModule, toBLV);

        // Deterministic remainder: send to acquisitionTreasury if set, else team
        if (remainder > 0) {
            address remainderRecipient =
                recips.acquisitionTreasury != address(0) ? recips.acquisitionTreasury : recips.team;
            token.safeTransfer(remainderRecipient, remainder);
        }

        emit Swept(bToken, delta, toTreasury, toRoyalties, toTeam, toAfterburner, toBLV, remainder);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getConfig(address bToken) external view returns (FeeConfig memory) {
        return _cfg[bToken];
    }

    function getRecipients(address bToken) external view returns (Recipients memory) {
        return _recips[bToken];
    }

    /*//////////////////////////////////////////////////////////////
                           UPGRADE AUTH
    //////////////////////////////////////////////////////////////*/

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
