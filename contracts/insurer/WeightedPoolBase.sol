// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/upgradeability/Delegator.sol';
import '../tools/tokens/ERC1363ReceiverBase.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IPremiumActuary.sol';
import './WeightedPoolExtension.sol';

/// @dev NB! MUST HAVE NO STORAGE
abstract contract WeightedPoolBase is IInsurerPoolCore, IPremiumActuary, Delegator, ERC1363ReceiverBase {
  address internal immutable _extension;

  constructor(uint256 unitSize, WeightedPoolExtension extension) {
    require(extension.coverageUnitSize() == unitSize);
    _extension = address(extension);
  }

  // solhint-disable-next-line payable-fallback
  fallback() external {
    // all IInsurerPoolDemand etc functions should be delegated to the extension
    _delegate(_extension);
  }

  /// @inheritdoc IInsurerPoolBase
  function charteredDemand() external pure override returns (bool) {
    return true;
  }

  function pushCoverageExcess() public virtual;

  event ExcessCoverageIncreased(uint256 coverageExcess);
}
