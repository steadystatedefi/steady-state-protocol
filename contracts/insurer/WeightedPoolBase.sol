// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/upgradeability/Delegator.sol';
import '../tools/tokens/ERC1363ReceiverBase.sol';
import '../interfaces/IPremiumActuary.sol';
import '../interfaces/IInsurerPool.sol';
import './WeightedPoolExtension.sol';

/// @dev NB! MUST HAVE NO STORAGE
abstract contract WeightedPoolBase is IInsurerPoolBase, IPremiumActuary, Delegator, ERC1363ReceiverBase {
  address internal immutable _extension;

  constructor(uint256 unitSize, WeightedPoolExtension extension) {
    require(extension.coverageUnitSize() == unitSize);
    _extension = address(extension);
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

  function addSubrogation(
    address donor,
    uint256 value /* TODO permissions? */
  ) external {
    if (value > 0) {
      internalSubrogate(donor, value);
    }
  }

  function internalSubrogate(address donor, uint256 value) internal virtual;
}
