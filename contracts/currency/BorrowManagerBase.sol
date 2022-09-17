// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../tools/tokens/ERC20Base.sol';
import '../tools/Errors.sol';
import '../tools/SafeERC20.sol';
import '../tools/math/WadRayMath.sol';
import './interfaces/ILender.sol';
import './interfaces/IReinvestStrategy.sol';

abstract contract BorrowManagerBase {
  using WadRayMath for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  struct LendedBalance {
    uint16 borrowerIndex;
    uint256 amount; // todo size
    uint256 yield;
  }

  struct BorrowerStateInfo {
    address borrower;
    uint96 lastAccum;
  }

  struct TokenLend {
    BorrowerStateInfo[] borrowers;
    mapping(address => LendedBalance) balances; // [borrower]
  }

  mapping(address => mapping(address => TokenLend)) private _lendings; // [token][lender]
  mapping(address => EnumerableSet.AddressSet) private _lendedTokens; // [lender]

  struct TokenBorrow {
    uint256 total;
    uint96 accumRate; // wad
    // rate
    // since

    // TODO customBalance

    EnumerableSet.AddressSet lenders;
  }

  mapping(address => mapping(address => TokenBorrow)) private _borrowings; // [token][borrower]
  mapping(address => EnumerableSet.AddressSet) private _borrowedTokens; // [borrower]

  function pushTo(
    address token,
    address fromFund,
    address toStrategy,
    uint256 amount
  ) external {
    // TODO onlyApprovedStrategy(strategy)
    // TODO onlyApprovedFund(fund)

    // ILender(fund).approveBorrow(token, amount, address(strategy));

    TokenBorrow storage borr = _borrowings[token][toStrategy];
    uint96 accumRate = borr.accumRate;

    TokenLend storage lend = _lendings[token][fromFund];
    LendedBalance storage lendBalance = lend.balances[toStrategy];

    uint256 index = lendBalance.borrowerIndex;
    if (index == 0) {
      _lendedTokens[fromFund].add(token);
      _borrowedTokens[toStrategy].add(token);
      borr.lenders.add(fromFund);

      lend.borrowers.push(BorrowerStateInfo({borrower: toStrategy, lastAccum: accumRate}));
      Arithmetic.require((lendBalance.borrowerIndex = uint16(lend.borrowers.length)) > 0);
      lendBalance.amount = amount;
    } else {
      BorrowerStateInfo storage info = lend.borrowers[index - 1];
      uint256 v = lendBalance.amount;
      lendBalance.amount = v + amount;
      lendBalance.yield += v.wadMul(accumRate - info.lastAccum);
      info.lastAccum = accumRate;
    }
    borr.total += amount;

    ILender(fromFund).approveBorrow(token, amount, address(toStrategy));
    IReinvestStrategy(toStrategy).investFrom(token, fromFund, amount);
    Sanity.require(IERC20(token).allowance(fromFund, toStrategy) == 0);

    // TODO get stats and update rate
  }

  function pullFrom(
    address token,
    address fromStrategy,
    address toFund,
    uint256 amount
  ) external returns (uint256) {
    // TODO onlyApprovedStrategy(strategy)
    // TODO onlyApprovedFund(fund)

    TokenBorrow storage borr = _borrowings[token][fromStrategy];
    uint96 accumRate = borr.accumRate;

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
      BorrowerStateInfo storage info = lend.borrowers[index];
      lendBalance.amount = v - amount;
      lendBalance.yield += v.wadMul(accumRate - info.lastAccum);
      info.lastAccum = accumRate;
    }

    if ((borr.total -= amount) == 0) {
      _borrowedTokens[fromStrategy].remove(token);
    }

    IReinvestStrategy(fromStrategy).approveDivest(token, toFund, amount);
    ILender(toFund).repayFrom(token, fromStrategy, amount);
    Sanity.require(IERC20(token).allowance(fromStrategy, toFund) == 0);

    return amount;
  }

  function pullYieldFrom(
    address token,
    address fromStrategy,
    address toFund,
    uint16 maxPct
  ) external returns (uint256) {}
  // func requestLiquidity
}
