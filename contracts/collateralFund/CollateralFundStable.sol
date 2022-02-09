// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/access/Ownable.sol';
import '../tools/math/WadRayMath.sol';
import './CollateralFundBase.sol';
import './DepositToken.sol';
import '../tools/tokens/IERC20Details.sol';

contract CollateralFundStable is CollateralFundBase, Ownable {
  constructor(string memory name) CollateralFundBase(name) {}

  function _calculateAssetPrice(address) internal pure override returns (uint256) {
    return 1;
  }

  function addDepositToken(address asset) external override onlyOwner returns (bool) {
    if (!depositWhitelist[asset]) {
      depositList.push(asset);
      depositWhitelist[asset] = true;
      idToUnderlying[_getId(asset)] = asset;

      //TODO: Probably should move the logic of this function to CollateralFundBalances for when 'ERC20 mode' is enabled

      //string memory tokenName = string(abi.encodePacked('COL-', IERC20Details(asset).name()));
      //string memory tokenSymbol = string(abi.encodePacked('COL-', IERC20Details(asset).symbol()));
      //depositTokens[asset] = new DepositToken(tokenName, tokenSymbol, address(this), asset);
    }

    return true;
  }

  //TODO: Ownable
  function addInsurer(address insurer) external override onlyOwner returns (bool) {
    if (!insurerWhitelist[insurer]) {
      insurerWhitelist[insurer] = true;
      insurers.push(insurer);
    }

    return true;
  }
}
