// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/PercentageMath.sol';
import '../insurance/InsurancePoolBase.sol';
import './WeightedPoolConfig.sol';

// Contains all variables for both base and extension contract. Allows for upgrades without corruption

/// @dev
/// @dev WARNING! This contract MUST NOT be extended with new fields after deployment
/// @dev
abstract contract WeightedPoolStorage is WeightedPoolConfig, InsurancePoolBase {
  using PercentageMath for uint256;
  using WadRayMath for uint256;

  struct UserBalance {
    uint128 balance; // scaled
    uint128 extra; // NB! this field is used differenly for perpetual and imperpetual pools
  }
  mapping(address => UserBalance) internal _balances; // [investor]

  address internal _joinHandler;

  /// @dev Amount of coverage provided to the pool that is not satisfying demand
  uint256 internal _excessCoverage;

  function internalIsInvestor(address account) internal view virtual returns (bool) {
    UserBalance memory b = _balances[account];
    return b.extra != 0 || b.balance != 0;
  }
}
