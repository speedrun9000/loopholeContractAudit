// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IFeeRouterReceiver {
    function receiveFees(address bToken, uint256 amount) external;
}

/**
 * @title BTokenFeeForwarder
 * @notice One-per-bToken receiver for pool creator fees. Set as `pool.feeRecipient`
 *         so each bToken's fees land at a unique address, then `flush()` pushes the
 *         balance into the shared ProjectFeeRouter with attribution.
 * @dev    Deployed by ProjectFeeRouterUpgradeable.registerBToken. Has no admin and
 *         no callable surface beyond `flush`. Holding tokens here is structurally
 *         attributed to `bToken`; the router credits `accrued[bToken]` only on a
 *         call from this contract.
 *
 *         Intentionally non-upgradable. Per-instance fields (`bToken`,
 *         `reserveToken`, `router`) are `immutable`; if forwarder logic ever needed
 *         to change, the fix is to deploy new forwarders for new bTokens — existing
 *         pools remain bound to their forwarders for the bToken's lifetime. The
 *         router proxy address is hardcoded into each forwarder, so the router must
 *         be upgraded behind its existing proxy (never migrated to a new address)
 *         or all live forwarders point at a dead address.
 */
contract BTokenFeeForwarder {
    using SafeERC20 for IERC20;

    address public immutable bToken;
    IERC20 public immutable reserveToken;
    address public immutable router;

    error NothingToFlush();

    constructor(address bToken_, IERC20 reserveToken_, address router_) {
        bToken = bToken_;
        reserveToken = reserveToken_;
        router = router_;
    }

    /**
     * @notice Forward all held reserve tokens to the router and credit `bToken`.
     */
    function flush() external {
        uint256 amount = reserveToken.balanceOf(address(this));
        if (amount == 0) revert NothingToFlush();
        reserveToken.safeTransfer(router, amount);
        IFeeRouterReceiver(router).receiveFees(bToken, amount);
    }
}
