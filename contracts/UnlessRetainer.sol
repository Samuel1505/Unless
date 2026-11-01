// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract UnlessRetainer is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable USDC;

    uint256 public constant MIN_WINDOW = 60;
    uint256 public constant MAX_WINDOW = 30 days;
    uint256 public constant MIN_NOTICE = 60;
    uint256 public constant MAX_NOTICE = 60 days;
    uint256 public constant MAX_PENDING_CLAIMS = 20;
    uint256 public constant MAX_TEXT_BYTES = 280;

    enum ClaimStatus { None, Pending, Paid, Objected, Cancelled }
    enum PaidVia     { None, ApprovedNow, PaidOut }

    struct Retainer {
        // slot 0
        address client;
        uint32  objectionWindow;   // seconds
        uint32  noticePeriod;      // seconds
        // slot 1
        address freelancer;
        uint64  endTime;           // unix seconds; claims allowed while block.timestamp < endTime
        // slot 2
        uint128 balance;           // USDC (6dp) held for this retainer
        uint128 reserved;          // sum of Pending claim amounts
        // slot 3
        uint128 withdrawalAmount;  // 0 = no pending withdrawal
        uint64  withdrawalReadyAt; // 0 = no pending withdrawal
        uint32  claimCount;        // total claims ever filed; next claimId = claimCount
        uint16  pendingClaims;     // number of Pending claims
        // slot 4
        uint128 totalDeposited;
        uint128 totalPaid;         // to freelancer
        // slot 5
        uint128 totalReturned;     // to client
        uint64  createdAt;
    }

    struct Claim {
        uint128     amount;
        uint64      filedAt;
        uint64      payableAt;     // filedAt + objectionWindow
        ClaimStatus status;
        PaidVia     paidVia;
        bytes32     noteHash;      // keccak256(bytes(note)); full note is in the ClaimFiled event
    }

    uint256 public nextRetainerId;                                   // starts at 0
    mapping(uint256 => Retainer) internal _retainers;
    mapping(uint256 => mapping(uint256 => Claim)) internal _claims;  // retainerId => claimId => Claim
    mapping(address => uint256[]) internal _clientRetainers;
    mapping(address => uint256[]) internal _freelancerRetainers;
    mapping(address => uint256) public owed;                         // credit-fallback ledger
    uint256 public totalOwed;

    event RetainerCreated(uint256 indexed id, address indexed client, address indexed freelancer,
                          uint32 objectionWindow, uint32 noticePeriod, uint64 endTime);
    event Deposited(uint256 indexed id, address indexed from, uint128 amount, uint128 newBalance);
    event ClaimFiled(uint256 indexed id, uint256 indexed claimId, uint128 amount, uint64 payableAt, string note);
    event ClaimObjected(uint256 indexed id, uint256 indexed claimId, string reason);
    event ClaimCancelled(uint256 indexed id, uint256 indexed claimId);
    event ClaimPaid(uint256 indexed id, uint256 indexed claimId, address indexed to, uint128 amount, PaidVia via);
    event WithdrawalRequested(uint256 indexed id, uint128 amount, uint64 readyAt);
    event WithdrawalCancelled(uint256 indexed id);
    event WithdrawalCompleted(uint256 indexed id, uint128 requested, uint128 paid);
    event RemainderWithdrawn(uint256 indexed id, uint128 amount);
    event EndTimeExtended(uint256 indexed id, uint64 oldEndTime, uint64 newEndTime);
    event PayoutDeferred(address indexed to, uint256 amount);
    event OwedWithdrawn(address indexed to, uint256 amount);

    error InvalidToken();
    error InvalidFreelancer();
    error WindowOutOfRange();
    error NoticeOutOfRange();
    error EndTimeTooSoon();
    error EndTimeNotLater();
    error RetainerNotFound();
    error ClaimNotFound();
    error NotClient();
    error NotFreelancer();
    error RetainerEnded();
    error RetainerNotEnded();
    error ZeroAmount();
    error TextTooLong();
    error TooManyPendingClaims();
    error InsufficientAvailable();
    error ClaimNotPending();
    error ObjectionWindowClosed();
    error ObjectionWindowOpen();
    error WithdrawalAlreadyPending();
    error NoWithdrawalPending();
    error NoticeNotElapsed();
    error NothingOwed();
    error DepositMismatch();

    /// @notice Spec 2. Sets the immutable token.
    constructor(IERC20 usdc_) {
        if (address(usdc_) == address(0)) revert InvalidToken();
        USDC = usdc_;
    }

    /// @notice Spec 6.1.
    function createRetainer(
        address freelancer,
        uint32 objectionWindow,
        uint32 noticePeriod,
        uint64 endTime,
        uint128 initialDeposit
    ) external nonReentrant returns (uint256 id) {
        if (freelancer == address(0)) revert InvalidFreelancer();
        if (freelancer == msg.sender) revert InvalidFreelancer();
        if (objectionWindow < MIN_WINDOW || objectionWindow > MAX_WINDOW) revert WindowOutOfRange();
        if (noticePeriod < MIN_NOTICE || noticePeriod > MAX_NOTICE) revert NoticeOutOfRange();
        if (uint256(endTime) <= block.timestamp + uint256(noticePeriod)) revert EndTimeTooSoon();

        id = nextRetainerId++;
        Retainer storage r = _retainers[id];
        r.client = msg.sender;
        r.objectionWindow = objectionWindow;
        r.noticePeriod = noticePeriod;
        r.freelancer = freelancer;
        r.endTime = endTime;
        r.createdAt = uint64(block.timestamp);
        _clientRetainers[msg.sender].push(id);
        _freelancerRetainers[freelancer].push(id);
        emit RetainerCreated(id, msg.sender, freelancer, objectionWindow, noticePeriod, endTime);

        if (initialDeposit > 0) {
            _deposit(r, msg.sender, initialDeposit);
            emit Deposited(id, msg.sender, initialDeposit, r.balance);
        }
    }

    /// @notice Spec 6.2.
    function deposit(uint256 id, uint128 amount) external nonReentrant {
        Retainer storage r = _getRetainer(id);
        if (msg.sender != r.client) revert NotClient();
        if (amount == 0) revert ZeroAmount();
        if (block.timestamp >= r.endTime) revert RetainerEnded();

        _deposit(r, msg.sender, amount);
        emit Deposited(id, msg.sender, amount, r.balance);
    }

    /// @notice Spec 6.5.
    function fileClaim(uint256 id, uint128 amount, string calldata note)
        external nonReentrant returns (uint256 claimId)
    {
        Retainer storage r = _getRetainer(id);
        if (msg.sender != r.freelancer) revert NotFreelancer();
        if (block.timestamp >= r.endTime) revert RetainerEnded();
        if (amount == 0) revert ZeroAmount();
        if (bytes(note).length > MAX_TEXT_BYTES) revert TextTooLong();
        if (r.pendingClaims >= MAX_PENDING_CLAIMS) revert TooManyPendingClaims();
        if (amount > r.balance - r.reserved) revert InsufficientAvailable();

        claimId = r.claimCount++;
        Claim storage c = _claims[id][claimId];
        c.amount = amount;
        c.filedAt = uint64(block.timestamp);
        c.payableAt = uint64(block.timestamp + uint256(r.objectionWindow));
        c.status = ClaimStatus.Pending;
        c.paidVia = PaidVia.None;
        c.noteHash = keccak256(bytes(note));
        r.reserved += amount;
        r.pendingClaims++;
        emit ClaimFiled(id, claimId, amount, c.payableAt, note);
    }

    /// @notice Spec 6.6.
    function approveClaim(uint256 id, uint256 claimId) external nonReentrant {
        Retainer storage r = _getRetainer(id);
        Claim storage c = _getClaim(id, claimId, r);
        if (msg.sender != r.client) revert NotClient();
        if (c.status != ClaimStatus.Pending) revert ClaimNotPending();

        _payClaim(id, claimId, r, c, PaidVia.ApprovedNow);
    }

    /// @notice Spec 6.7.
    function objectToClaim(uint256 id, uint256 claimId, string calldata reason)
        external nonReentrant
    {
        Retainer storage r = _getRetainer(id);
        Claim storage c = _getClaim(id, claimId, r);
        if (msg.sender != r.client) revert NotClient();
        if (c.status != ClaimStatus.Pending) revert ClaimNotPending();
        if (block.timestamp >= c.payableAt) revert ObjectionWindowClosed();
        if (bytes(reason).length > MAX_TEXT_BYTES) revert TextTooLong();

        c.status = ClaimStatus.Objected;
        r.reserved -= c.amount;
        r.pendingClaims--;
        emit ClaimObjected(id, claimId, reason);
    }

    /// @notice Spec 6.8.
    function cancelClaim(uint256 id, uint256 claimId) external nonReentrant {
        Retainer storage r = _getRetainer(id);
        Claim storage c = _getClaim(id, claimId, r);
        if (msg.sender != r.freelancer) revert NotFreelancer();
        if (c.status != ClaimStatus.Pending) revert ClaimNotPending();

        c.status = ClaimStatus.Cancelled;
        r.reserved -= c.amount;
        r.pendingClaims--;
        emit ClaimCancelled(id, claimId);
    }

    /// @notice Spec 6.9.
    function payOutClaim(uint256 id, uint256 claimId) external nonReentrant {
        Retainer storage r = _getRetainer(id);
        Claim storage c = _getClaim(id, claimId, r);
        if (c.status != ClaimStatus.Pending) revert ClaimNotPending();
        if (block.timestamp < c.payableAt) revert ObjectionWindowOpen();

        _payClaim(id, claimId, r, c, PaidVia.PaidOut);
    }

    /// @notice Spec 6.11.
    function requestWithdrawal(uint256 id, uint128 amount) external nonReentrant {
        Retainer storage r = _getRetainer(id);
        if (msg.sender != r.client) revert NotClient();
        if (block.timestamp >= r.endTime) revert RetainerEnded();
        if (r.withdrawalReadyAt != 0) revert WithdrawalAlreadyPending();
        if (amount == 0) revert ZeroAmount();
        if (amount > r.balance - r.reserved) revert InsufficientAvailable();

        r.withdrawalAmount = amount;
        r.withdrawalReadyAt = uint64(block.timestamp + r.noticePeriod);
        emit WithdrawalRequested(id, amount, r.withdrawalReadyAt);
    }

    /// @notice Spec 6.12.
    function cancelWithdrawal(uint256 id) external nonReentrant {
        Retainer storage r = _getRetainer(id);
        if (msg.sender != r.client) revert NotClient();
        if (r.withdrawalReadyAt == 0) revert NoWithdrawalPending();

        r.withdrawalAmount = 0;
        r.withdrawalReadyAt = 0;
        emit WithdrawalCancelled(id);
    }

    /// @notice Spec 6.13.
    function completeWithdrawal(uint256 id) external nonReentrant {
        Retainer storage r = _getRetainer(id);
        if (r.withdrawalReadyAt == 0) revert NoWithdrawalPending();
        if (block.timestamp < r.withdrawalReadyAt) revert NoticeNotElapsed();

        uint128 requested = r.withdrawalAmount;
        uint128 available = r.balance - r.reserved;
        uint128 payout = requested < available ? requested : available;
        r.withdrawalAmount = 0;
        r.withdrawalReadyAt = 0;
        r.balance -= payout;
        r.totalReturned += payout;
        emit WithdrawalCompleted(id, requested, payout);
        if (payout > 0) _send(r.client, payout);
    }

    /// @notice Spec 6.14.
    function withdrawRemainder(uint256 id) external nonReentrant {
        Retainer storage r = _getRetainer(id);
        if (msg.sender != r.client) revert NotClient();
        if (block.timestamp < r.endTime) revert RetainerNotEnded();
        uint128 available = r.balance - r.reserved;
        if (available == 0) revert ZeroAmount();

        if (r.withdrawalReadyAt != 0) {
            r.withdrawalAmount = 0;
            r.withdrawalReadyAt = 0;
            emit WithdrawalCancelled(id);
        }
        uint128 payout = available;
        r.balance -= payout;
        r.totalReturned += payout;
        emit RemainderWithdrawn(id, payout);
        _send(r.client, payout);
    }

    /// @notice Spec 6.15.
    function extendEndTime(uint256 id, uint64 newEndTime) external nonReentrant {
        Retainer storage r = _getRetainer(id);
        if (msg.sender != r.client) revert NotClient();
        if (newEndTime <= r.endTime) revert EndTimeNotLater();

        uint64 oldEndTime = r.endTime;
        r.endTime = newEndTime;
        emit EndTimeExtended(id, oldEndTime, newEndTime);
    }

    /// @notice Spec 6.16.
    function withdrawOwed() external nonReentrant {
        uint256 amount = owed[msg.sender];
        if (amount == 0) revert NothingOwed();

        owed[msg.sender] = 0;
        totalOwed -= amount;
        USDC.safeTransfer(msg.sender, amount);
        emit OwedWithdrawn(msg.sender, amount);
    }

    /// @notice Spec 7.
    function getRetainer(uint256 id)
        external view returns (Retainer memory r, uint256 available, bool ended)
    {
        r = _getRetainer(id);
        available = r.balance - r.reserved;
        ended = block.timestamp >= r.endTime;
    }

    /// @notice Spec 7.
    function getClaim(uint256 id, uint256 claimId) external view returns (Claim memory) {
        Retainer storage r = _getRetainer(id);
        return _getClaim(id, claimId, r);
    }

    /// @notice Spec 7.
    function getClaims(uint256 id, uint256 offset, uint256 limit)
        external view returns (Claim[] memory)
    {
        uint256 claimCount = _retainers[id].claimCount;
        if (offset >= claimCount) return new Claim[](0);
        uint256 available = claimCount - offset;
        if (limit > available) limit = available;

        Claim[] memory claims = new Claim[](limit);
        for (uint256 i = 0; i < limit; i++) {
            claims[i] = _claims[id][offset + i];
        }
        return claims;
    }

    /// @notice Spec 7.
    function retainersOfClient(address a) external view returns (uint256[] memory) {
        return _clientRetainers[a];
    }

    /// @notice Spec 7.
    function retainersOfFreelancer(address a) external view returns (uint256[] memory) {
        return _freelancerRetainers[a];
    }

    function _deposit(Retainer storage r, address payer, uint128 amount) internal {
        uint256 beforeBalance = USDC.balanceOf(address(this));
        USDC.safeTransferFrom(payer, address(this), amount);
        uint256 received = USDC.balanceOf(address(this)) - beforeBalance;
        if (received != amount) revert DepositMismatch();
        r.balance += amount;
        r.totalDeposited += amount;
    }

    function _send(address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = address(USDC).call(
            abi.encodeCall(IERC20.transfer, (to, amount))
        );
        bool success = ok && (ret.length == 0 || (ret.length == 32 && abi.decode(ret, (uint256)) == 1));
        if (!success) {
            owed[to] += amount;
            totalOwed += amount;
            emit PayoutDeferred(to, amount);
        }
    }

    function _payClaim(uint256 id, uint256 claimId, Retainer storage r, Claim storage c, PaidVia via)
        internal
    {
        c.status = ClaimStatus.Paid;
        c.paidVia = via;
        r.reserved -= c.amount;
        r.balance -= c.amount;
        r.totalPaid += c.amount;
        r.pendingClaims -= 1;
        emit ClaimPaid(id, claimId, r.freelancer, c.amount, via);
        _send(r.freelancer, c.amount);
    }

    function _getRetainer(uint256 id) internal view returns (Retainer storage r) {
        r = _retainers[id];
        if (r.client == address(0)) revert RetainerNotFound();
    }

    function _getClaim(uint256 id, uint256 claimId, Retainer storage r)
        internal view returns (Claim storage c)
    {
        if (claimId >= r.claimCount) revert ClaimNotFound();
        c = _claims[id][claimId];
    }
}
