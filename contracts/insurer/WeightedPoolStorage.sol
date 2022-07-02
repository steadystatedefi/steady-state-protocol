// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/introspection/ERC165Checker.sol';
import '../tools/math/PercentageMath.sol';
import '../interfaces/IInsurerGovernor.sol';
import '../interfaces/IPremiumDistributor.sol';
import '../insurance/Collateralized.sol';
import './WeightedPoolConfig.sol';

// Contains all variables for both base and extension contract. Allows for upgrades without corruption

/// @dev
/// @dev WARNING! This contract MUST NOT be extended with new fields after deployment
/// @dev
abstract contract WeightedPoolStorage is WeightedPoolConfig, Collateralized {
  using PercentageMath for uint256;
  using WadRayMath for uint256;

  struct UserBalance {
    uint128 balance; // scaled
    uint128 extra; // NB! this field is used differenly for perpetual and imperpetual pools
  }
  mapping(address => UserBalance) internal _balances; // [investor]

  address private _governor;
  bool private _governorIsContract;

  IPremiumDistributor internal _premiumDistributor;

  /// @dev Amount of coverage provided to the pool that is not satisfying demand
  uint256 internal _excessCoverage;

  function internalIsInvestor(address account) internal view virtual returns (bool) {
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

  function _setGovernor(address addr) private {
    emit GovernorUpdated(_governor = addr);
  }

  function internalSetTypedGovernor(IInsurerGovernor addr) internal {
    _governorIsContract = true;
    _setGovernor(address(addr));
  }

  function governorAccount() internal view returns (address) {
    return _governor;
  }

  event GovernorUpdated(address);

  function internalSetGovernor(address addr) internal virtual {
    // will also return false for EOA
    _governorIsContract = ERC165Checker.supportsInterface(addr, type(IInsurerGovernor).interfaceId);
    _setGovernor(addr);
  }

  function governorContract() internal view virtual returns (IInsurerGovernor) {
    return IInsurerGovernor(_governorIsContract ? _governor : address(0));
  }

  event PremiumDistributorUpdated(address);

  function internalSetPremiumDistributor(address premiumDistributor_) internal virtual {
    _premiumDistributor = IPremiumDistributor(premiumDistributor_);
    emit PremiumDistributorUpdated(premiumDistributor_);
  }
}
