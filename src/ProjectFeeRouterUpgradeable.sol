// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {NftMarketplace} from "./NftMarketplace.sol";

/**
 * @title ProjectFeeRouterUpgradeable
 * @notice UUPS upgradeable fee router that receives ERC20 creator-fee tokens
 *         and splits them per bToken configuration.
 * @dev Set as pool.feeRecipient for each bToken. Pull-based: anyone can call sweep().
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

    /// @notice Tracked balance per bToken (for delta-based sweep)
    mapping(address => uint256) public lastBalance;

    /// @notice Fee split config per bToken
    mapping(address => FeeConfig) internal _feeConfig;

    /// @notice Recipient addresses per bToken
    mapping(address => Recipients) internal _recipients;

    /// @dev Storage gap for future upgrades
    uint256[50] private __gap;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Registered(address indexed bToken, address indexed reserveToken);

    event ConfigSet(address indexed bToken, FeeConfig feeConfig, Recipients recipients);

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
    error InvalidBpSum();
    error ZeroRecipientForNonZeroBps();
    error ZeroReserve();
    error NothingToSweep();

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
     * @notice Register a bToken with its reserve token address.
     * @param bToken The bToken address
     * @param reserveToken The ERC20 reserve token for this bToken's pool
     */
    function registerBToken(address bToken, address reserveToken) external onlyOwner {
        if (reserveToken == address(0)) revert ZeroReserve();
        reserve[bToken] = reserveToken;
        lastBalance[bToken] = IERC20(reserveToken).balanceOf(address(this));
        emit Registered(bToken, reserveToken);
    }

    /**
     * @notice Set the fee config and recipients for a bToken.
     * @param bToken The bToken address (must be registered)
     * @param feeConfig Fee split in basis points (must sum to 10000)
     * @param recipients Recipient addresses
     */
    function setConfig(address bToken, FeeConfig calldata feeConfig, Recipients calldata recipients)
        external
        onlyOwner
    {
        if (reserve[bToken] == address(0)) revert BTokenNotRegistered();

        uint256 sum = uint256(feeConfig.bpsToAcquisitionTreasury) + uint256(feeConfig.bpsToRoyalties)
            + uint256(feeConfig.bpsToTeam) + uint256(feeConfig.bpsToAfterburner) + uint256(feeConfig.bpsToBLV);
        if (sum != 10_000) revert InvalidBpSum();

        if (feeConfig.bpsToAcquisitionTreasury > 0 && recipients.acquisitionTreasury == address(0)) {
            revert ZeroRecipientForNonZeroBps();
        }
        if (feeConfig.bpsToRoyalties > 0 && recipients.royaltyRecipient == address(0)) {
            revert ZeroRecipientForNonZeroBps();
        }
        if (feeConfig.bpsToTeam > 0 && recipients.team == address(0)) {
            revert ZeroRecipientForNonZeroBps();
        }
        if (feeConfig.bpsToAfterburner > 0 && recipients.afterburner == address(0)) {
            revert ZeroRecipientForNonZeroBps();
        }
        if (feeConfig.bpsToBLV > 0 && recipients.blvModule == address(0)) {
            revert ZeroRecipientForNonZeroBps();
        }

        _feeConfig[bToken] = feeConfig;
        _recipients[bToken] = recipients;

        emit ConfigSet(bToken, feeConfig, recipients);
    }

    /**
     * @notice Distribute any new creator-fee tokens that arrived for a bToken.
     * @dev Pull-based: reads current balance, computes delta from lastBalance,
     *      updates lastBalance, then distributes slices.
     * @param bToken The bToken whose fees to sweep
     */
    function sweep(address bToken) external nonReentrant {
        address reserveToken = reserve[bToken];
        if (reserveToken == address(0)) revert BTokenNotRegistered();

        IERC20 token = IERC20(reserveToken);
        uint256 bal = token.balanceOf(address(this));
        uint256 delta = bal - lastBalance[bToken];
        if (delta == 0) revert NothingToSweep();

        FeeConfig memory feeConfig = _feeConfig[bToken];
        Recipients memory recipients = _recipients[bToken];

        uint256 toTreasury = (delta * feeConfig.bpsToAcquisitionTreasury) / 10_000;
        uint256 toRoyalties = (delta * feeConfig.bpsToRoyalties) / 10_000;
        uint256 toTeam = (delta * feeConfig.bpsToTeam) / 10_000;
        uint256 toAfterburner = (delta * feeConfig.bpsToAfterburner) / 10_000;
        uint256 toBLV = (delta * feeConfig.bpsToBLV) / 10_000;

        uint256 distributed = toTreasury + toRoyalties + toTeam + toAfterburner + toBLV;
        uint256 remainder = delta - distributed;

        // Transfer slices
        if (toTreasury > 0) {
            token.safeTransfer(recipients.acquisitionTreasury, toTreasury);
            // TODO: note that `NftMarketplace` assumes the incoming token matches its fixed `offerToken`
            NftMarketplace(recipients.acquisitionTreasury).informOfFeeDistribution({
                bToken: bToken,
                amountFees: toTreasury
            });
        }
        if (toRoyalties > 0) token.safeTransfer(recipients.royaltyRecipient, toRoyalties);
        if (toTeam > 0) token.safeTransfer(recipients.team, toTeam);
        if (toAfterburner > 0) token.safeTransfer(recipients.afterburner, toAfterburner);
        if (toBLV > 0) token.safeTransfer(recipients.blvModule, toBLV);

        // Deterministic remainder: send to acquisitionTreasury if set, else team
        if (remainder > 0) {
            address remainderRecipient =
                recipients.acquisitionTreasury != address(0) ? recipients.acquisitionTreasury : recipients.team;
            token.safeTransfer(remainderRecipient, remainder);
        }

        // Adjust lastBalance to account for all outflows
        lastBalance[bToken] = token.balanceOf(address(this));

        emit Swept(bToken, delta, toTreasury, toRoyalties, toTeam, toAfterburner, toBLV, remainder);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getConfig(address bToken) external view returns (FeeConfig memory) {
        return _feeConfig[bToken];
    }

    function getRecipients(address bToken) external view returns (Recipients memory) {
        return _recipients[bToken];
    }

    /*//////////////////////////////////////////////////////////////
                           UPGRADE AUTH
    //////////////////////////////////////////////////////////////*/

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
