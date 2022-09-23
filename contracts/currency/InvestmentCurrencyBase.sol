// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.10;

import '../tools/math/Math.sol';
import '../tools/tokens/ERC20MintableBalancelessBase.sol';
import '../tools/tokens/IERC1363.sol';
import './interfaces/ISubBalance.sol';

abstract contract InvestmentCurrencyBase is ISubBalance, ERC20MintableBalancelessBase {
  using InvestAccount for InvestAccount.Balance;
  using Math for uint256;

  uint16 internal constant FLAG_MANAGER = 1 << 0; // MUST be equal to InvestAccount.FLAG_MANAGED
  uint16 internal constant FLAG_MANAGED_BALANCE = 1 << 1; // MUST be equal to InvestAccount.FLAG_MANAGED_BALANCE

  uint16 internal constant FLAG_TRANSFER_CALLBACK = 1 << 2;
  uint16 internal constant FLAG_MINT = 1 << 3;
  uint16 internal constant FLAG_BURN = 1 << 4;
  uint256 internal constant FLAG_RESTRICTED = 1 << 16;

  mapping(address => InvestAccount.Balance) private _accounts;
  mapping(address => mapping(address => uint256)) private _subBalances; // [account][giver]
  uint128 private _totalSupply;
  uint128 private _totalNonManaged;

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

  function totalAndManagedSupply() public view virtual returns (uint256 total, uint256 totalManaged) {
    total = _totalSupply;
    totalManaged = total - _totalNonManaged;
  }

  function updateTotalSupply(uint256 decrement, uint256 increment) internal virtual override {
    Arithmetic.require((_totalSupply = uint128((_totalSupply - decrement) + increment)) >= increment);
  }

  function updateNonManagedSupply(uint256 decrement, uint256 increment) internal virtual {
    Arithmetic.require((_totalNonManaged = uint128((_totalNonManaged - decrement) + increment)) >= increment);
  }

  function internalGetBalance(address account) internal view virtual returns (InvestAccount.Balance) {
    return _accounts[account];
  }

  function balanceOf(address account) public view returns (uint256 u) {
    InvestAccount.Balance acc = _accounts[account];
    u = acc.ownBalance();
    return acc.isNotManager() ? u + acc.givenBalance() : u;
  }

  function balancesOf(address account) public view returns (uint256 full, uint256 givenOut, uint256 givenIn) {
    InvestAccount.Balance acc = _accounts[account];
    full = acc.ownBalance();
    if (acc.isNotManager()) {
      givenIn = acc.givenBalance();
      if (!acc.isNotManagedOrRestrictedBalance()) {
        full += givenIn;
      }
    } else {
      full += givenOut = acc.givenBalance();
    }
  }

  function subBalanceOf(address account, address from) public view returns (uint256) {
    return _subBalances[account][from];
  }

  error BalanceOperationRestricted();

  function requireSafeOp(bool ok) internal pure {
    if (!ok) {
      revert BalanceOperationRestricted();
    }
  }

  function incrementBalance(address account, uint256 amount) internal virtual override {
    InvestAccount.Balance to = _accounts[account];
    if (amount > 0) {
      _updateBalance(account, to, to.incOwnBalance(amount));
    }
  }

  function decrementBalance(address account, uint256 amount) internal override {
    InvestAccount.Balance from = _accounts[account];
    requireSafeOp(from.isNotManager());
    if (amount > 0) {
      _updateBalance(account, from, from.decOwnBalance(amount));
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

    if (to.isNotManager()) {
      // user to user
      // insurer to user (mcd)
      // insurer to insured
      // insured to user (non-given portion only)

      from = from.decOwnBalance(amount);

      if (to.isNotRestricted() || from.isNotManager()) {
        _updateNonManagedTransfer(sender, from, recipient, to, amount);

        to = to.incOwnBalance(amount);
      } else {
        Sanity.require(from.isNotRestricted());

        from = from.incGivenBalance(amount);
        to = to.incGivenBalance(amount);
        _subBalances[recipient][sender] += amount;
      }
    } else {
      // user to insurer
      // !insurer to insurer (transferFrom only)

      requireSafeOp(from.isNotManager());
      Sanity.require(to.isNotRestricted());

      if (from.isNotRestricted()) {
        _updateNonManagedTransfer(sender, from, recipient, to, amount);
        from = from.decOwnBalance(amount);
      } else {
        requireSafeOp(recipient == msg.sender);

        from = from.decGivenBalance(amount);
        to = to.decGivenBalance(amount);
        _subBalances[sender][recipient] -= amount;
      }

      to = to.incOwnBalance(amount);
    }

    _accounts[sender] = from;
    _accounts[recipient] = to;
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

  function internalSubBalance(
    address account,
    bool lock,
    uint256 amount
  ) internal {
    (InvestAccount.Balance acc, bool edge) = _accounts[account].flipRefCount(lock);
    if (lock) {
      Value.require(amount == 0);
    } else {
      acc = acc.decGivenBalance(amount);
      Sanity.require((_subBalances[account][msg.sender] -= amount) == 0);
    }

    Sanity.require(!edge || acc.givenBalance() == 0);
    _accounts[account] = acc;
  }

  function _updateNonManagedTransfer(
    address sender,
    InvestAccount.Balance from,
    address recipient,
    InvestAccount.Balance to,
    uint256 amount
  ) private {
    if (from.isNotManagedBalance()) {
      if (!to.isNotManagedBalance()) {
        internalBeforeManagedBalanceUpdate(recipient, to);
        updateNonManagedSupply(amount, 0);
      }
    } else {
      if (to.isNotManagedBalance()) {
        internalBeforeManagedBalanceUpdate(sender, from);
        updateNonManagedSupply(0, amount);
      }
    }
  }

  function _updateBalance(
    address account,
    InvestAccount.Balance accBefore,
    InvestAccount.Balance accAfter
  ) private {
    uint256 bBefore = accBefore.isNotManagedBalance() ? accBefore.ownBalance() : 0;
    uint256 bAfter = accAfter.isNotManagedBalance() ? accAfter.ownBalance() : 0;
    if (bBefore != bAfter) {
      updateNonManagedSupply(bBefore, bAfter);
    }
    _accounts[account] = accAfter;
  }

  function _updateFlags(
    address account,
    InvestAccount.Balance accBefore,
    InvestAccount.Balance accAfter
  ) private {
    uint16 flagDiff = accBefore.flags() ^ accAfter.flags();
    if (flagDiff & FLAG_MANAGER != 0) {
      State.require(accAfter.givenBalance() == 0);
      if (accAfter.isNotManager()) {
        // flag was unset
        State.require(accAfter.ownBalance() == 0);
      }
    }
    if (flagDiff != 0) {
      internalBeforeManagedBalanceUpdate(account, accBefore);
    }

    _updateBalance(account, accBefore, accAfter);
  }

  function internalBeforeManagedBalanceUpdate(address, InvestAccount.Balance) internal virtual;

  // function managedBalanceOf(address account) internal view returns (uint256) {
  //   InvestAccount.Balance acc = _accounts[account];
  //   return acc.isNotManaged() ? 0 : acc.ownBalance() + acc.givenBalance();
  // }

  function internalGetFlags(address account) internal view returns (uint256 flags) {
    InvestAccount.Balance acc = _accounts[account];
    flags = acc.flags();
    if (acc.refCount() != 0) {
      flags |= FLAG_RESTRICTED;
    }
  }

  function internalUpdateFlags(
    address account,
    uint16 unsetFlags,
    uint16 setFlags
  ) internal {
    Value.require(account != address(0));
    InvestAccount.Balance acc = _accounts[account];
    _updateFlags(account, acc, acc.setFlags(setFlags | (acc.flags() & ~unsetFlags)));
  }

  function internalUnsetFlags(address account) internal {
    Value.require(account != address(0));
    InvestAccount.Balance acc = _accounts[account];
    _updateFlags(account, acc, acc.setFlags(0));
  }
}

library InvestAccount {
  type Balance is uint256;

  uint16 internal constant FLAG_MANAGER = 1 << 0;
  uint16 internal constant FLAG_MANAGED_BALANCE = 1 << 1;

  function eq(Balance v0, Balance v1) internal pure returns (bool) {
    return Balance.unwrap(v0) == Balance.unwrap(v1);
  }

  function ownBalance(Balance v) internal pure returns (uint112) {
    return uint112(Balance.unwrap(v));
  }

  uint8 private constant OFS_GIVEN_BALANCE = 112;

  function givenBalance(Balance v) internal pure returns (uint112) {
    return uint104(Balance.unwrap(v) >> OFS_GIVEN_BALANCE);
  }

  uint8 private constant OFS_REF_COUNT = OFS_GIVEN_BALANCE + 112;

  function refCount(Balance v) internal pure returns (uint16) {
    return uint16(Balance.unwrap(v) >> OFS_REF_COUNT);
  }

  uint256 private constant MASK_RESTRICTED = 0xFFFF;

  uint256 private constant INT_FLAG_MANAGER = uint256(FLAG_MANAGER) << OFS_FLAGS;
  uint256 private constant INT_FLAG_MANAGED_BALANCE = uint256(FLAG_MANAGED_BALANCE | FLAG_MANAGER) << OFS_FLAGS;

  function isNotRestricted(Balance v) internal pure returns (bool) {
    return refCount(v) == 0;
  }

  function isNotManagedBalance(Balance v) internal pure returns (bool) {
    return Balance.unwrap(v) & INT_FLAG_MANAGED_BALANCE == 0;
  }

  function isNotManagedOrRestrictedBalance(Balance v) internal pure returns (bool) {
    return Balance.unwrap(v) & (MASK_RESTRICTED | INT_FLAG_MANAGED_BALANCE) == 0;
  }

  function isNotManager(Balance v) internal pure returns (bool) {
    return Balance.unwrap(v) & INT_FLAG_MANAGER == 0;
  }

  uint8 private constant OFS_FLAGS = OFS_REF_COUNT + 16;

  function flags(Balance v) internal pure returns (uint16 u) {
    return uint16(Balance.unwrap(v) >> OFS_FLAGS);
  }

  function flipRefCount(Balance v, bool inc) internal pure returns (Balance, bool edge) {
    uint256 u = Balance.unwrap(v);
    uint16 c = uint16(u >> OFS_REF_COUNT);
    if (c != 0) {
      u ^= uint256(c) << OFS_REF_COUNT;
    }
    edge = (inc ? c++ : --c) == 0;
    return (Balance.wrap(u | (uint256(c) << OFS_REF_COUNT)), edge);
  }

  function setOwnBalance(Balance v, uint112 b) internal pure returns (Balance) {
    return Balance.wrap((Balance.unwrap(v) & (type(uint256).max << OFS_GIVEN_BALANCE)) | b);
  }

  function setGivenBalance(Balance v, uint112 b) internal pure returns (Balance) {
    return setMasked(v, b, type(uint112).max, OFS_GIVEN_BALANCE);
  }

  function setFlags(Balance v, uint16 f) internal pure returns (Balance) {
    return setMasked(v, f, type(uint16).max, OFS_FLAGS);
  }

  function setMasked(
    Balance v,
    uint256 value,
    uint256 mask,
    uint8 shift
  ) private pure returns (Balance) {
    return Balance.wrap((Balance.unwrap(v) & ~(mask << shift)) | (value << shift));
  }

  function incOwnBalance(Balance v, uint256 amount) internal pure returns (Balance) {
    unchecked {
      v = Balance.wrap(Balance.unwrap(v) + amount);
    }
    Arithmetic.require(ownBalance(v) >= amount);
    return v;
  }

  function decOwnBalance(Balance v, uint256 amount) internal pure returns (Balance) {
    Arithmetic.require(ownBalance(v) >= amount);
    unchecked {
      return Balance.wrap(Balance.unwrap(v) - amount);
    }
  }

  function incGivenBalance(Balance v, uint256 amount) internal pure returns (Balance) {
    unchecked {
      v = Balance.wrap(Balance.unwrap(v) + (amount << OFS_GIVEN_BALANCE));
    }
    Arithmetic.require(givenBalance(v) >= amount);
    return v;
  }

  function decGivenBalance(Balance v, uint256 amount) internal pure returns (Balance) {
    Arithmetic.require(givenBalance(v) >= amount);
    unchecked {
      return Balance.wrap(Balance.unwrap(v) - (amount << OFS_GIVEN_BALANCE));
    }
  }
}
