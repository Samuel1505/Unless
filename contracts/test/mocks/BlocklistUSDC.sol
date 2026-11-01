// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MockUSDC} from "./MockUSDC.sol";

/// @notice MockUSDC that mirrors Arc's blocklist: transfers revert when the sender or the
/// recipient is blocked. Minting is not affected.
/// @dev Lives in test/ only. See docs/04-TEST-PLAN.md section 2.1.
contract BlocklistUSDC is MockUSDC {
    error Blocked(address account);

    mapping(address => bool) public blocked;

    function setBlocked(address account, bool isBlocked) external {
        blocked[account] = isBlocked;
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        _checkNotBlocked(msg.sender, to);
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        _checkNotBlocked(from, to);
        return super.transferFrom(from, to, value);
    }

    function _checkNotBlocked(address from, address to) internal view {
        if (blocked[from]) revert Blocked(from);
        if (blocked[to]) revert Blocked(to);
    }
}
