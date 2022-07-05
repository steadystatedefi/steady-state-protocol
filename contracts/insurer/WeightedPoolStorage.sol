// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/PercentageMath.sol';
import '../interfaces/IPremiumDistributor.sol';
import './WeightedPoolConfig.sol';
import './InsurerJoinBase.sol';

// Contains all variables for both base and extension contract. Allows for upgrades without corruption

/// @dev
/// @dev WARNING! This contract MUST NOT be extended with new fields after deployment
/// @dev
abstract contract WeightedPoolStorage is WeightedPoolConfig, InsurerJoinBase {
  using PercentageMath for uint256;
  using WadRayMath for uint256;

  struct UserBalance {
    uint128 balance; // scaled
    uint128 extra; // NB! this field is used differenly for perpetual and imperpetual pools
  }
  mapping(address => UserBalance) internal _balances; // [investor]

  IPremiumDistributor internal _premiumDistributor;

  /// @dev Amount of coverage provided to the pool that is not satisfying demand
  uint256 internal _excessCoverage;

  ///@dev Return if an account has a balance or premium earned
  function internalIsInvestor(address account) internal view override returns (bool) {
    UserBalance memory b = _balances[account];
    return b.extra != 0 || b.balance != 0;
  }

  /// @return status The status of the account, NotApplicable if unknown about this address or account is an investor
  function internalStatusOf(address account) internal view returns (InsuredStatus status) {
    if ((status = internalGetStatus(account)) == InsuredStatus.Unknown && internalIsInvestor(account)) {
      status = InsuredStatus.NotApplicable;
    }
    return status;
  }

  event PremiumDistributorUpdated(address);

  function internalSetPremiumDistributor(address premiumDistributor_) internal virtual {
    _premiumDistributor = IPremiumDistributor(premiumDistributor_);
    emit PremiumDistributorUpdated(premiumDistributor_);
  }

  /// @dev Prepare for an insured pool to join by setting the parameters
  function internalPrepareJoin(address insured) internal override {
    InsuredParams memory insuredParams = IInsuredPool(insured).insuredParams();

    uint256 maxShare = uint256(insuredParams.riskWeightPct).percentDiv(_params.riskWeightTarget);
    uint256 v;
    if (maxShare >= (v = _params.maxInsuredShare)) {
      maxShare = v;
    } else if (maxShare < (v = _params.minInsuredShare)) {
      maxShare = v;
    }

    super.internalSetInsuredParams(insured, Rounds.InsuredParams({minUnits: insuredParams.minUnitsPerInsurer, maxShare: uint16(maxShare)}));
  }

  function internalInitiateJoin(address insured) internal override returns (InsuredStatus) {
    IJoinHandler jh = governorContract();
    return address(jh) == address(0) ? InsuredStatus.Joining : jh.handleJoinRequest(insured);
  }

  function internalGetStatus(address account) internal view override(InsurerJoinBase, WeightedPoolConfig) returns (InsuredStatus) {
    return WeightedPoolConfig.internalGetStatus(account);
  }

  function internalSetStatus(address account, InsuredStatus status) internal override {
    return super.internalSetInsuredStatus(account, status);
  }

  function internalAfterJoinOrLeave(address insured, InsuredStatus status) internal override {
    if (address(_premiumDistributor) != address(0)) {
      _premiumDistributor.registerPremiumSource(insured, status == InsuredStatus.Accepted);
    }
  }
}
