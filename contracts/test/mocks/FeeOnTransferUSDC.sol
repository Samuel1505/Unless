// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MockUSDC} from "./MockUSDC.sol";

/// @notice MockUSDC that takes a flat fee on transferFrom: the recipient receives `value - fee`
/// and the fee is burned from the sender. Proves the deposit balance-delta check (DepositMismatch).
/// @dev Lives in test/ only. See docs/04-TEST-PLAN.md section 4.3 and P0 ruling 6.
contract FeeOnTransferUSDC is MockUSDC {
    /// @notice Flat fee in base units taken on every transferFrom (capped at the amount).
    uint256 public fee = 1;

    function setFee(uint256 newFee) external {
        fee = newFee;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        uint256 taken = value < fee ? value : fee;
        _spendAllowance(from, msg.sender, value);
        _transfer(from, to, value - taken);
        if (taken > 0) _burn(from, taken);
        return true;
    }
}
