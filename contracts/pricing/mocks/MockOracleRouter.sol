// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../tools/Errors.sol';
import '../../tools/math/PercentageMath.sol';
import '../../tools/math/WadRayMath.sol';
import '../../access/AccessHelper.sol';
import '../interfaces/IManagedPriceRouter.sol';
import '../interfaces/IPriceFeedChainlinkV3.sol';
import '../interfaces/IPriceFeedUniswapV2.sol';
import '../OracleRouterBase.sol';

contract MockOracleRouter is OracleRouterBase {
  using WadRayMath for uint256;
  using PercentageMath for uint256;

  constructor(IAccessController acl, address quote) AccessHelper(acl) OracleRouterBase(quote) {}

  function pullAssetPrice(address asset, uint256) external view override returns (uint256) {
    return getAssetPrice(asset);
  }

  function attachSource(address asset, bool) external virtual override {
    Value.require(asset != address(0));
  }

  function resetSourceGroup() external virtual override {}

  function internalResetGroup(uint256 mask) internal override {}

  function internalRegisterGroup(address account, uint256 mask) internal override {}

  function groupsOf(address) external pure override returns (uint256 memberOf, uint256 ownerOf) {
    return (0, 0);
  }
}
