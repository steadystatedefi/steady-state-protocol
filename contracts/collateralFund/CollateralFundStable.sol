// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '../dependencies/IERC20Mintable.sol';
import '../dependencies/IERC1363Receiver.sol';
import '../interfaces/ICollateralFund.sol';
import '../interfaces/IInsurerPool.sol';
import '../pricing/interfaces/IPriceOracle.sol';
import '../tools/math/WadRayMath.sol';
import './CollateralFundBase.sol';

contract CollateralFundStable is CollateralFundBase {
  function _calculateAssetPrice(address a) internal pure override returns (uint256) {
    return 1;
  }
}
