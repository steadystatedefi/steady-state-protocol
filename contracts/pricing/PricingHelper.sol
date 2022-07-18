// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/Errors.sol';
import '../tools/math/PercentageMath.sol';
import '../tools/math/WadRayMath.sol';
import '../access/AccessHelper.sol';
import './interfaces/IManagedPriceRouter.sol';

abstract contract PricingHelper is AccessHelper {
  using WadRayMath for uint256;
  using PercentageMath for uint256;

  IManagedPriceRouter private immutable _pricer;

  constructor(address pricer_) {
    _pricer = IManagedPriceRouter(pricer_);
  }

  // _pricer = IManagedPriceRouter(address(acl) == address(0) ? address(0) : acl.getAddress(AccessFlags.PRICE_ROUTER));

  function internalGetPriceOf(address asset) internal view virtual returns (uint256) {}
}
