// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/upgradeability/Delegator.sol';
import '../tools/tokens/ERC1363ReceiverBase.sol';
import '../interfaces/IPremiumActuary.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IJoinable.sol';
import './WeightedPoolExtension.sol';
import './JoinablePoolExtension.sol';
import './WeightedPoolStorage.sol';

abstract contract WeightedPoolBase is IJoinableBase, IInsurerPoolBase, IPremiumActuary, Delegator, ERC1363ReceiverBase, WeightedPoolStorage {
  address internal immutable _extension;
  address internal immutable _joinExtension;

  constructor(
    WeightedPoolExtension extension,
    JoinablePoolExtension joinExtension
  ) WeightedPoolConfig(joinExtension.accessController(), extension.coverageUnitSize(), extension.collateral()) {
    // require(extension.accessController() == joinExtension.accessController());
    // require(extension.coverageUnitSize() == joinExtension.coverageUnitSize());
    require(extension.collateral() == joinExtension.collateral());
    // TODO check for the same access controller
    _extension = address(extension);
    _joinExtension = address(joinExtension);
  }

  // solhint-disable-next-line payable-fallback
  fallback() external {
    // all ICoverageDistributor etc functions should be delegated to the extension
    _delegate(_extension);
  }

  function charteredDemand() external pure override returns (bool) {
    return true;
  }

  function pushCoverageExcess() public virtual;

  /// @dev initiates evaluation of the insured pool by this insurer. May involve governance activities etc.
  /// IInsuredPool.joinProcessed will be called after the decision is made.
  function requestJoin(address) external override {
    _delegate(_joinExtension);
  }

  function approveJoiner(address, bool) external onlyGovernorOr(AccessFlags.INSURER_OPS) {
    _delegate(_joinExtension);
  }

  function governor() public view returns (address) {
    return governorAccount();
  }

  event ExcessCoverageIncreased(uint256 coverageExcess); // TODO => ExcessCoverageUpdated

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

  function setGovernor(address addr) external aclHas(AccessFlags.INSURER_ADMIN) {
    internalSetGovernor(addr);
  }

  function setPremiumDistributor(address addr) external aclHas(AccessFlags.INSURER_ADMIN) {
    internalSetPremiumDistributor(addr);
  }

  function setPoolParams(WeightedPoolParams calldata params) external onlyGovernorOr(AccessFlags.INSURER_ADMIN) {
    internalSetPoolParams(params);
  }

  function setDefaultLoopLimits(uint16[] calldata limits) external onlyGovernorOr(AccessFlags.INSURER_OPS) {
    internalDefaultLoopLimits(limits);
  }

  /// @return status The status of the account, NotApplicable if unknown about this address or account is an investor
  function statusOf(address account) external view returns (InsuredStatus status) {
    return internalStatusOf(account);
  }

  function premiumDistributor() public view override returns (address) {
    return address(_premiumDistributor);
  }
}
