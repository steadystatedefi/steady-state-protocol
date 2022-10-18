// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../tools/tokens/ERC20Base.sol';
import '../tools/Errors.sol';
import '../tools/SafeERC20.sol';
import '../tools/math/Math.sol';
import '../tools/math/WadRayMath.sol';
import './interfaces/ILender.sol';
import './interfaces/IReinvestStrategy.sol';

/// @dev A template that facilitates liquidity borrowing between ILender(s) and IReinvestStrategy(s)
abstract contract BorrowBalancesBase {
  using Math for uint256;
  using WadRayMath for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  struct LendedBalance {
    uint16 borrowerIndex;
    uint240 amount;
  }

  struct BorrowerStateInfo {
    address borrower;
  }

  struct TokenLend {
    BorrowerStateInfo[] borrowers;
    mapping(address => LendedBalance) balances; // [borrower]
  }

  mapping(address => mapping(address => TokenLend)) private _lendings; // [token][lender]
  mapping(address => EnumerableSet.AddressSet) private _lendedTokens; // [lender]

  struct TokenBorrow {
    uint256 total;
    EnumerableSet.AddressSet lenders;
  }

  mapping(address => mapping(address => TokenBorrow)) private _borrowings; // [token][borrower]
  mapping(address => EnumerableSet.AddressSet) private _borrowedTokens; // [borrower]

  error AssetIsNotSupported(address asset, address strategy);

  /// @dev Moves `amount` of token from a lender `fromFund` to a strategy `toStrategy`
  function internalPushTo(
    address token,
    address fromFund,
    address toStrategy,
    uint256 amount
  ) internal {
    ILender(fromFund).approveBorrow(msg.sender, token, amount, address(toStrategy));

    TokenBorrow storage borr = _borrowings[token][toStrategy];

    TokenLend storage lend = _lendings[token][fromFund];
    LendedBalance storage lendBalance = lend.balances[toStrategy];

    uint256 index = lendBalance.borrowerIndex;
    uint240 v;
    if (index == 0) {
      _lendedTokens[fromFund].add(token);
      _borrowedTokens[toStrategy].add(token);
      borr.lenders.add(fromFund);

      lend.borrowers.push(BorrowerStateInfo({borrower: toStrategy}));
      Arithmetic.require((lendBalance.borrowerIndex = uint16(lend.borrowers.length)) > 0);
    } else {
      v = lendBalance.amount;
    }
    Arithmetic.require((lendBalance.amount = v + uint240(amount)) >= amount);
    uint256 totalBorrowedBefore = borr.total;
    borr.total = totalBorrowedBefore + amount;

    if (totalBorrowedBefore == 0) {
      if (!IReinvestStrategy(toStrategy).connectAssetBefore(token)) {
        revert AssetIsNotSupported(token, toStrategy);
      }
    }

    IReinvestStrategy(toStrategy).investFrom(token, fromFund, amount);
    Sanity.require(IERC20(token).allowance(fromFund, toStrategy) == 0);

    if (totalBorrowedBefore == 0) {
      IReinvestStrategy(toStrategy).connectAssetAfter(token);
    }
  }

  /// @dev Moves `amount` of token from a strategy `fromStrategy` to a lender `toFund`
  function internalPullFrom(
    address token,
    address fromStrategy,
    address toFund,
    uint256 amount
  ) internal returns (uint256) {
    TokenBorrow storage borr = _borrowings[token][fromStrategy];

    TokenLend storage lend = _lendings[token][toFund];
    LendedBalance storage lendBalance = lend.balances[fromStrategy];

    uint256 index = lendBalance.borrowerIndex;
    if (index == 0) {
      return 0;
    }

    uint256 v = lendBalance.amount;
    if (v == amount || amount == type(uint256).max) {
      amount = v;
      uint256 lastIndex = lend.borrowers.length;
      if (lastIndex != index) {
        BorrowerStateInfo storage info = lend.borrowers[lastIndex - 1];
        lend.borrowers[index - 1] = info;
        lend.balances[info.borrower].borrowerIndex = uint16(index);
      }
      delete lend.balances[fromStrategy];
      lend.borrowers.pop();

      if (lastIndex == 1) {
        _lendedTokens[toFund].remove(token);
      }
    } else {
      lendBalance.amount = uint240(v - amount);
    }

    uint256 totalBorrowed = borr.total - amount;

    uint256 beforeAmount = IReinvestStrategy(fromStrategy).approveDivest(token, toFund, amount, 0);
    if (beforeAmount <= amount) {
      if (beforeAmount < amount) {
        totalBorrowed += amount - beforeAmount;
        amount = beforeAmount;
      }
      if (totalBorrowed == 0) {
        _borrowedTokens[fromStrategy].remove(token);
      }
    }
    borr.total = totalBorrowed;

    ILender(toFund).repayFrom(token, fromStrategy, amount);
    Sanity.require(IERC20(token).allowance(fromStrategy, toFund) == 0);

    return amount;
  }

  /// @dev Moves not more that `maxAmount` of token from a strategy `fromStrategy` to a lender `viaFund` by calling depositYield to the address `to`.
  /// @dev This method will only take an amount above the amount invested by internalPushTo (the amount borrowed).
  /// @return amount that was set to the address `to`.
  function internalPullYieldFrom(
    address token,
    address fromStrategy,
    address viaFund,
    uint256 maxAmount,
    address to
  ) internal returns (uint256 amount) {
    TokenBorrow storage borr = _borrowings[token][fromStrategy];
    uint256 totalBorrowed = borr.total;

    uint256 beforeAmount = IReinvestStrategy(fromStrategy).approveDivest(token, viaFund, maxAmount, totalBorrowed);
    if (beforeAmount > totalBorrowed) {
      amount = beforeAmount - totalBorrowed;
      if (amount > maxAmount) {
        amount = maxAmount;
      }
      ILender(viaFund).depositYield(token, fromStrategy, amount, to);
    }

    Sanity.require(IERC20(token).allowance(fromStrategy, viaFund) == 0);
  }

  /// @dev Repay an `amount` of a borrowed balance of a `token` for a strategy `forStrategy`
  function internalPayLoss(
    address token,
    address from,
    address forStrategy,
    address viaFund,
    uint256 amount,
    address to
  ) internal {
    TokenBorrow storage borr = _borrowings[token][forStrategy];
    borr.total -= amount;
    // TODO should it cover borrowed balance of the fund as well?
    ILender(viaFund).depositYield(token, from, amount, to);
  }

  /// @return totalBorrowed amount of `token` by the `strategy`
  /// @return totalRepayable amount of `token` owned by the `strategy`
  function balancesOf(address token, address strategy) public view returns (uint256 totalBorrowed, uint256 totalRepayable) {
    TokenBorrow storage borr = _borrowings[token][strategy];
    return (borr.total, IReinvestStrategy(strategy).investedValueOf(token));
  }
}
