// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.10;

import '../tools/math/Math.sol';
import '../tools/tokens/ERC20MintableBalancelessBase.sol';
import '../tools/tokens/IERC1363.sol';
import './interfaces/ISubBalance.sol';

/** 
  @dev This template provides a logic to track managed balances and escrows.
  Managed balances - are balances which are unlikely to be redeemed / swapped, i.e. balances directly or indirectly managed by an insurer. 
  Underlyings of such balances can be more-or-less safely reinvested.
  Unmanaged balances, i.e. balances of users, are considered as non-reinvestable.

  The escrow sub-balances are for safety reasons. An escrow holds a portion of manager's balance reserved for an account, 
  i.e. a portion of coverage from insurer for an insured policy. This reduces amount of collateral currency residing on the insurer. 
  An insurer can add to the escrow or can close it, while insured can not use the escrow'ed balance until it is close.
*/
abstract contract InvestmentCurrencyBase is ISubBalance, ERC20MintableBalancelessBase {
  using InvestAccount for InvestAccount.Balance;
  using Math for uint256;

  /// @dev Marks an account of a collateral manager, i.e. insurer.
  /// @dev A collateral manager manages escow sub-balances of other accounts, balance of the manager is reinvestable.
  // MUST be equal to InvestAccount.FLAG_MANAGER
  uint16 internal constant FLAG_MANAGER = 1 << 0;

  /// @dev Marks an account of with reinvestable balance (but neither manager nor escrow).
  // MUST be equal to InvestAccount.FLAG_MANAGED_BALANCE
  uint16 internal constant FLAG_MANAGED_BALANCE = 1 << 1;

  /// @dev Marks an account that requires IERC1363 callabck
  uint16 internal constant FLAG_TRANSFER_CALLBACK = 1 << 2;
  /// @dev Marks an account allowed to mint
  uint16 internal constant FLAG_MINT = 1 << 3;
  /// @dev Marks an account allowed to burn
  uint16 internal constant FLAG_BURN = 1 << 4;
  uint16 internal constant FLAGS_MASK = type(uint16).max;
  /// @dev This mark is returened when an account has escrow sub-balance.
  uint256 internal constant FLAG_RESTRICTED = 1 << 16;

  /// @dev Balance and total of sub-balances of an account.
  /// @dev Manager's account has total of sub-balances given OUT to escrows, others - total of sub-balances given IN (received) to escrow.
  mapping(address => InvestAccount.Balance) private _accounts;

  /// @dev Individual escrow sub-balances
  mapping(address => mapping(address => uint256)) private _subBalances; // [account][giver]

  uint128 private _totalSupply;
  /// @dev A portion of _totalSupply which is not managed/reinvestable.
  uint128 private _totalNonManaged;

  function _onlyWithAnyFlags(uint256 flags) private view {
    Access.require(_accounts[msg.sender].flags() & flags == flags && flags != 0);
  }

  modifier onlyWithFlags(uint256 flags) {
    _onlyWithAnyFlags(flags);
    _;
  }

  /// @inheritdoc IERC20
  function totalSupply() public view override returns (uint256) {
    return _totalSupply;
  }

  /// @return total amount of token, same as totalSupply()
  /// @return totalManaged amount of token usables for reinvestment, hence eligible to receive yield
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

  /// @inheritdoc IERC20
  function balanceOf(address account) public view override returns (uint256 u) {
    InvestAccount.Balance acc = _accounts[account];
    u = acc.ownBalance();
    return acc.isNotManager() ? u + acc.givenBalance() : u;
  }

  /// @inheritdoc ISubBalance
  function balancesOf(address account)
    public
    view
    returns (
      uint256 full,
      uint256 givenOut,
      uint256 givenIn
    )
  {
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

  /// @inheritdoc ISubBalance
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
      // When the recipient is not a collateral manager (i.e. insurer), then the following types of transfers are acceptable:
      // - user to user
      // - insurer to user - coverage drawdown (mcd), reduces managed total
      // - insurer to insured - transfer coverage to escrow
      // - insured to user - non-escrow portion only

      from = from.decOwnBalance(amount);

      if (to.isNotRestricted() || from.isNotManager()) {
        _updateNonManagedTransfer(sender, from, recipient, to, amount);

        to = to.incOwnBalance(amount);
      } else {
        Sanity.require(from.isNotRestricted());

        // given OUT balance, because `from` is Manager
        from = from.incGivenBalance(amount);
        // given IN balance, because `to` is not Manager
        to = to.incGivenBalance(amount);
        _subBalances[recipient][sender] += amount;
      }
    } else {
      // When the recipient is a collateral manager (i.e. insurer), then the following types of transfers are acceptable:
      // - user to insurer - an investment of collateral, increases managed total
      // - not-insurer to insurer - a subrogation or an indirect investment. ONLY as transferFrom by insurer.
      // Other types of transfers are forbidden.

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
    // IERC1363 callabck
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
    // IERC1363 callabck
    _notifyRecipient(sender, recipient, amount);
  }

  /// @dev Enables/disables escrow between the manager and the account.
  /// @dev An escrow sub-balance is considered as managed, hence, it can be reinvested.
  /// @param manager controls the escrow sub-blanace. The manager can transfer to the sub-balance (NOT from it) or close it.
  /// @param account holds the escrow sub-balance. The holder can NOT spend the escrow sub-balance.
  /// @param enable is true to open the escrow sub-balance or false to close it.
  /// @param transferAmount is a part of the escrow to be released to the `account`, the rest will be returned to `manager`. Must be zero when `enable` is true.
  function internalSubBalance(
    address manager,
    address account,
    bool enable,
    uint256 transferAmount
  ) internal returns (uint256 releaseAmount) {
    (InvestAccount.Balance acc, bool edge) = _accounts[account].flipRefCount(enable);
    releaseAmount = _subBalances[account][manager];
    if (enable) {
      Value.require(transferAmount == 0);
      Value.require(releaseAmount == 0);
    } else {
      if (releaseAmount != 0) {
        acc = acc.decGivenBalance(releaseAmount);
        delete _subBalances[account][manager];
        emit Transfer(account, manager, releaseAmount);
      }

      if (transferAmount != 0 || releaseAmount != 0) {
        InvestAccount.Balance accMgr = _accounts[manager];
        _updateBalance(manager, accMgr, accMgr.incOwnBalance(releaseAmount).decOwnBalance(transferAmount));
        if (transferAmount != 0) {
          acc = acc.incOwnBalance(transferAmount);
          emit Transfer(manager, account, transferAmount);
        }
      }
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
