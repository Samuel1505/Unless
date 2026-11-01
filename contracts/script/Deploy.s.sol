// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UnlessRetainer} from "../UnlessRetainer.sol";

contract Deploy is Script {
    address constant ARC_USDC = 0x3600000000000000000000000000000000000000;

    function run() external returns (UnlessRetainer retainer) {
        require(block.chainid == 5042 || block.chainid == 5042002, "not Arc");
        vm.startBroadcast();
        retainer = new UnlessRetainer(IERC20(ARC_USDC));
        vm.stopBroadcast();
        console2.log("UnlessRetainer", address(retainer));
    }
}
