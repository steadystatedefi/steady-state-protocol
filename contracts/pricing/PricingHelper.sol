// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/Errors.sol';
import '../access/AccessHelper.sol';
import './interfaces/IManagedPriceRouter.sol';

/// @dev A template to access a pricer
abstract contract PricingHelper {
  /// @return address of a price oracle / router
  function priceOracle() external view returns (address) {
    return address(getPricer());
  }

  function remoteAcl() internal view virtual returns (IAccessController);

  function getPricer() internal view virtual returns (IManagedPriceRouter pricer) {
    IAccessController acl = remoteAcl();
    if (address(acl) != address(0)) {
      pricer = IManagedPriceRouter(acl.getAddress(AccessFlags.PRICE_ROUTER));
    }
    State.require(address(pricer) != address(0));
  }
}
