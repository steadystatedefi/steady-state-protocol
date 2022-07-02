// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/upgradeability/Delegator.sol';
import '../tools/tokens/ERC1363ReceiverBase.sol';
import '../interfaces/IPremiumActuary.sol';
import '../interfaces/IInsurerPool.sol';
import '../governance/GovernedHelper.sol';
import './WeightedPoolExtension.sol';
import './WeightedPoolConfig.sol';

/// @dev NB! MUST HAVE NO STORAGE
abstract contract WeightedPoolBase is IInsurerPoolBase, IPremiumActuary, ICancellableCoverageDemand, Delegator, ERC1363ReceiverBase, GovernedHelper {
  address internal immutable _extension;
  IAccessController private immutable _remoteAcl;

  constructor(
    IAccessController acl,
    uint256 unitSize,
    WeightedPoolExtension extension
  ) {
    require(extension.coverageUnitSize() == unitSize);
    _extension = address(extension);
    _remoteAcl = acl;
  }

  // solhint-disable-next-line payable-fallback
  fallback() external {
    // all ICoverageDistributor etc functions should be delegated to the extension
    _delegate(_extension);
  }

  function remoteAcl() internal view override returns (IAccessController) {
    return _remoteAcl;
  }

  function charteredDemand() external pure override returns (bool) {
    return true;
  }

  function pushCoverageExcess() public virtual;

  event ExcessCoverageIncreased(uint256 coverageExcess); // TODO => ExcessCoverageUpdated

  function premiumDistributor() public view virtual returns (address);

  function _onlyPremiumDistributor() private view {
    require(msg.sender == premiumDistributor());
  }

  modifier onlyPremiumDistributor() virtual {
    _onlyPremiumDistributor();
    _;
  }

  function burnPremium(
    address account,
    uint256 value,
    address drawdownRecepient
  ) external override onlyPremiumDistributor {
    internalBurnPremium(account, value, drawdownRecepient);
  }

  function internalBurnPremium(
    address account,
    uint256 value,
    address drawdownRecepient
  ) internal virtual;

  function collectDrawdownPremium() external override onlyPremiumDistributor returns (uint256) {
    return internalCollectDrawdownPremium();
  }

  function internalCollectDrawdownPremium() internal virtual returns (uint256);

  function addSubrogation(address donor, uint256 value) external aclHas(AccessFlags.INSURER_OPS) {
    if (value > 0) {
      internalSubrogate(donor, value);
    }
  }

  function internalSubrogate(address donor, uint256 value) internal virtual;

  function internalSetGovernor(address) internal virtual;

  function setGovernor(address addr) external aclHas(AccessFlags.INSURER_ADMIN) {
    internalSetGovernor(addr);
  }

  function internalSetPremiumDistributor(address) internal virtual;

  function setPremiumDistributor(address addr) external aclHas(AccessFlags.INSURER_ADMIN) {
    internalSetPremiumDistributor(addr);
  }

  function internalSetPoolParams(WeightedPoolParams memory params) internal virtual;

  function internalDefaultLoopLimits(uint16[] memory limits) internal virtual;

  function setPoolParams(WeightedPoolParams calldata params) external onlyGovernorOr(AccessFlags.INSURER_ADMIN) {
    internalSetPoolParams(params);
  }

  function setDefaultLoopLimits(uint16[] calldata limits) external onlyGovernorOr(AccessFlags.INSURER_OPS) {
    internalDefaultLoopLimits(limits);
  }

  function _onlyInsuredOrOps(address insured) private view {
    if (insured != msg.sender) {
      _onlyGovernorOr(AccessFlags.INSURER_OPS);
    }
  }

  function cancelCoverage(address insured, uint256) external override returns (uint256 payoutValue) {
    /*
    ATTN! This method does access check for msg.sender as the extension has no access to AccessController.
     */
    _onlyInsuredOrOps(insured);
    payoutValue;
    _delegate(_extension);
  }

  function cancelCoverageDemand(
    address insured,
    uint256,
    uint256
  ) external override returns (uint256 cancelledUnits) {
    /*
    ATTN! This method does access check for msg.sender as the extension has no access to AccessController.
     */
    _onlyInsuredOrOps(insured);
    cancelledUnits;
    _delegate(_extension);
  }
}
