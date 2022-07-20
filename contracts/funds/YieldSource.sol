// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../tools/SafeERC20.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/math/PercentageMath.sol';
import '../interfaces/IPremiumSource.sol';

import '../access/AccessHelper.sol';
import './YieldDistributorBase.sol';
import './Collateralized.sol';

abstract contract YieldSource is IPremiumSource {
  using SafeERC20 for IERC20;
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  address private immutable _token;
  IPremiumSourceDelegate private immutable _delegate;

  constructor(address token, IPremiumSourceDelegate delegate) {
    Value.require(token != address(0));
    Value.require(address(delegate) != address(0));
    _token = token;
    _delegate = delegate;
  }

  function premiumToken() external view override returns (address) {
    return _token;
  }

  function collectPremium(
    address actuary,
    address token,
    uint256 amount,
    uint256 value
  ) external override {
    _delegate.collectPremium(actuary, token, amount, value, msg.sender);
  }
}
