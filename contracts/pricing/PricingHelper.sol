// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/Errors.sol';
import '../access/AccessHelper.sol';
import './interfaces/IManagedPriceRouter.sol';

abstract contract PricingHelper {
  IManagedPriceRouter private immutable _pricer;

  constructor(address pricer_) {
    _pricer = IManagedPriceRouter(pricer_);
  }

  function priceOracle() external view returns (address) {
    return address(getPricer());
  }

  function remoteAcl() internal view virtual returns (IAccessController pricer);

  function getPricer() internal view virtual returns (IManagedPriceRouter pricer) {
    pricer = _pricer;
    if (address(pricer) == address(0)) {
      pricer = IManagedPriceRouter(_getPricerByAcl(remoteAcl()));
      State.require(address(pricer) != address(0));
    }
  }

  function _getPricerByAcl(IAccessController acl) internal view returns (address) {
    return address(acl) == address(0) ? address(0) : acl.getAddress(AccessFlags.PRICE_ROUTER);
  }
}
