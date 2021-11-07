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

  //TODO: Ownable
  function addDepositToken(address asset) external override returns (bool) {
    if (address(depositTokens[asset]) == address(0)) {
      //TODO: Confirm it meets spec?
      depositTokenList.push(asset);
      depositTokens[asset] = IDepositToken(asset);
    }

    return true;
  }

  //TODO: Ownable
  function addInsurer(address insurer) external override returns (bool) {
    if (!insurerWhitelist[insurer]) {
      insurerWhitelist[insurer] = true;
      insurers.push(insurer);
    }

    return true;
  }
}
