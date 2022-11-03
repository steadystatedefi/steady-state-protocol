// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/PercentageMath.sol';
import '../interfaces/IPremiumDistributor.sol';
import './WeightedPoolConfig.sol';

/// @dev A storage template for the basic insurer operations.
abstract contract WeightedPoolStorage is WeightedPoolConfig {
  using PercentageMath for uint256;
  using WadRayMath for uint256;

  struct UserBalance {
    uint128 balance; // scaled
    uint128 extra; // NB! this field is used differenly for perpetual and imperpetual pools
  }
  mapping(address => UserBalance) internal _balances; // [investor]

  IPremiumDistributor internal _premiumDistributor;

  /// @dev Amount of coverage provided to this pool but is not satisfying demand
  uint192 internal _excessCoverage;
  bool internal _paused;

  event ExcessCoverageUpdated(uint256 coverageExcess);

  function internalSetExcess(uint256 excess) internal {
    Arithmetic.require((_excessCoverage = uint192(excess)) == excess);
    emit ExcessCoverageUpdated(excess);
  }

  modifier onlyUnpaused() {
    Access.require(!_paused);
    _;
  }

  ///@return true when the `account` has a non-zero balance or premium
  function internalIsInvestor(address account) internal view override returns (bool) {
    UserBalance memory b = _balances[account];
    return b.extra != 0 || b.balance != 0;
  }

  event PremiumDistributorUpdated(address);

  function internalSetPremiumDistributor(address premiumDistributor_) internal virtual {
    _premiumDistributor = IPremiumDistributor(premiumDistributor_);
    emit PremiumDistributorUpdated(premiumDistributor_);
  }

  function internalAfterJoinOrLeave(address insured, MemberStatus status) internal override {
    if (address(_premiumDistributor) != address(0)) {
      _premiumDistributor.registerPremiumSource(insured, status == MemberStatus.Accepted);
    }
    super.internalAfterJoinOrLeave(insured, status);
  }

  /// @dev a storage reserve for further upgrades
  uint256[16] private _gap;
}
