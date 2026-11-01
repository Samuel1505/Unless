// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MockUSDC} from "./MockUSDC.sol";

/// @notice MockUSDC whose transfer returns false (instead of reverting) when the recipient is
/// blocked. Exercises the `ret` decoding branch of the contract's outbound payment routine.
/// @dev Lives in test/ only. See docs/04-TEST-PLAN.md section 2.1.
contract FalseReturnUSDC is MockUSDC {
    mapping(address => bool) public blocked;

    function setBlocked(address account, bool isBlocked) external {
        blocked[account] = isBlocked;
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        if (blocked[to]) return false;
        return super.transfer(to, value);
    }
}
