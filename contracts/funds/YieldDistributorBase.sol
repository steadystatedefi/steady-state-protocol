// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../tools/SafeERC20.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/math/PercentageMath.sol';
import '../interfaces/IManagedCollateralCurrency.sol';
import '../interfaces/IYieldDistributor.sol';
import '../interfaces/IPremiumActuary.sol';
import '../interfaces/IPremiumSource.sol';
import '../access/AccessHelper.sol';

import '../access/AccessHelper.sol';
import './interfaces/ICollateralFund.sol';
import './Collateralized.sol';

abstract contract YieldDistributorBase is IYieldDistributor, IPremiumSourceDelegate, AccessHelper, Collateralized {
  using SafeERC20 for IERC20;
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  mapping(address => address) private _delegates;

  struct ActuaryProfile {
    uint256 x;
    // collateral balance
    // yield integral
  }
  mapping(address => ActuaryProfile) private _actuaries;

  struct YieldProfile {
    uint256 x;
  }
  mapping(address => YieldProfile) private _profiles; // [token]

  function collectPremium(
    address actuary,
    address token,
    uint256 amount,
    uint256 value,
    address recipient
  ) external override {
    Access.require(_delegates[token] == msg.sender);
    // Access.require(_actuaries[actuary]);
    Access.require(IPremiumActuary(actuary).premiumDistributor() == recipient);
  }
}
