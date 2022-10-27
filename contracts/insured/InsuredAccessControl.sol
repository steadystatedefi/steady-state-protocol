// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/introspection/ERC165Checker.sol';
import '../tools/math/PercentageMath.sol';
import '../tools/math/WadRayMath.sol';
import '../governance/interfaces/IInsuredGovernor.sol';
import '../governance/GovernedHelper.sol';
import '../pricing/PricingHelper.sol';

abstract contract InsuredAccessControl is GovernedHelper, PricingHelper {
  using PercentageMath for uint256;

  address private _governor;
  bool private _governorIsContract;

  constructor(IAccessController acl, address collateral_) GovernedHelper(acl, collateral_) {}

  function remoteAcl() internal view override(AccessHelper, PricingHelper) returns (IAccessController pricer) {
    return AccessHelper.remoteAcl();
  }

  function internalSetTypedGovernor(IInsuredGovernor addr) internal {
    _governorIsContract = true;
    _setGovernor(address(addr));
  }

  function internalSetGovernor(address addr) internal virtual {
    // will also return false for EOA
    _governorIsContract = ERC165Checker.supportsInterface(addr, type(IInsuredGovernor).interfaceId);
    _setGovernor(addr);
  }

  function governorContract() internal view virtual returns (IInsuredGovernor) {
    return IInsuredGovernor(_governorIsContract ? governorAccount() : address(0));
  }

  function internalQueryGovernorAcl(
    address g,
    address account,
    uint256 flags
  ) internal view override returns (uint256 mask, uint256 overrides) {
    return super.internalQueryGovernorAcl(_governorIsContract ? g : address(0), account, flags);
  }

  event GovernorUpdated(address);

  function _setGovernor(address addr) internal {
    emit GovernorUpdated(_governor = addr);
  }

  function governorAccount() internal view override returns (address) {
    return _governor;
  }
}
