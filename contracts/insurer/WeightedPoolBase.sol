// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/ERC1363ReceiverBase.sol';
import '../tools/math/PercentageMath.sol';
import '../tools/upgradeability/Delegator.sol';
import '../libraries/Balances.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IInsuredPool.sol';
import './WeightedPoolStorage.sol';
import './WeightedPoolExtension.sol';

abstract contract WeightedPoolBase is IInsurerPoolCore, WeightedPoolStorage, Delegator, ERC1363ReceiverBase {
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using Balances for Balances.RateAcc;

  address internal immutable _extension;

  constructor(uint256 unitSize, WeightedPoolExtension extension) WeightedRoundsBase(unitSize) {
    require(extension.coverageUnitSize() == unitSize);
    _extension = address(extension);
  }

  // solhint-disable-next-line payable-fallback
  fallback() external {
    // all IInsurerPoolDemand etc functions should be delegated to the extension
    _delegate(_extension);
  }

  function internalSetPoolParams(WeightedPoolParams memory params) internal {
    require(params.minUnitsPerRound > 0);
    require(params.maxUnitsPerRound >= params.minUnitsPerRound);

    require(params.maxAdvanceUnits >= params.minAdvanceUnits);
    require(params.minAdvanceUnits >= params.maxUnitsPerRound);

    require(params.minInsuredShare > 0);
    require(params.maxInsuredShare > params.minInsuredShare);
    require(params.maxInsuredShare <= PercentageMath.ONE);

    require(params.riskWeightTarget > 0);
    require(params.riskWeightTarget < PercentageMath.ONE);
    _params = params;
  }

  function charteredDemand() public pure override(IInsurerPoolCore, WeightedPoolStorage) returns (bool) {
    return true;
  }

  function _beforeBalanceUpdate(address account)
    private
    returns (UserBalance memory b, Balances.RateAcc memory totals)
  {
    totals = _totalRate.sync(uint32(block.timestamp));
    b = _balances[account];

    if (b.balance > 0) {
      uint256 premiumDiff = totals.accum - b.premiumBase;
      if (premiumDiff > 0) {
        _premiums[account] += premiumDiff.rayMul(b.balance);
      }
    }
  }

  function _afterBalanceUpdate(
    uint256 newExcess,
    Balances.RateAcc memory totals,
    DemandedCoverage memory coverage
  ) private returns (Balances.RateAcc memory) {
    uint256 rate = coverage.premiumRate.rayMul(exchangeRate());
    console.log('_afterBalanceUpdate0', coverage.premiumRate, rate, newExcess);

    rate = (rate * WadRayMath.RAY) / (newExcess + coverage.totalCovered + coverage.pendingCovered);

    console.log('_afterBalanceUpdate1', rate, coverage.totalCovered, coverage.pendingCovered);
    if (totals.rate != rate) {
      _totalRate = totals.setRate(uint32(block.timestamp), rate);
    }
    return totals;
  }

  function internalMintForCoverage(address account, uint256 coverageAmount) internal {
    OpenBalance memory openBalance = _openBalance;

    uint256 buyOff;
    if (openBalance.buyOffShare > 0) {
      buyOff = coverageAmount.percentMul(openBalance.buyOffShare);
      if (buyOff >= openBalance.buyOffCoverage) {
        (buyOff, openBalance.buyOffCoverage) = (openBalance.buyOffCoverage, 0);
      } else {
        openBalance.buyOffCoverage -= uint112(buyOff);
      }
      coverageAmount -= buyOff;
    }

    (UserBalance memory b, Balances.RateAcc memory totals) = _beforeBalanceUpdate(account);

    if (coverageAmount > 0 || openBalance.excessCoverage > 0) {
      (uint256 newExcess, , AddCoverageParams memory p, PartialState memory part, Rounds.Batch memory bp) = super
        .internalAddCoverage(coverageAmount + openBalance.excessCoverage, type(uint256).max);

      if (newExcess != openBalance.excessCoverage) {
        require(newExcess == (openBalance.excessCoverage = uint128(newExcess)));
        buyOff = 1; // forces update of _openBalance
      }

      totals = _afterBalanceUpdate(newExcess, totals, super.internalGetPremiumTotals(part, bp, p.premium));
    }

    if (buyOff != 0) {
      _openBalance = openBalance;
    }

    uint256 amount = coverageAmount.rayDiv(exchangeRate()) + b.balance;
    require(amount == (b.balance = uint128(amount)));
    b.premiumBase = totals.accum;
    _balances[account] = b;
  }

  function internalBurn(address account, uint256 amount) internal returns (uint256 coverageAmount) {
    (UserBalance memory b, Balances.RateAcc memory totals) = _beforeBalanceUpdate(account);
    if (amount == type(uint256).max) {
      (amount, b.balance) = (b.balance, 0);
    } else {
      b.balance = uint128(b.balance - amount);
    }

    if (amount > 0) {
      coverageAmount = amount.rayMul(exchangeRate());
      totals = _afterBalanceUpdate(
        _openBalance.excessCoverage = uint128(_openBalance.excessCoverage - coverageAmount),
        totals,
        super.internalGetPremiumTotals()
      );
    }

    b.premiumBase = totals.accum;
    _balances[account] = b;
    return coverageAmount;
  }

  function balanceOf(address account) external view override returns (uint256) {
    return uint256(_balances[account].balance).rayMul(exchangeRate());
  }

  function scaledBalanceOf(address account) external view returns (uint256) {
    return _balances[account].balance;
  }

  function totalSupply() external view override returns (uint256) {
    DemandedCoverage memory coverage = super.internalGetPremiumTotals();
    return coverage.totalCovered + coverage.pendingCovered;
  }

  function interestRate(address account) external view override returns (uint256 rate, uint256 accumulated) {
    Balances.RateAcc memory totals = _totalRate.sync(uint32(block.timestamp));
    UserBalance memory b = _balances[account];

    accumulated = _premiums[account];

    if (b.balance > 0) {
      uint256 premiumDiff = totals.accum - b.premiumBase;
      if (premiumDiff > 0) {
        accumulated += uint256(b.balance).rayMul(premiumDiff);
      }
      return (uint256(b.balance).rayMul(totals.rate), accumulated);
    }

    return (0, accumulated);
  }

  function exchangeRate() public pure override returns (uint256) {
    return WadRayMath.RAY;
  }

  function statusOf(address account) external view returns (InsuredStatus) {
    return internalGetStatus(account);
  }

  /// @dev ERC1363-like receiver, invoked by the collateral fund for transfers/investments from user.
  /// mints $IC tokens when $CC is received from a user
  function internalReceiveTransfer(
    address operator,
    address,
    uint256 value,
    bytes calldata data
  ) internal override onlyCollateralFund {
    if (internalIsInvestor(operator)) {
      if (value == 0) return;
      internalHandleInvestment(operator, value, data);
    } else {
      InsuredStatus status = internalGetStatus(operator);
      if (status != InsuredStatus.Unknown) {
        // TODO return of funds from insured
        Errors.notImplemented();
        return;
      }
    }
    internalHandleInvestment(operator, value, data);
  }

  function internalHandleInvestment(
    address investor,
    uint256 amount,
    bytes memory data
  ) internal virtual {
    if (data.length > 0) {
      abi.decode(data, ());
    }
    internalMintForCoverage(investor, amount);
  }
}
