// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.10;

import '../tools/math/Math.sol';
import '../tools/tokens/ERC20MintableBalancelessBase.sol';
import '../tools/tokens/IERC1363.sol';

abstract contract InvestmentCurrencyBase is ERC20MintableBalancelessBase {
  using InvestAccount for InvestAccount.Balance;
  using Math for uint256;

  uint8 internal constant FLAG_LOCKED = 1 << 0; // MUST be equal to InvestAccount.FLAG_LOCKED
  uint8 internal constant FLAG_MANAGED = 1 << 1; // MUST be equal to InvestAccount.FLAG_INVESTED
  uint8 internal constant FLAG_TRANSFER_CALLBACK = 1 << 2;
  uint8 internal constant FLAG_MINT = 1 << 3;
  uint8 internal constant FLAG_BURN = 1 << 4;

  mapping(address => InvestAccount.Balance) private _accounts;
  uint128 private _totalSupply;
  uint128 private _totalNonInvest;

  function _onlyWithAnyFlags(uint256 flags) private view {
    Access.require(_accounts[msg.sender].flags() & flags == flags && flags != 0);
  }

  modifier onlyWithFlags(uint256 flags) {
    _onlyWithAnyFlags(flags);
    _;
  }

  function totalSupply() public view override returns (uint256) {
    return _totalSupply;
  }

  function totalAndInvestedSupply() public view returns (uint256 total, uint256 totalInvested) {
    total = _totalSupply;
    totalInvested = total - _totalNonInvest;
  }

  function updateTotalSupply(uint256 decrement, uint256 increment) internal virtual override {
    Arithmetic.require((_totalSupply = uint128((_totalSupply - decrement) + increment)) >= increment);
  }

  function updateNonInvestSupply(uint256 decrement, uint256 increment) internal virtual {
    Arithmetic.require((_totalNonInvest = uint128((_totalNonInvest - decrement) + increment)) >= increment);
  }

  function balanceOf(address account) public view returns (uint256) {
    return _accounts[account].balance();
  }

  error BalanceOperationRestricted();

  function requireSafeOp(bool ok) internal pure {
    if (!ok) {
      revert BalanceOperationRestricted();
    }
  }

  function internalIsSelfAllowed(address) internal view virtual returns (bool) {}

  function incrementBalance(address account, uint256 amount) internal override {
    // TODO: fund to this - yield inbound
    InvestAccount.Balance to = _accounts[account];
    requireSafeOp(to.isNotLocked() || internalIsSelfAllowed(account));
    if (amount > 0) {
      _incBalance(account, to, amount);
    }
  }

  function decrementBalance(address account, uint256 amount) internal override {
    InvestAccount.Balance from = _accounts[account];
    requireSafeOp(from.isNotInvested());
    if (amount > 0) {
      _decBalance(account, from, amount);
    }
  }

  function transferBalance(
    address sender,
    address recipient,
    uint256 amount
  ) internal override {
    InvestAccount.Balance from = _accounts[sender];
    InvestAccount.Balance to = _accounts[recipient];

    requireSafeOp(recipient != address(this));

    if (to.flags() & FLAG_MANAGED == 0) {
      // user to user
      // insurer to user (mcd)
      // insurer to insured
      requireSafeOp(from.isNotLocked());
      requireSafeOp(from.flags() & FLAG_MANAGED != 0 || to.isNotLocked());
    } else {
      // user to insurer
      // any to insurer (transferFrom only)
      // this to insurer - yield outbound
      requireSafeOp(to.isNotLocked());
      requireSafeOp(from.isNotInvested() || recipient == msg.sender || internalIsSelfAllowed(sender));
    }

    if (amount > 0) {
      _decBalance(sender, from, amount);
      _incBalance(recipient, to, amount);
    }
  }

  function _transferAndEmit(
    address sender,
    address recipient,
    uint256 amount,
    address onBehalf
  ) internal override {
    super._transferAndEmit(sender, recipient, amount, onBehalf);
    _notifyRecipient(onBehalf, recipient, amount);
  }

  function _notifyRecipient(
    address sender,
    address recipient,
    uint256 amount
  ) private {
    if (msg.sender != recipient && _accounts[recipient].flags() & FLAG_TRANSFER_CALLBACK != 0) {
      IERC1363Receiver(recipient).onTransferReceived(msg.sender, sender, amount, '');
    }
  }

  function _mintAndTransfer(
    address sender,
    address recipient,
    uint256 amount
  ) internal override {
    super._mintAndTransfer(sender, recipient, amount);
    _notifyRecipient(sender, recipient, amount);
  }

  function internalLockBalance(address account, bool lock) internal {
    InvestAccount.Balance acc = _accounts[account];
    _updateAccount(account, acc, acc.flipLockCount(lock));
  }

  function _updateAccount(
    address account,
    InvestAccount.Balance accBefore,
    InvestAccount.Balance accAfter
  ) private {
    Value.require(account != address(0));
    if (accAfter.eq(accBefore)) {
      return;
    }
    _updateAccountUnchecked(account, accBefore, accAfter);
  }

  function _incBalance(
    address account,
    InvestAccount.Balance before,
    uint256 amount
  ) private {
    _updateAccountUnchecked(account, before, before.setBalance((before.balance() + amount).asUint128()));
  }

  function _decBalance(
    address account,
    InvestAccount.Balance before,
    uint256 amount
  ) private {
    _updateAccountUnchecked(account, before, before.setBalance(uint128(before.balance() - amount)));
  }

  function _updateAccountUnchecked(
    address account,
    InvestAccount.Balance accBefore,
    InvestAccount.Balance accAfter
  ) private {
    uint256 bBefore = accBefore.isNotInvested() ? accBefore.balance() : 0;
    uint256 bAfter = accAfter.isNotInvested() ? accAfter.balance() : 0;

    if (bBefore != bAfter && bBefore != 0) {
      uint104 beforeBase = accBefore.yieldBase();
      uint104 afterBase = internalGetCurrentYieldBase();
      if (beforeBase < afterBase) {
        accAfter = accAfter.setYieldBase(afterBase);
        internalAddAccountYield(account, bBefore, beforeBase, afterBase);
      }
    }

    _accounts[account] = accAfter;

    if (bBefore != bAfter) {
      updateNonInvestSupply(bBefore, bAfter);
    }
  }

  function internalGetCurrentYieldBase() internal view virtual returns (uint104);

  function internalAddAccountYield(
    address account,
    uint256 balance,
    uint256 baseBefore,
    uint256 baseAfter
  ) internal virtual;

  function internalPullYield(address account) internal returns (uint256) {
    // InvestAccount.Balance acc = _accounts[account];
  }

  function internalGetFlags(address account) internal view returns (uint256 flags) {
    InvestAccount.Balance acc = _accounts[account];
    flags = acc.flags();
    if (acc.lockCount() != 0) {
      flags |= FLAG_LOCKED;
    }
  }

  function internalUpdateFlags(
    address account,
    uint8 unsetFlags,
    uint8 setFlags
  ) internal {
    InvestAccount.Balance acc = _accounts[account];
    _updateAccount(account, acc, acc.setFlags(setFlags | (acc.flags() & ~unsetFlags)));
  }

  function internalUnsetFlags(address account) internal {
    InvestAccount.Balance acc = _accounts[account];
    _updateAccount(account, acc, acc.setFlags(0));
  }
}

library InvestAccount {
  type Balance is uint256;

  uint8 internal constant FLAG_LOCKED = 1 << 0;
  uint8 internal constant FLAG_INVESTED = 1 << 1;

  function balance(Balance v) internal pure returns (uint128) {
    return uint128(Balance.unwrap(v));
  }

  uint8 private constant OFS_YIELD_BASE = 128;

  function yieldBase(Balance v) internal pure returns (uint104) {
    return uint104(Balance.unwrap(v) >> OFS_YIELD_BASE);
  }

  uint8 private constant OFS_LOCK_COUNT = OFS_YIELD_BASE + 104;

  function eq(Balance v0, Balance v1) internal pure returns (bool) {
    return Balance.unwrap(v0) == Balance.unwrap(v1);
  }

  function lockCount(Balance v) internal pure returns (uint16) {
    return uint16(Balance.unwrap(v) >> OFS_LOCK_COUNT);
  }

  uint256 private constant MASK_LOCKED = (uint256(FLAG_LOCKED) << 16) | 0xFFFF;
  uint256 private constant MASK_INVESTED = (uint256(FLAG_INVESTED) << 16) | MASK_LOCKED;

  function isNotLocked(Balance v) internal pure returns (bool) {
    return (Balance.unwrap(v) >> OFS_LOCK_COUNT) & MASK_LOCKED == 0;
  }

  function isNotInvested(Balance v) internal pure returns (bool) {
    return (Balance.unwrap(v) >> OFS_LOCK_COUNT) & MASK_INVESTED == 0;
  }

  uint8 private constant OFS_FLAGS = OFS_LOCK_COUNT + 16;

  function flags(Balance v) internal pure returns (uint8 u) {
    return uint8(Balance.unwrap(v) >> OFS_FLAGS);
  }

  function flipLockCount(Balance v, bool inc) internal pure returns (Balance) {
    uint256 u = Balance.unwrap(v);
    uint16 c = uint16(u >> OFS_LOCK_COUNT);
    if (c != 0) {
      u ^= uint256(c) << OFS_LOCK_COUNT;
    }
    return Balance.wrap(u | (uint256(inc ? c + 1 : c - 1) << OFS_LOCK_COUNT));
  }

  function setBalance(Balance v, uint128 b) internal pure returns (Balance) {
    return Balance.wrap((Balance.unwrap(v) & (type(uint256).max << 128)) | b);
  }

  function setYieldBase(Balance v, uint104 b) internal pure returns (Balance) {
    return setMasked(v, b, type(uint104).max, OFS_YIELD_BASE);
  }

  function setFlags(Balance v, uint8 f) internal pure returns (Balance) {
    return setMasked(v, f, type(uint8).max, OFS_FLAGS);
  }

  function setMasked(
    Balance v,
    uint256 value,
    uint256 mask,
    uint8 shift
  ) private pure returns (Balance) {
    return Balance.wrap((Balance.unwrap(v) & ~(mask << shift)) | (value << shift));
  }
}
