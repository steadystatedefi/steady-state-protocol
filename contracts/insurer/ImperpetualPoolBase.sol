// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/PercentageMath.sol';
import '../tools/upgradeability/Delegator.sol';
import '../tools/tokens/ERC1363ReceiverBase.sol';
import '../libraries/Balances.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IInsuredPool.sol';
import './ImperpetualPoolStorage.sol';
import './ImperpetualPoolExtension.sol';
import './WeightedPoolBase.sol';

/// @title Index Pool Base with Perpetual Index Pool Tokens
/// @notice Handles adding coverage by users.
abstract contract ImperpetualPoolBase is ImperpetualPoolStorage, WeightedPoolBase {
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using Balances for Balances.RateAcc;

  constructor(uint256 unitSize, ImperpetualPoolExtension extension) WeightedRoundsBase(unitSize) WeightedPoolBase(unitSize, extension) {}

  /// @dev Updates the user's balance based upon the current exchange rate of $CC to $Pool_Coverage
  /// @dev Update the new amount of excess coverage
  function _mintForCoverage(address account, uint256 value) private {
    uint256 excessCoverage = _excessCoverage;
    uint256 amount;

    if (value > 0 || excessCoverage > 0) {
      (uint256 newExcess, , AddCoverageParams memory p, PartialState memory part) = super.internalAddCoverage(
        value + excessCoverage,
        type(uint256).max
      );
      if (newExcess != excessCoverage) {
        _excessCoverage = newExcess;
        if (newExcess > excessCoverage) {
          emit ExcessCoverageIncreased(newExcess);
        }
      }
      amount = value.rayDiv(exchangeRate(super.internalGetPremiumTotals(part, p.premium), value));
    }
    _mint(account, amount, value);
  }

  function internalSubrogate(uint256 value) private {
    if (value > 0) {
      emit ExcessCoverageIncreased(_excessCoverage += value);
      internalOnCoverageRecovered();
    }
  }

  function updateCoverageOnCancel(
    address insured,
    uint256 payoutValue,
    uint256 excessCoverage
  ) public returns (uint256) {
    require(msg.sender == address(this));

    uint256 givenValue = _insuredBalances[insured];

    if (givenValue != payoutValue) {
      if (givenValue > payoutValue) {
        // take back the given coverage
        transferCollateralFrom(insured, address(this), givenValue - payoutValue);
      } else {
        uint128 drawndownSupply = _drawdownSupply;

        if (drawndownSupply > 0) {
          uint256 underpay = payoutValue - givenValue;
          if (drawndownSupply > underpay) {
            drawndownSupply = uint128(drawndownSupply - underpay);
          } else {
            (underpay, drawndownSupply) = (drawndownSupply, 0);
            payoutValue = givenValue + underpay;
          }
          _drawdownSupply = drawndownSupply;

          transferCollateral(insured, underpay);
        }
      }
    }

    if (excessCoverage > 0) {
      emit ExcessCoverageIncreased(_excessCoverage += excessCoverage);
      internalOnCoverageRecovered();
    }

    return payoutValue;
  }

  function updateCoverageOnReconcile(
    address insured,
    uint256 receivedCoverage,
    uint256 totalCovered
  ) public returns (uint256) {
    require(msg.sender == address(this));

    uint256 expectedAmount = totalCovered.percentMul(PercentageMath.ONE - _params.maxDrawdown); // TODO use an inverse value in the config
    uint256 actualAmount = _insuredBalances[insured];

    if (actualAmount < expectedAmount) {
      uint256 v = expectedAmount - actualAmount;
      if (v < receivedCoverage) {
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

  function internalOnCoverageRecovered() internal virtual {
    pushCoverageExcess();
  }

  /// @dev Attempt to take the excess coverage and fill batches
  /// @dev Occurs when there is excess and a new batch is ready (more demand added)
  function pushCoverageExcess() public override {
    uint256 excessCoverage = _excessCoverage;
    if (excessCoverage > 0) {
      (_excessCoverage, , , ) = super.internalAddCoverage(excessCoverage, type(uint256).max);
    }
  }

  function _burnValue(
    address account,
    uint256 value,
    DemandedCoverage memory coverage
  ) private returns (uint256 burntAmount) {
    _burn(account, burntAmount = value.rayDiv(exchangeRate(coverage, 0)), value);
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

  function internalBurnPremium(address account, uint256 value) internal returns (uint256 burntAmount) {
    DemandedCoverage memory coverage = super.internalGetPremiumTotals();

    require(coverage.totalPremium >= _burntPremium + value);
    burntAmount = _burnValue(account, value, coverage);
    _burntPremium += to128(value);
  }

  function internalBurnCoverage(
    address account,
    uint256 value,
    address recepient
  ) internal returns (uint256 burntAmount) {
    uint256 usableExcess = _excessCoverage;
    if (usableExcess < value) {
      _drawdownSupply = uint128(_drawdownSupply + usableExcess - value);
    } else if (usableExcess > value) {
      usableExcess = value;
    }

    DemandedCoverage memory coverage = super.internalGetPremiumTotals();
    burntAmount = _burnValue(account, value, coverage);

    if (usableExcess > 0) {
      _excessCoverage -= usableExcess;
    }

    transferCollateral(recepient, value);
  }

  function balanceOf(address account) public view override returns (uint256) {
    return _balances[account].balance;
  }

  /// @return status The status of the account, NotApplicable if unknown about this address or account is an investor
  function statusOf(address account) external view returns (InsuredStatus status) {
    return internalStatusOf(account);
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
}
