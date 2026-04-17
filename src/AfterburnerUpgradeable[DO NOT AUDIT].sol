// SPDX-License-Identifier: UNLICENSED
//
// ██████████████████████████████████████████████████████████████████████████████
// █                                                                          █
// █                     DO NOT AUDIT THIS CONTRACT                           █
// █                                                                          █
// █  This contract is out of scope for the audit. It is included here only   █
// █  for compilation and integration testing purposes.                       █
// █                                                                          █
// ██████████████████████████████████████████████████████████████████████████████
//
pragma solidity ^0.8.0;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBCredit} from "./interfaces/IBCredit.sol";
import {IBStaking} from "./interfaces/IBStaking.sol";
import {IBSwap} from "./interfaces/IBSwap.sol";

/**
 * @title AfterburnerUpgradeable
 * @notice Fee-funded leveraged buyback module. Accumulates reserve tokens from
 *         ProjectFeeRouter, then calls BCredit.leverage() on baseline
 *         to do a leveraged bToken purchase (borrow at BLV -> buy bTokens -> lock
 *         as collateral). Locked collateral is effectively removed from circulation.
 * @dev    Keeper bot handles timing/randomization off-chain. Contract just exposes
 *         execute() with parameters computed off-chain.
 * TODO Should this buy on fee sweep or on execute?
 */
contract AfterburnerUpgradeable is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The bToken to buy
    address public bToken;

    /// @notice The reserve token used to buy bTokens
    address public reserveToken;

    /// @notice Baseline relay address (Components are called through this)
    address public baseline;

    /// TODO Seperate to feerouter and marketplace
    /// @notice Addresses authorized to call fund()
    mapping(address => bool) public authorizedFunders;

    /// @dev Storage gap for future upgrades
    uint256[50] private __gap;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Funded(address indexed funder, uint256 amount);
    event Executed(uint256 targetCollateral, uint256 stakedBTokensUsed, uint256 debtAdded);
    event BaselineUpdated(address baseline);
    event FunderUpdated(address indexed funder, bool authorized);
    event SwappedAndStaked(uint256 reservesIn, uint256 bTokensOut);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotAuthorized();
    error BaselineNotSet();
    error ZeroAmount();

    /*//////////////////////////////////////////////////////////////
                             INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner_, address bToken_, address reserveToken_, address baseline_)
        external
        initializer
    {
        __Ownable_init(owner_);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        bToken = bToken_;
        reserveToken = reserveToken_;
        baseline = baseline_;
    }

    /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setBaseline(address baseline_) external onlyOwner {
        baseline = baseline_;
        emit BaselineUpdated(baseline_);
    }

    function setAuthorizedFunder(address funder, bool authorized) external onlyOwner {
        authorizedFunders[funder] = authorized;
        emit FunderUpdated(funder, authorized);
    }

    /*//////////////////////////////////////////////////////////////
                              FUNDING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit reserve tokens into the afterburner.
     */
    function fund(uint256 amount) external nonReentrant {
        if (!authorizedFunders[msg.sender] && msg.sender != owner()) revert NotAuthorized();
        if (amount == 0) revert ZeroAmount();

        IERC20(reserveToken).safeTransferFrom(msg.sender, address(this), amount);
        emit Funded(msg.sender, amount);
    }

    /**
     * @notice Swap reserve tokens for bTokens and stake them.
     *     /// yo afkbyte this function is needed because bCredit.leverage no longer supports reserves in. only bTokens staked are used.
     *     /// so we need to swap the funded reserves for bTokens and stake them so that they can be used in the leverage function.
     *     /// you could also consider just adding this piece into the execute function. but youd need to get 2 different swap quotes and its a little harder.
     *     /// you could also consider just throwing it into the fund function. but then the person funding would need to also provide a swap quote which might be annoying.
     */
    function swapAndStake(uint256 reservesIn, uint256 bTokensOutMin) external nonReentrant onlyOwner {
        if (baseline == address(0)) revert BaselineNotSet();
        if (reservesIn == 0) revert ZeroAmount();

        IERC20(reserveToken).forceApprove(baseline, reservesIn);
        (uint256 bTokensOut,) = IBSwap(baseline).buyTokensExactIn(bToken, reservesIn, bTokensOutMin);
        IERC20(bToken).approve(baseline, bTokensOut);
        IBStaking(baseline).deposit(bToken, address(this), bTokensOut);

        emit SwappedAndStaked(reservesIn, bTokensOut);
    }

    /*//////////////////////////////////////////////////////////////
                        EXECUTE LEVERAGED BUYBACK
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Leveraged buyback via BCredit.leverage() on baseline.
     *         Borrows reserves at BLV against targetCollateral, buys bTokens,
     *         locks them as collateral (removed from circulation).
     * @param targetCollateral Total bToken collateral to end up with
     * @param collateralIn   the amount of staked bTokens to use as collateral.
     * @param limit    the limit for the internal leverage swap. get it by calling IBLens.quoteLeverage()
     */
    function execute(uint256 targetCollateral, uint256 collateralIn, uint256 limit) external nonReentrant onlyOwner {
        if (baseline == address(0)) revert BaselineNotSet();
        if (targetCollateral == 0) revert ZeroAmount();

        /// @afkbyte this is because now that the bTokens are staked, we can claim fees and then leverage them later.
        /// depending on the implementation you could make this its own function if you wanted to.
        uint256 earned = IBStaking(baseline).claim(bToken, address(this), false);
        emit Funded(address(this), earned);

        // Leveraged buyback: borrow at BLV, buy more bTokens, lock as collateral
        uint256 debtAdded = IBCredit(baseline).leverage(bToken, targetCollateral, collateralIn, limit);

        // Clear any leftover approval
        IERC20(reserveToken).forceApprove(baseline, 0);

        emit Executed(targetCollateral, collateralIn, debtAdded);
    }

    /*//////////////////////////////////////////////////////////////
                           UPGRADE AUTH
    //////////////////////////////////////////////////////////////*/

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
