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
        amount = value.rayDiv(exchangeRate(super.internalGetPremiumTotals(part, p.premium)));
      }
    }
    _mint(account, amount, value);
  }

  /// @dev Update the exchange rate and excess coverage when a policy cancellation occurs
  function updateCoverageOnCancel(uint256 paidoutCoverage, uint256 excess) public {
    require(msg.sender == address(this));

    uint256 excessCoverage = _excessCoverage + excess;
    if (paidoutCoverage > 0) {
      _lostCoverage += paidoutCoverage;
    }

    if (excess > 0) {
      _excessCoverage = excessCoverage;
      emit ExcessCoverageIncreased(excessCoverage);
    }

    internalPostCoverageCancel();
  }

  function internalPostCoverageCancel() internal virtual {
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
    _burn(account, burntAmount = value.rayDiv(exchangeRate(coverage)), value);
  }

  function totalSupplyValue(DemandedCoverage memory coverage) private view returns (uint256 v) {
    v = _excessCoverage;
    v += coverage.totalPremium - _burntPremium;
    v += (coverage.totalCovered + coverage.pendingCovered) - _lostCoverage;
  }

  function totalSupplyValue() public view returns (uint256) {
    return totalSupplyValue(super.internalGetPremiumTotals());
  }

  function exchangeRate(DemandedCoverage memory coverage) private view returns (uint256 v) {
    if ((v = totalSupply()) > 0) {
      return totalSupplyValue(coverage) / v;
    }
  }

  function exchangeRate() public view override returns (uint256 v) {
    return exchangeRate(super.internalGetPremiumTotals());
  }

  function internalBurnPremium(address account, uint256 value) internal returns (uint256 burntAmount) {
    DemandedCoverage memory coverage = super.internalGetPremiumTotals();
    uint256 burntPremium = _burntPremium + value;
    require(coverage.totalPremium >= burntPremium);

    burntAmount = _burnValue(account, value, coverage);
    _burntPremium += burntPremium;
  }

  function internalBurnCoverage(address account, uint256 value) internal returns (uint256 burntAmount) {
    DemandedCoverage memory coverage = super.internalGetPremiumTotals();
    // uint256 lostCoverage = _lostCoverage + value;
    uint256 drawndownValue = _drawndownValue + value;

    uint256 limit = (coverage.totalCovered + coverage.pendingCovered - _lostCoverage).percentMul(_params.maxDrawdown);
    require(limit >= drawndownValue);

    burntAmount = _burnValue(account, value, coverage);
    _drawndownValue += drawndownValue;
  }

  function balanceOf(address account) public view override returns (uint256) {
    return scaledBalanceOf(account).rayMul(exchangeRate());
  }

  function scaledBalanceOf(address account) public view override returns (uint256) {
    return _balances[account].balance;
  }

  /// @return status The status of the account, NotApplicable if unknown about this address or account is an investor
  function statusOf(address account) external view returns (InsuredStatus status) {
    if ((status = internalGetStatus(account)) == InsuredStatus.Unknown && internalIsInvestor(account)) {
      status = InsuredStatus.NotApplicable;
    }
    return status;
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

  // TODO should not be required
  function withdrawable(address account) public view override returns (uint256 amount) {}

  function withdrawAll() external override returns (uint256) {}

  function interestOf(address account) external view override returns (uint256 rate, uint256 accumulated) {}

  // function getUnadjusted()
  //   external
  //   view
  //   returns (
  //     uint256 total,
  //     uint256 pendingCovered,
  //     uint256 pendingDemand
  //   )
  // {
  //   return internalGetUnadjustedUnits();
  // }

  // function applyAdjustments() external {
  //   internalApplyAdjustmentsToTotals();
  // }
}
