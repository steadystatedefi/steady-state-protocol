// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/upgradeability/VersionedInitializable.sol';
import '../tools/upgradeability/Delegator.sol';
import '../tools/tokens/ERC1363ReceiverBase.sol';
import '../interfaces/ICollateralStakeManager.sol';
import '../interfaces/IYieldStakeAsset.sol';
import '../interfaces/IPremiumActuary.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IJoinable.sol';
import './WeightedPoolExtension.sol';
import './JoinablePoolExtension.sol';
import './WeightedPoolStorage.sol';

abstract contract WeightedPoolBase is
  IJoinableBase,
  IInsurerPoolBase,
  IPremiumActuary,
  IYieldStakeAsset,
  Delegator,
  ERC1363ReceiverBase,
  WeightedPoolStorage,
  VersionedInitializable
{
  address internal immutable _extension;
  address internal immutable _joinExtension;

  constructor(WeightedPoolExtension extension, JoinablePoolExtension joinExtension)
    WeightedPoolConfig(joinExtension.accessController(), extension.coverageUnitSize(), extension.collateral())
  {
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

  function internalOnCoverageRecovered() internal virtual {
    pushCoverageExcess();
  }

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
      transferCollateralFrom(donor, address(this), value);
      internalSubrogated(value);
      internalOnCoverageRecovered();
      internalOnCoveredUpdated();
    }
  }

  function internalSubrogated(uint256 value) internal virtual;

  function setGovernor(address addr) external aclHas(AccessFlags.INSURER_ADMIN) {
    internalSetGovernor(addr);
  }

  function setPremiumDistributor(address addr) external aclHas(AccessFlags.INSURER_ADMIN) {
    internalSetPremiumDistributor(addr);
  }

  function setPoolParams(WeightedPoolParams calldata params) external onlyGovernorOr(AccessFlags.INSURER_ADMIN) {
    internalSetPoolParams(params);
  }

  // TODO setLoopLimits
  // function setLoopLimits(uint16[] calldata limits) external onlyGovernorOr(AccessFlags.INSURER_OPS) {
  //   internalSetLoopLimits(limits);
  // }

  /// @return status The status of the account, NotApplicable if unknown about this address or account is an investor
  function statusOf(address account) external view returns (InsuredStatus status) {
    return internalStatusOf(account);
  }

  function premiumDistributor() public view override returns (address) {
    return address(_premiumDistributor);
  }

  function internalReceiveTransfer(
    address operator,
    address account,
    uint256 amount,
    bytes calldata data
  ) internal override onlyCollateralCurrency onlyUnpaused {
    require(data.length == 0);
    require(operator != address(this) && account != address(this) && internalGetStatus(account) == InsuredStatus.Unknown);

    internalMintForCoverage(account, amount);
    internalOnCoveredUpdated();
  }

  function internalMintForCoverage(address account, uint256 value) internal virtual;

  function setPaused(bool paused) external onlyEmergencyAdmin {
    _paused = paused;
  }

  function isPaused() public view returns (bool) {
    return _paused;
  }

  function internalOnCoveredUpdated() internal {}

  function internalSyncStake() internal {
    ICollateralStakeManager m = ICollateralStakeManager(IManagedCollateralCurrency(collateral()).borrowManager());
    if (address(m) != address(0)) {
      m.syncByStakeAsset(totalSupply(), collateralSupply());
    }
  }

  function _coveredTotal() internal view returns (uint256) {
    (uint256 totalCovered, uint256 pendingCovered) = super.internalGetCoveredTotals();
    return totalCovered + pendingCovered;
  }

  function totalSupply() public view virtual override returns (uint256);

  function collateralSupply() public view override returns (uint256) {
    return _coveredTotal() + _excessCoverage;
  }

  function internalPullDemand(uint256 loopLimit) internal {
    uint256 insuredLimit = defaultLoopLimit(LoopLimitType.AddCoverageDemandByPull, 0);

    for (; loopLimit > 0; ) {
      address insured;
      (insured, loopLimit) = super.internalPullDemandCandidate(loopLimit, false);
      if (insured == address(0)) {
        break;
      }
      if (IInsuredPool(insured).pullCoverageDemand(internalOpenBatchRounds() * internalUnitSize(), insuredLimit)) {
        if (loopLimit <= insuredLimit) {
          break;
        }
        loopLimit -= insuredLimit;
      }
    }
  }

  function internalAutoPullDemand(
    AddCoverageParams memory params,
    uint256 loopLimit,
    bool hasExcess,
    uint256 value
  ) internal {
    if (loopLimit > 0 && (hasExcess || params.openBatchNo == 0)) {
      uint256 n = _params.unitsPerAutoPull;
      if (n == 0) {
        return;
      }

      if (value != 0) {
        n = value / (n * internalUnitSize());
        if (n < loopLimit) {
          loopLimit = n;
        }
      }

      if (!hasExcess) {
        super.internalPullDemandCandidate(loopLimit == 0 ? 1 : loopLimit, true);
      } else if (loopLimit > 0) {
        internalPullDemand(loopLimit);
      }
    }
  }
}
