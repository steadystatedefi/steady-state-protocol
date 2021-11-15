// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '../dependencies/IERC20Mintable.sol';
import '../dependencies/IERC1363Receiver.sol';
import '../interfaces/ICollateralFund.sol';
import '../interfaces/IInsurerPool.sol';
import '../pricing/interfaces/IPriceOracle.sol';
import '../tools/math/WadRayMath.sol';
import './CollateralFundBase.sol';
import './DepositToken.sol';

contract CollateralFundStable is CollateralFundBase {
  constructor(string memory name, string memory symbol) CollateralFundBase(name, symbol) {}

  function _calculateAssetPrice(address a) internal pure override returns (uint256) {
    return 1;
  }

  //TODO: Ownable
  function addDepositToken(address asset) external override returns (bool) {
    if (address(depositTokens[asset]) == address(0)) {
      depositTokenList.push(asset);

      //TODO: Do we want to make this here? Or will multiple collateral funds share?
      string memory tokenName = string(abi.encodePacked('COL-', ERC20(asset).name()));
      string memory tokenSymbol = string(abi.encodePacked('COL-', ERC20(asset).symbol()));
      depositTokens[asset] = new DepositToken(tokenName, tokenSymbol, address(this), asset);
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
