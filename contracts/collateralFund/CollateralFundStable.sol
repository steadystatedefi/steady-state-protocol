// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '../tools/math/WadRayMath.sol';
import './CollateralFundBase.sol';
import '../tools/tokens/IERC20Details.sol';
import '../tools/SafeOwnable.sol';

contract CollateralFundStable is CollateralFundBase, SafeOwnable {
  constructor(string memory name) CollateralFundBase(name) {}

  function _calculateAssetPrice(address) internal pure override returns (uint256) {
    return 1;
  }

  function addDepositToken(address asset) external override onlyOwner returns (bool) {
    if (!depositWhitelist[asset]) {
      depositList.push(asset);
      depositWhitelist[asset] = true;
      idToUnderlying[_getId(asset)] = asset;
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

  function CreateToken(
    address underlying,
    string calldata name,
    string calldata symbol
  ) external onlyOwner returns (address) {
    return createToken(underlying, name, symbol);
  }

  function AddStrategy(
    address strategy,
    address token,
    uint128 amount
  ) external {
    activeStrategies.push(ITreasuryStrategy(strategy));
    setStrategyAllocation(strategy, token, amount);
  }
}
