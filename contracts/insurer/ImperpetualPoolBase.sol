// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './ImperpetualPoolStorage.sol';
import './ImperpetualPoolExtension.sol';
import './WeightedPoolBase.sol';

/// @title Index Pool Base with Perpetual Index Pool Tokens
/// @notice Handles adding coverage by users.
abstract contract ImperpetualPoolBase is ImperpetualPoolStorage {
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using Balances for Balances.RateAcc;

  constructor(
    ImperpetualPoolExtension extension,
    JoinablePoolExtension joinExtension
  ) WeightedPoolBase(extension, joinExtension) {}

  function _addCoverage(uint256 value)
    private
    returns (
      bool done,
      AddCoverageParams memory params,
      PartialState memory part
    )
  {
    uint256 excessCoverage = _excessCoverage;
    if (excessCoverage > 0 || value > 0) {
      uint256 newExcess;
      (newExcess, , params, part) = super.internalAddCoverage(value + excessCoverage, type(uint256).max);
      if (newExcess != excessCoverage) {
        _excessCoverage = newExcess;
        emit ExcessCoverageIncreased(newExcess);
      }
      if (params.unitsCovered > 0) {
        // TODO increase MCD in the premium pool
      }
      done = true;
    }
  }

  /// @dev Updates the user's balance based upon the current exchange rate of $CC to $Pool_Coverage
  /// @dev Update the new amount of excess coverage
  function _mintForCoverage(address account, uint256 value) private {
    (bool done, AddCoverageParams memory params, PartialState memory part) = _addCoverage(value);
    // TODO test adding coverage to an empty pool
    _mint(account, done ? value.rayDiv(exchangeRate(super.internalGetPremiumTotals(part, params.premium), value)) : value, value);
  }

  function internalSubrogate(address donor, uint256 value) internal override {
    transferCollateralFrom(donor, address(this), value);
    emit ExcessCoverageIncreased(_excessCoverage += value);
    internalOnCoverageRecovered();
  }

  function updateCoverageOnCancel(
    address insured,
    uint256 payoutValue,
    uint256 advanceValue,
    uint256 recoveredValue,
    uint256 premiumDebt
  ) external onlySelf returns (uint256) {
    uint256 givenOutValue = _insuredBalances[insured];
    require(givenOutValue <= advanceValue);

    delete _insuredBalances[insured];
    uint256 givenValue = givenOutValue + premiumDebt;

    if (givenValue != payoutValue) {
      if (givenValue > payoutValue) {
        recoveredValue += advanceValue - givenValue;

        // try to take back the given coverage
        uint256 recovered = transferAvailableCollateralFrom(insured, address(this), givenValue - payoutValue);

        // only the outstanding premium debt should be deducted, an outstanding coverage debt is managed as reduction of coverage itself
        if (premiumDebt > recovered) {
          _decrementTotalValue(premiumDebt - recovered);
        }

        recoveredValue += recovered;
      } else {
        recoveredValue += advanceValue;

        uint128 drawndownSupply = _drawdownSupply;

        if (drawndownSupply > 0) {
          uint256 underpay = payoutValue - givenValue;

          if (drawndownSupply >= underpay) {
            drawndownSupply = uint128(drawndownSupply - underpay);
          } else {
            // TODO use excess also??

            payoutValue -= underpay - drawndownSupply;
            (underpay, drawndownSupply) = (drawndownSupply, 0);
          }
          _drawdownSupply = drawndownSupply;

          transferCollateral(insured, underpay);
        }

        recoveredValue -= payoutValue;
      }
    }

    if (recoveredValue > 0) {
      emit ExcessCoverageIncreased(_excessCoverage += recoveredValue);
      internalOnCoverageRecovered();
    }

    return payoutValue;
  }

  function updateCoverageOnReconcile(
    address insured,
    uint256 receivedCoverage,
    uint256 totalCovered
  ) external onlySelf returns (uint256) {
    // TODO remove
    uint256 expectedAmount = totalCovered.percentMul(_params.maxDrawdownInverse);
    uint256 actualAmount = _insuredBalances[insured];

    if (actualAmount < expectedAmount) {
      uint256 v = expectedAmount - actualAmount;
      if (v < receivedCoverage) {
        // TODO update the premium fund
        _drawdownSupply += to128(receivedCoverage - v);
        receivedCoverage = v;
      }

      _insuredBalances[insured] = actualAmount + receivedCoverage;
      transferCollateral(insured, receivedCoverage);
    } else {
      receivedCoverage = 0;
    }

    return receivedCoverage;
  }

  function _toInt128(uint256 v) private pure returns (int128) {
    require(v <= type(uint128).max);
    return int128(uint128(v));
  }

  function _decrementTotalValue(uint256 valueLoss) private {
    _valueAdjustment -= _toInt128(valueLoss);
  }

  function _incrementTotalValue(uint256 valueGain) private {
    _valueAdjustment += _toInt128(valueGain);
  }

  function internalOnCoverageRecovered() internal virtual {
    pushCoverageExcess();
  }

  /// @dev Attempt to take the excess coverage and fill batches
  /// @dev Occurs when there is excess and a new batch is ready (more demand added)
  function pushCoverageExcess() public override {
    _addCoverage(0);
  }

  function totalSupplyValue(DemandedCoverage memory coverage, uint256 added) private view returns (uint256 v) {
    v = (coverage.totalCovered + coverage.pendingCovered) - added;
    {
      int256 va = _valueAdjustment;
      if (va >= 0) {
        v += uint256(va);
      } else {
        v -= uint256(-va);
      }
    }
    v += coverage.totalPremium - _burntPremium;
    v += _excessCoverage;
  }

  function totalSupplyValue() public view returns (uint256) {
    return totalSupplyValue(super.internalGetPremiumTotals(), 0);
  }

  function exchangeRate(DemandedCoverage memory coverage, uint256 added) private view returns (uint256 v) {
    if ((v = totalSupply()) > 0) {
      v = totalSupplyValue(coverage, added).rayDiv(v);
    } else {
      v = WadRayMath.RAY;
    }
  }

  function exchangeRate() public view override returns (uint256 v) {
    return exchangeRate(super.internalGetPremiumTotals(), 0);
  }

  function balanceOf(address account) public view override returns (uint256) {
    return _balances[account].balance;
  }

  ///@notice Transfer a balance to a recipient, syncs the balances before performing the transfer
  ///@param sender  The sender
  ///@param recipient The receiver
  ///@param amount  Amount to transfer
  function transferBalance(
    address sender,
    address recipient,
    uint256 amount
  ) internal override {
    _balances[sender].balance = uint128(_balances[sender].balance - amount);
    _balances[recipient].balance += uint128(amount);
  }

  ///
  function internalReceiveTransfer(
    address operator,
    address account,
    uint256 amount,
    bytes calldata data
  ) internal override onlyCollateralCurrency {
    require(data.length == 0);
    require(operator != address(this) && account != address(this) && internalGetStatus(account) == InsuredStatus.Unknown);

    _mintForCoverage(account, amount);
  }

  function _burnValue(
    address account,
    uint256 value,
    DemandedCoverage memory coverage
  ) private returns (uint256 burntAmount) {
    _burn(account, burntAmount = value.rayDiv(exchangeRate(coverage, 0)), value);
  }

  function _burnPremium(
    address account,
    uint256 value,
    DemandedCoverage memory coverage
  ) internal returns (uint256 burntAmount) {
    require(coverage.totalPremium >= _burntPremium + value);
    burntAmount = _burnValue(account, value, coverage);
    _burntPremium += to128(value);
  }

  function _burnCoverage(
    address account,
    uint256 value,
    address recepient,
    DemandedCoverage memory coverage
  ) internal returns (uint256 burntAmount) {
    uint256 usableExcess = _excessCoverage;
    if (usableExcess < value) {
      // TODO fix oveflow
      _drawdownSupply = uint128(_drawdownSupply + usableExcess - value);
    } else if (usableExcess > value) {
      usableExcess = value;
    }

    burntAmount = _burnValue(account, value, coverage);

    if (usableExcess > 0) {
      _excessCoverage -= usableExcess;
    }

    transferCollateral(recepient, value);
  }

  function internalBurnPremium(
    address account,
    uint256 value,
    address drawdownRecepient
  ) internal override {
    DemandedCoverage memory coverage = super.internalGetPremiumTotals();
    drawdownRecepient != address(0) ? _burnCoverage(account, value, drawdownRecepient, coverage) : _burnPremium(account, value, coverage);
  }

  function internalCollectDrawdownPremium() internal override returns (uint256) {
    // TODO
  }
}
