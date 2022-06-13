// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';
import '../tools/SafeERC20.sol';
import '../tools/Errors.sol';
import '../tools/tokens/ERC20BalancelessBase.sol';
import '../libraries/Balances.sol';
import '../tools/tokens/IERC20.sol';
import '../interfaces/IPremiumCalculator.sol';
import '../interfaces/IInsurancePool.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IInsuredPool.sol';
import '../interfaces/IProtocol.sol';
import '../tools/math/WadRayMath.sol';
import '../insurance/InsurancePoolBase.sol';
import './BalancerLib.sol';

import 'hardhat/console.sol';

contract PremiumFund {
  using WadRayMath for uint256;
  using SafeERC20 for IERC20;
  using BalancerLib for BalancerLib.PoolPremiums;

  mapping(address => BalancerLib.PoolPremiums) private _premiums;
  address private _collateral;

  function swapToken(
    address poolToken,
    address account,
    uint256 valueToSwap,
    address targetToken,
    uint256 minAmount,
    address recipient
  ) external returns (uint256 tokenAmount) {
    require(recipient != address(0));
    BalancerLib.PoolPremiums storage pool = _premiums[poolToken];

    uint256 fee;
    (tokenAmount, fee) = pool.swapToken(targetToken, valueToSwap, minAmount);

    if (tokenAmount > 0) {
      address r;
      if (_collateral == targetToken) {
        if (fee == 0) {
          // use a direct transfer when no fees
          require(tokenAmount == valueToSwap);
          r = recipient;
        } else {
          r = address(this);
        }
      }
      pool.burnPremium(account, valueToSwap, r);
      if (r != recipient) {
        SafeERC20.safeTransfer(IERC20(targetToken), recipient, tokenAmount);
      }
    }
  }

  struct SwapInstruction {
    uint256 valueToSwap;
    address targetToken;
    uint256 minAmount;
    address recepient;
  }

  function swapTokens(
    address poolToken,
    address account,
    address defaultRecepient,
    SwapInstruction[] calldata instructions
  ) external returns (uint256[] memory) {}
}
