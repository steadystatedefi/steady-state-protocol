// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/introspection/ERC165Checker.sol';
import '../tools/math/PercentageMath.sol';
import '../interfaces/IInsurerGovernor.sol';
import '../governance/GovernedHelper.sol';
import './InsurerJoinBase.sol';

abstract contract WeightedPoolAccessControl is GovernedHelper, InsurerJoinBase {
  using PercentageMath for uint256;

  address private _governor;
  bool private _governorIsContract;

  function _onlyActiveInsured(address insurer) internal view {
    require(internalGetStatus(insurer) == InsuredStatus.Accepted);
  }

  function _onlyInsured(address insurer) private view {
    require(internalGetStatus(insurer) > InsuredStatus.Unknown);
  }

  modifier onlyActiveInsured() {
    _onlyActiveInsured(msg.sender);
    _;
  }

  modifier onlyInsured() {
    _onlyInsured(msg.sender);
    _;
  }

  function internalSetTypedGovernor(IInsurerGovernor addr) internal {
    _governorIsContract = true;
    _setGovernor(address(addr));
  }

  function internalSetGovernor(address addr) internal virtual {
    // will also return false for EOA
    _governorIsContract = ERC165Checker.supportsInterface(addr, type(IInsurerGovernor).interfaceId);
    _setGovernor(addr);
  }

  function governorContract() internal view virtual returns (IInsurerGovernor) {
    return IInsurerGovernor(_governorIsContract ? governorAccount() : address(0));
  }

  function isAllowedByGovernor(address account, uint256 flags) internal view override returns (bool) {
    return IInsurerGovernor(governorAccount()).governerQueryAccessControlMask(account, flags) & flags != 0;
  }

  function internalInitiateJoin(address insured) internal override returns (InsuredStatus) {
    IJoinHandler jh = governorContract();
    if (address(jh) == address(0)) {
      IApprovalCatalog c = approvalCatalog();
      require(address(c) == address(0) || c.hasApprovedApplication(insured));
      return InsuredStatus.Joining;
    } else {
      return jh.handleJoinRequest(insured);
    }
  }

  event GovernorUpdated(address);

  function _setGovernor(address addr) internal {
    emit GovernorUpdated(_governor = addr);
  }

  function governorAccount() internal view override returns (address) {
    return _governor;
  }
}
