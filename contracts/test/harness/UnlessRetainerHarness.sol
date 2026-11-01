// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {UnlessRetainer} from "../../UnlessRetainer.sol";

/// @notice Test-only harness. Exposes the internal storage of UnlessRetainer through read-only
/// accessors while the public view functions are still stubs. It overrides nothing.
contract UnlessRetainerHarness is UnlessRetainer {
    constructor(IERC20 usdc_) UnlessRetainer(usdc_) {}

    function retainerOf(uint256 id) external view returns (Retainer memory) {
        return _retainers[id];
    }

    function claimOf(uint256 id, uint256 claimId) external view returns (Claim memory) {
        return _claims[id][claimId];
    }

    function clientRetainerIds(address a) external view returns (uint256[] memory) {
        return _clientRetainers[a];
    }

    function freelancerRetainerIds(address a) external view returns (uint256[] memory) {
        return _freelancerRetainers[a];
    }

    /// @dev balance - reserved
    function availableOf(uint256 id) external view returns (uint256) {
        Retainer storage r = _retainers[id];
        return uint256(r.balance) - uint256(r.reserved);
    }
}
