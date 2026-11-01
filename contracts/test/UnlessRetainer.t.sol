// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {UnlessRetainer} from "../UnlessRetainer.sol";
import {UnlessRetainerBase} from "./UnlessRetainer.Base.t.sol";

/// @notice Unit tests: constructor (4.1) and createRetainer (4.2).
contract UnlessRetainerTest is UnlessRetainerBase {
    // ---------------------------------------------------------------- 4.1 constructor

    function test_constructor_setsUSDC() public view {
        assertEq(address(retainer.USDC()), address(usdc));
    }

    function test_constructor_zeroAddress_revertsInvalidToken() public {
        vm.expectRevert(UnlessRetainer.InvalidToken.selector);
        new UnlessRetainer(IERC20(address(0)));
    }

    function test_constants_matchSpec() public view {
        assertEq(retainer.MIN_WINDOW(), MIN_WINDOW);
        assertEq(retainer.MAX_WINDOW(), MAX_WINDOW);
        assertEq(retainer.MIN_NOTICE(), MIN_NOTICE);
        assertEq(retainer.MAX_NOTICE(), MAX_NOTICE);
        assertEq(retainer.MAX_PENDING_CLAIMS(), MAX_PENDING);
        assertEq(retainer.MAX_TEXT_BYTES(), MAX_TEXT);
    }

    // ---------------------------------------------------------------- 4.2 createRetainer: success

    function test_createRetainer_happyPath_storesFieldsIndexesAndEmitsInOrder() public {
        uint128 dep = 10e6;
        _approve(client, dep);

        vm.recordLogs();
        _expectCreated(0, client, freelancer, WINDOW, NOTICE, END);
        _expectDeposited(0, client, dep, dep);
        vm.prank(client);
        uint256 id = retainer.createRetainer(freelancer, WINDOW, NOTICE, END, dep);

        assertEq(id, 0, "first id is 0");
        assertEq(retainer.nextRetainerId(), 1);

        UnlessRetainer.Retainer memory r = retainer.retainerOf(0);
        assertEq(r.client, client);
        assertEq(r.freelancer, freelancer);
        assertEq(uint256(r.objectionWindow), uint256(WINDOW));
        assertEq(uint256(r.noticePeriod), uint256(NOTICE));
        assertEq(uint256(r.endTime), uint256(END));
        assertEq(uint256(r.balance), dep);
        assertEq(uint256(r.reserved), 0);
        assertEq(uint256(r.withdrawalAmount), 0);
        assertEq(uint256(r.withdrawalReadyAt), 0);
        assertEq(uint256(r.claimCount), 0);
        assertEq(uint256(r.pendingClaims), 0);
        assertEq(uint256(r.totalDeposited), dep);
        assertEq(uint256(r.totalPaid), 0);
        assertEq(uint256(r.totalReturned), 0);
        assertEq(uint256(r.createdAt), block.timestamp);

        uint256[] memory byClient = retainer.clientRetainerIds(client);
        uint256[] memory byFreelancer = retainer.freelancerRetainerIds(freelancer);
        assertEq(byClient.length, 1);
        assertEq(byClient[0], 0);
        assertEq(byFreelancer.length, 1);
        assertEq(byFreelancer[0], 0);

        // Order: RetainerCreated first, then Deposited, and nothing else from the retainer.
        Vm.Log[] memory logs = _retainerLogs(vm.getRecordedLogs());
        assertEq(logs.length, 2, "retainer log count");
        assertEq(logs[0].topics[0], UnlessRetainer.RetainerCreated.selector);
        assertEq(logs[1].topics[0], UnlessRetainer.Deposited.selector);
    }

    function test_createRetainer_calledRepeatedly_incrementsIdsAndAppendsIndexes() public {
        uint256 a = _createFor(client, freelancer, 0);
        uint256 b = _createFor(client, freelancer2, 0);
        uint256 c = _createFor(client2, freelancer, 0);
        assertEq(a, 0);
        assertEq(b, 1);
        assertEq(c, 2);
        assertEq(retainer.nextRetainerId(), 3);

        uint256[] memory ofClient = retainer.clientRetainerIds(client);
        assertEq(ofClient.length, 2);
        assertEq(ofClient[0], 0);
        assertEq(ofClient[1], 1);
        uint256[] memory ofClient2 = retainer.clientRetainerIds(client2);
        assertEq(ofClient2.length, 1);
        assertEq(ofClient2[0], 2);
        uint256[] memory ofFreelancer = retainer.freelancerRetainerIds(freelancer);
        assertEq(ofFreelancer.length, 2);
        assertEq(ofFreelancer[0], 0);
        assertEq(ofFreelancer[1], 2);
        uint256[] memory ofFreelancer2 = retainer.freelancerRetainerIds(freelancer2);
        assertEq(ofFreelancer2.length, 1);
        assertEq(ofFreelancer2[0], 1);
        assertEq(retainer.clientRetainerIds(stranger).length, 0);
    }

    function test_createRetainer_zeroInitialDeposit_movesNoTokensAndEmitsNoDeposited() public {
        vm.recordLogs();
        _expectCreated(0, client, freelancer, WINDOW, NOTICE, END);
        vm.prank(client);
        uint256 id = retainer.createRetainer(freelancer, WINDOW, NOTICE, END, 0);

        assertEq(id, 0);
        _assertState(0, 0, 0, 0, 0, 0, 0);
        assertEq(usdc.balanceOf(client), START_BALANCE);
        assertEq(usdc.balanceOf(address(retainer)), 0);

        Vm.Log[] memory all = vm.getRecordedLogs();
        for (uint256 i = 0; i < all.length; i++) {
            assertTrue(all[i].emitter != address(usdc), "no token event");
        }
        Vm.Log[] memory logs = _retainerLogs(all);
        assertEq(logs.length, 1, "only RetainerCreated, no Deposited");
        assertEq(logs[0].topics[0], UnlessRetainer.RetainerCreated.selector);
    }

    function test_createRetainer_withDeposit_recordsBalanceAndMovesTokens() public {
        _approve(client, 25e6);
        _expectCreated(0, client, freelancer, WINDOW, NOTICE, END);
        _expectDeposited(0, client, 25e6, 25e6);
        vm.prank(client);
        retainer.createRetainer(freelancer, WINDOW, NOTICE, END, 25e6);

        _assertState(0, 25e6, 0, 25e6, 0, 0, 0);
        assertEq(usdc.balanceOf(client), START_BALANCE - 25e6);
        assertEq(usdc.balanceOf(address(retainer)), 25e6);
        assertEq(usdc.allowance(client, address(retainer)), 0, "exact allowance consumed");
    }

    // ---------------------------------------------------------------- 4.2 createRetainer: boundary successes

    function test_createRetainer_windowEqualsMin_succeeds() public {
        _expectCreated(0, client, freelancer, MIN_WINDOW, NOTICE, END);
        vm.prank(client);
        retainer.createRetainer(freelancer, MIN_WINDOW, NOTICE, END, 0);
        assertEq(uint256(retainer.retainerOf(0).objectionWindow), uint256(MIN_WINDOW));
    }

    function test_createRetainer_windowEqualsMax_succeeds() public {
        _expectCreated(0, client, freelancer, MAX_WINDOW, NOTICE, END);
        vm.prank(client);
        retainer.createRetainer(freelancer, MAX_WINDOW, NOTICE, END, 0);
        assertEq(uint256(retainer.retainerOf(0).objectionWindow), uint256(MAX_WINDOW));
    }

    function test_createRetainer_noticeEqualsMin_succeeds() public {
        _expectCreated(0, client, freelancer, WINDOW, MIN_NOTICE, END);
        vm.prank(client);
        retainer.createRetainer(freelancer, WINDOW, MIN_NOTICE, END, 0);
        assertEq(uint256(retainer.retainerOf(0).noticePeriod), uint256(MIN_NOTICE));
    }

    function test_createRetainer_noticeEqualsMax_succeeds() public {
        uint64 end = uint64(block.timestamp + uint256(MAX_NOTICE) + 1);
        _expectCreated(0, client, freelancer, WINDOW, MAX_NOTICE, end);
        vm.prank(client);
        retainer.createRetainer(freelancer, WINDOW, MAX_NOTICE, end, 0);
        assertEq(uint256(retainer.retainerOf(0).noticePeriod), uint256(MAX_NOTICE));
    }

    function test_createRetainer_endTimeOneAfterNotice_succeeds() public {
        uint64 end = uint64(block.timestamp + uint256(NOTICE) + 1);
        _expectCreated(0, client, freelancer, WINDOW, NOTICE, end);
        vm.prank(client);
        retainer.createRetainer(freelancer, WINDOW, NOTICE, end, 0);
        assertEq(uint256(retainer.retainerOf(0).endTime), uint256(end));
    }

    // ---------------------------------------------------------------- 4.2 createRetainer: reverts

    function _assertNothingCreated() internal view {
        assertEq(retainer.nextRetainerId(), 0, "nextRetainerId");
        assertEq(retainer.clientRetainerIds(client).length, 0);
        assertEq(retainer.freelancerRetainerIds(freelancer).length, 0);
        assertEq(usdc.balanceOf(address(retainer)), 0);
        assertEq(usdc.balanceOf(client), START_BALANCE);
    }

    function test_createRetainer_zeroFreelancer_revertsInvalidFreelancer() public {
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.InvalidFreelancer.selector);
        retainer.createRetainer(address(0), WINDOW, NOTICE, END, 0);
        _assertNothingCreated();
    }

    function test_createRetainer_freelancerIsCaller_revertsInvalidFreelancer() public {
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.InvalidFreelancer.selector);
        retainer.createRetainer(client, WINDOW, NOTICE, END, 0);
        _assertNothingCreated();
    }

    function test_createRetainer_windowBelowMin_revertsWindowOutOfRange() public {
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.WindowOutOfRange.selector);
        retainer.createRetainer(freelancer, MIN_WINDOW - 1, NOTICE, END, 0);
        _assertNothingCreated();
    }

    function test_createRetainer_windowAboveMax_revertsWindowOutOfRange() public {
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.WindowOutOfRange.selector);
        retainer.createRetainer(freelancer, MAX_WINDOW + 1, NOTICE, END, 0);
        _assertNothingCreated();
    }

    function test_createRetainer_noticeBelowMin_revertsNoticeOutOfRange() public {
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.NoticeOutOfRange.selector);
        retainer.createRetainer(freelancer, WINDOW, MIN_NOTICE - 1, END, 0);
        _assertNothingCreated();
    }

    function test_createRetainer_noticeAboveMax_revertsNoticeOutOfRange() public {
        uint64 end = uint64(block.timestamp + uint256(MAX_NOTICE) + 100);
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.NoticeOutOfRange.selector);
        retainer.createRetainer(freelancer, WINDOW, MAX_NOTICE + 1, end, 0);
        _assertNothingCreated();
    }

    function test_createRetainer_endTimeEqualsNowPlusNotice_revertsEndTimeTooSoon() public {
        uint64 end = uint64(block.timestamp + uint256(NOTICE));
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.EndTimeTooSoon.selector);
        retainer.createRetainer(freelancer, WINDOW, NOTICE, end, 0);
        _assertNothingCreated();
    }

    function test_createRetainer_endTimeInPast_revertsEndTimeTooSoon() public {
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.EndTimeTooSoon.selector);
        retainer.createRetainer(freelancer, WINDOW, NOTICE, 0, 0);
        _assertNothingCreated();
    }

    function test_createRetainer_noApproval_revertsERC20InsufficientAllowanceAndStoresNothing() public {
        vm.prank(client);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(retainer), 0, 10e6)
        );
        retainer.createRetainer(freelancer, WINDOW, NOTICE, END, 10e6);
        _assertNothingCreated();
    }

    function test_createRetainer_allowanceOneShort_revertsERC20InsufficientAllowance() public {
        _approve(client, 10e6 - 1);
        vm.prank(client);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(retainer), 10e6 - 1, 10e6
            )
        );
        retainer.createRetainer(freelancer, WINDOW, NOTICE, END, 10e6);
        _assertNothingCreated();
    }

    // ---------------------------------------------------------------- 4.2 createRetainer: check order

    function test_createRetainer_zeroFreelancerAndBadWindow_revertsInvalidFreelancer() public {
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.InvalidFreelancer.selector);
        retainer.createRetainer(address(0), 0, 0, 0, 0);
    }

    function test_createRetainer_freelancerIsCallerAndBadWindow_revertsInvalidFreelancer() public {
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.InvalidFreelancer.selector);
        retainer.createRetainer(client, 0, 0, 0, 0);
    }

    function test_createRetainer_badWindowAndBadNotice_revertsWindowOutOfRange() public {
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.WindowOutOfRange.selector);
        retainer.createRetainer(freelancer, MIN_WINDOW - 1, MIN_NOTICE - 1, 0, 0);
    }

    function test_createRetainer_badNoticeAndEndTooSoon_revertsNoticeOutOfRange() public {
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.NoticeOutOfRange.selector);
        retainer.createRetainer(freelancer, WINDOW, MIN_NOTICE - 1, 0, 0);
    }

    function test_createRetainer_endTooSoonAndNoAllowance_revertsEndTimeTooSoon() public {
        uint64 end = uint64(block.timestamp + uint256(NOTICE));
        vm.prank(client);
        vm.expectRevert(UnlessRetainer.EndTimeTooSoon.selector);
        retainer.createRetainer(freelancer, WINDOW, NOTICE, end, 10e6);
    }
}
