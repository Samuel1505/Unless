// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {UnlessRetainer} from "../UnlessRetainer.sol";
import {UnlessRetainerBase} from "./UnlessRetainer.Base.t.sol";
import {UnlessRetainerHarness} from "./harness/UnlessRetainerHarness.sol";
import {FeeOnTransferUSDC} from "./mocks/FeeOnTransferUSDC.sol";

/// @notice Unit tests: deposit (4.3).
contract UnlessRetainerDepositTest is UnlessRetainerBase {
    // ---------------------------------------------------------------- success

    function test_deposit_byClient_increasesBalanceAndMovesTokens() public {
        uint256 id = _create(10e6);
        _approve(client, 4e6);

        _expectDeposited(id, client, 4e6, 14e6);
        vm.prank(client);
        retainer.deposit(id, 4e6);

        _assertState(id, 14e6, 0, 14e6, 0, 0, 0);
        assertEq(usdc.balanceOf(client), START_BALANCE - 14e6);
        assertEq(usdc.balanceOf(address(retainer)), 14e6);
    }

    function test_deposit_onRetainerCreatedEmpty_fundsIt() public {
        uint256 id = _create(0);
        _approve(client, 1);
        _expectDeposited(id, client, 1, 1);
        vm.prank(client);
        retainer.deposit(id, 1);
        _assertState(id, 1, 0, 1, 0, 0, 0);
    }

    function test_deposit_multipleDeposits_accumulate() public {
        uint256 id = _create(1e6);
        uint128 running = 1e6;
        uint128[3] memory amounts = [uint128(2e6), uint128(3e6), uint128(5e6)];
        for (uint256 i = 0; i < amounts.length; i++) {
            _approve(client, amounts[i]);
            running += amounts[i];
            _expectDeposited(id, client, amounts[i], running);
            vm.prank(client);
            retainer.deposit(id, amounts[i]);
            _assertState(id, running, 0, running, 0, 0, 0);
        }
        assertEq(uint256(running), 11e6);
        assertEq(usdc.balanceOf(address(retainer)), 11e6);
        assertEq(usdc.balanceOf(client), START_BALANCE - 11e6);
    }

    function test_deposit_oneSecondBeforeEnd_succeeds() public {
        uint256 id = _create(0);
        _approve(client, 3e6);
        vm.warp(uint256(END) - 1);
        _expectDeposited(id, client, 3e6, 3e6);
        vm.prank(client);
        retainer.deposit(id, 3e6);
        _assertState(id, 3e6, 0, 3e6, 0, 0, 0);
    }

    function test_deposit_doesNotTouchOtherRetainers() public {
        uint256 a = _create(5e6);
        uint256 b = _createFor(client2, freelancer2, 7e6);
        _approve(client, 2e6);
        vm.prank(client);
        retainer.deposit(a, 2e6);
        _assertState(a, 7e6, 0, 7e6, 0, 0, 0);
        _assertState(b, 7e6, 0, 7e6, 0, 0, 0);
    }

    // ---------------------------------------------------------------- reverts

    function test_deposit_unknownId_revertsRetainerNotFound() public {
        _create(0);
        _approve(client, 1e6);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.deposit(1, 1e6);
    }

    function test_deposit_noRetainerAtAll_revertsRetainerNotFound() public {
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.deposit(0, 1e6);
    }

    function test_deposit_byFreelancer_revertsNotClient() public {
        uint256 id = _create(0);
        _approve(freelancer, 1e6);
        vm.prank(freelancer);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.deposit(id, 1e6);
    }

    function test_deposit_byStranger_revertsNotClient() public {
        uint256 id = _create(0);
        _approve(stranger, 1e6);
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.deposit(id, 1e6);
        _assertState(id, 0, 0, 0, 0, 0, 0);
    }

    function test_deposit_zeroAmount_revertsZeroAmount() public {
        uint256 id = _create(0);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ZeroAmount.selector);
        retainer.deposit(id, 0);
    }

    function test_deposit_atEndTime_revertsRetainerEnded() public {
        uint256 id = _create(0);
        _approve(client, 1e6);
        vm.warp(END);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.RetainerEnded.selector);
        retainer.deposit(id, 1e6);
    }

    function test_deposit_afterEndTime_revertsRetainerEnded() public {
        uint256 id = _create(0);
        _approve(client, 1e6);
        vm.warp(uint256(END) + 1);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.RetainerEnded.selector);
        retainer.deposit(id, 1e6);
    }

    function test_deposit_noApproval_revertsERC20InsufficientAllowance() public {
        uint256 id = _create(0);
        vm.prank(client);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(retainer), 0, 1e6)
        );
        retainer.deposit(id, 1e6);
        _assertState(id, 0, 0, 0, 0, 0, 0);
    }

    // ---------------------------------------------------------------- check order

    function test_deposit_unknownIdByStrangerWithZeroAmount_revertsRetainerNotFound() public {
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.RetainerNotFound.selector);
        retainer.deposit(42, 0);
    }

    function test_deposit_strangerWithZeroAmount_revertsNotClient() public {
        uint256 id = _create(0);
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.deposit(id, 0);
    }

    function test_deposit_strangerAfterEnd_revertsNotClient() public {
        uint256 id = _create(0);
        vm.warp(END);
        vm.prank(stranger);
        vm.expectRevert(UnlessRetainer.NotClient.selector);
        retainer.deposit(id, 1e6);
    }

    function test_deposit_zeroAmountAfterEnd_revertsZeroAmountBeforeRetainerEnded() public {
        uint256 id = _create(0);
        vm.warp(END);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.ZeroAmount.selector);
        retainer.deposit(id, 0);
    }

    // ---------------------------------------------------------------- DepositMismatch (fee-on-transfer)

    function _feeHarness() internal returns (FeeOnTransferUSDC fee, UnlessRetainerHarness h) {
        fee = new FeeOnTransferUSDC();
        h = new UnlessRetainerHarness(IERC20(address(fee)));
        fee.mint(client, START_BALANCE);
    }

    function test_deposit_feeOnTransferToken_revertsDepositMismatchAndLeavesStateUnchanged() public {
        (FeeOnTransferUSDC fee, UnlessRetainerHarness h) = _feeHarness();
        vm.prank(client);
        uint256 id = h.createRetainer(freelancer, WINDOW, NOTICE, END, 0);
        vm.prank(client);
        fee.approve(address(h), 10e6);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.DepositMismatch.selector);
        h.deposit(id, 10e6);

        UnlessRetainer.Retainer memory r = h.retainerOf(id);
        assertEq(uint256(r.balance), 0);
        assertEq(uint256(r.totalDeposited), 0);
        assertEq(fee.balanceOf(client), START_BALANCE, "client tokens unchanged");
        assertEq(fee.balanceOf(address(h)), 0, "retainer tokens unchanged");
        assertEq(fee.totalSupply(), START_BALANCE, "nothing burned");
        assertEq(fee.allowance(client, address(h)), 10e6, "allowance unchanged");
    }

    function test_createRetainer_feeOnTransferToken_withDeposit_revertsDepositMismatchAndStoresNothing() public {
        (FeeOnTransferUSDC fee, UnlessRetainerHarness h) = _feeHarness();
        vm.prank(client);
        fee.approve(address(h), 10e6);

        vm.prank(client);
        vm.expectRevert(UnlessRetainer.DepositMismatch.selector);
        h.createRetainer(freelancer, WINDOW, NOTICE, END, 10e6);

        assertEq(h.nextRetainerId(), 0, "nothing created");
        assertEq(h.clientRetainerIds(client).length, 0);
        assertEq(h.freelancerRetainerIds(freelancer).length, 0);
        assertEq(fee.balanceOf(client), START_BALANCE);
        assertEq(fee.balanceOf(address(h)), 0);
        assertEq(fee.totalSupply(), START_BALANCE);
    }

    function test_createRetainer_feeOnTransferToken_zeroDeposit_succeeds() public {
        (FeeOnTransferUSDC fee, UnlessRetainerHarness h) = _feeHarness();
        vm.prank(client);
        uint256 id = h.createRetainer(freelancer, WINDOW, NOTICE, END, 0);
        assertEq(id, 0);
        assertEq(fee.balanceOf(address(h)), 0);
    }
}
