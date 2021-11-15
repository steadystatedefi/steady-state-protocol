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

abstract contract WeightedPoolBase is IInsurerPoolCore, WeightedPoolTokenStorage, Delegator, ERC1363ReceiverBase {
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using Balances for Balances.RateAcc;

  address internal immutable _extension;

  event ExcessCoverageIncreased(uint256 coverageExcess);

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

  function charteredDemand() external pure override returns (bool) {
    return true;
  }

  function _beforeBalanceUpdate(address account)
    private
    returns (UserBalance memory b, Balances.RateAcc memory totals)
  {
    totals = _totalRate.sync(uint32(block.timestamp));
    b = _syncBalance(account, totals);
  }

  function _syncBalance(address account, Balances.RateAcc memory totals) private returns (UserBalance memory b) {
    b = _balances[account];
    if (b.balance > 0) {
      uint256 premiumDiff = totals.accum - b.premiumBase;
      if (premiumDiff > 0) {
        _premiums[account] += premiumDiff.rayMul(b.balance);
      }
    }
    b.premiumBase = totals.accum;
  }

  function _afterBalanceUpdate(
    uint256 newExcess,
    Balances.RateAcc memory totals,
    DemandedCoverage memory coverage
  ) private returns (Balances.RateAcc memory) {
    uint256 rate = coverage.premiumRate.rayMul(exchangeRate());
    // console.log('_afterBalanceUpdate0', coverage.premiumRate, rate, newExcess);

    rate = (rate * WadRayMath.RAY) / (newExcess + coverage.totalCovered + coverage.pendingCovered);

    // console.log('_afterBalanceUpdate1', rate, coverage.totalCovered, coverage.pendingCovered);
    if (totals.rate != rate) {
      _totalRate = totals.setRateAfterSync(rate);
    } else {
      require(totals.updatedAt == block.timestamp);
    }
    return totals;
  }

  function internalMintForCoverage(address account, uint256 coverageAmount) internal {
    (UserBalance memory b, Balances.RateAcc memory totals) = _beforeBalanceUpdate(account);

    uint256 excessCoverage = _excessCoverage;
    if (coverageAmount > 0 || excessCoverage > 0) {
      (uint256 newExcess, , AddCoverageParams memory p, PartialState memory part, Rounds.Batch memory bp) = super
        .internalAddCoverage(coverageAmount + excessCoverage, type(uint256).max);

      if (newExcess != excessCoverage) {
        _excessCoverage = newExcess;
        if (newExcess > excessCoverage) {
          emit ExcessCoverageIncreased(newExcess);
        }
      }

      totals = _afterBalanceUpdate(newExcess, totals, super.internalGetPremiumTotals(part, bp, p.premium));
    }

    emit Transfer(address(0), account, coverageAmount);

    uint256 amount = coverageAmount.rayDiv(exchangeRate()) + b.balance;
    require(amount == (b.balance = uint128(amount)));
    _balances[account] = b;
  }

  function pushCoverageExcess() public {
    uint256 excessCoverage = _excessCoverage;
    if (excessCoverage == 0) {
      return;
    }

    Balances.RateAcc memory totals = _totalRate.sync(uint32(block.timestamp));

    (uint256 newExcess, , AddCoverageParams memory p, PartialState memory part, Rounds.Batch memory bp) = super
      .internalAddCoverage(excessCoverage, type(uint256).max);

    if (newExcess != excessCoverage) {
      _excessCoverage = newExcess;
      _afterBalanceUpdate(newExcess, totals, super.internalGetPremiumTotals(part, bp, p.premium));
    }
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
      totals = _afterBalanceUpdate(_excessCoverage -= coverageAmount, totals, super.internalGetPremiumTotals());
    }
    emit Transfer(account, address(0), coverageAmount);
    _balances[account] = b;

    transferCollateral(account, coverageAmount);

    return coverageAmount;
  }

  function balanceOf(address account) external view override returns (uint256) {
    return uint256(_balances[account].balance).rayMul(exchangeRate());
  }

  function balancesOf(address account)
    public
    view
    returns (
      uint256 coverage,
      uint256 scaled,
      uint256 premium
    )
  {
    scaled = _balances[account].balance;
    coverage = scaled.rayMul(exchangeRate());
    (, premium) = interestRate(account);
  }

  function scaledBalanceOf(address account) external view override returns (uint256) {
    return _balances[account].balance;
  }

  function totalSupply() public view override returns (uint256) {
    DemandedCoverage memory coverage = super.internalGetPremiumTotals();
    return coverage.totalCovered + coverage.pendingCovered;
  }

  function interestRate(address account) public view override returns (uint256 rate, uint256 accumulated) {
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

  function exchangeRate() public view override returns (uint256) {
    return WadRayMath.RAY - _inverseExchangeRate;
  }

  function statusOf(address account) external view returns (InsuredStatus status) {
    if ((status = internalGetStatus(account)) == InsuredStatus.Unknown && internalIsInvestor(account)) {
      status = InsuredStatus.NotApplicable;
    }
    return status;
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

  function transferBalance(
    address sender,
    address recipient,
    uint256 amount
  ) internal override {
    (UserBalance memory b, Balances.RateAcc memory totals) = _beforeBalanceUpdate(sender);

    b.balance = uint128(b.balance - amount);
    _balances[sender] = b;

    b = _syncBalance(recipient, totals);
    require((b.balance = uint128(amount += b.balance)) == amount);
    _balances[recipient] = b;
  }
}
