// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';
import '../tools/SafeERC20.sol';
import '../tools/Errors.sol';
import '../tools/tokens/ERC20BalancelessBase.sol';
import '../libraries/Balances.sol';
import '../tools/tokens/IERC20.sol';
import '../interfaces/IPremiumCalculator.sol';
import '../interfaces/IPremiumSink.sol';
import '../interfaces/IInsuredPool.sol';
import '../tools/math/WadRayMath.sol';
import './BalancerLib2.sol';

import 'hardhat/console.sol';

contract PremiumFund is IPremiumSink {
  using WadRayMath for uint256;
  using SafeERC20 for IERC20;
  using BalancerLib2 for BalancerLib2.AssetBalancer;
  using Balances for Balances.RateAcc;

  mapping(address => BalancerLib2.AssetBalancer) private _balancers; // [insurer]

  struct PoolConfig {
    mapping(address => address) insureds; // [token]
    mapping(address => int256) debts; // [token]
  }
  mapping(address => PoolConfig) private _configs; // [insurer]
  mapping(address => uint256) private _collectedFees; // [token]
  address private _collateral;

  function collateral() public view override returns (address) {
    return _collateral;
  }

  function premiumAllocationUpdated(
    address insured,
    uint256 accumulated,
    uint256 increment,
    uint256 rate
  ) external override {
    _premiumAllocationUpdated(insured, accumulated, increment, rate);
  }

  function _premiumAllocationUpdated(
    address insured,
    uint256 accumulated,
    uint256 increment,
    uint256 rate
  ) private {
    PoolConfig storage config = _configs[msg.sender];
    address targetToken = IInsuredPool(insured).premiumToken();
    require(config.insureds[insured] == targetToken);

    BalancerLib2.AssetBalancer storage balancer = _balancers[msg.sender];
    require(balancer.replenishAsset(targetToken, increment, rate, _replenishFn) <= accumulated);
  }

  function premiumAllocationFinished(
    address insured,
    uint256 accumulated,
    uint256 increment
  ) external override returns (uint256 premiumDebt) {
    _premiumAllocationUpdated(insured, accumulated, increment, 0);
    // TODO change config
    // TODO return debt
  }

  function _replenishFn(
    BalancerLib2.AssetBalancer storage,
    address,
    uint256 v
  ) private pure returns (uint256, uint256) {
    return (v, v);
  }

  function syncAsset(address poolToken, address targetToken) external {
    // if (_collateral == targetToken) {
    //   return;
    // }
    // BalancerLib2.AssetBalancer storage balancer = _balancers[poolToken];
  }

  function swapAsset(
    address poolToken, // aka insurer
    address account,
    address recipient,
    uint256 valueToSwap,
    address targetToken,
    uint256 minAmount
  ) public returns (uint256 tokenAmount) {
    require(recipient != address(0));

    uint256 fee;
    address burnReceiver;
    uint256 drawdownValue = IDynamicPremiumSource(poolToken).collectPremiumValue();
    BalancerLib2.AssetBalancer storage balancer = _balancers[poolToken];

    if (_collateral == targetToken) {
      (tokenAmount, fee) = balancer.swapExternalAsset(targetToken, valueToSwap, minAmount, drawdownValue);
      if (tokenAmount > 0) {
        if (fee == 0) {
          // use a direct transfer when no fees
          require(tokenAmount == valueToSwap);
          burnReceiver = recipient;
        } else {
          burnReceiver = address(this);
        }
      }
    } else {
      (tokenAmount, fee) = balancer.swapAsset(targetToken, valueToSwap, minAmount, drawdownValue, _replenishFn);
    }

    if (tokenAmount > 0) {
      IPremiumSource(poolToken).burnPremium(account, valueToSwap, burnReceiver);
      if (burnReceiver != recipient) {
        SafeERC20.safeTransfer(IERC20(targetToken), recipient, tokenAmount);
      }
    }

    if (fee > 0) {
      _collectedFees[targetToken] += fee;
    }
  }

  struct SwapInstruction {
    uint256 valueToSwap;
    address targetToken;
    uint256 minAmount;
    address recipient;
  }

  function swapTokens(
    address poolToken,
    address account,
    address defaultRecepient,
    SwapInstruction[] calldata instructions
  ) external returns (uint256[] memory tokenAmounts) {
    if (instructions.length <= 1) {
      return instructions.length == 0 ? tokenAmounts : _swapTokensOne(poolToken, account, defaultRecepient, instructions[0]);
    }

    uint256[] memory fees;
    (tokenAmounts, fees) = _swapTokens(poolToken, account, instructions, IDynamicPremiumSource(poolToken).collectPremiumValue());

    for (uint256 i = 0; i < instructions.length; i++) {
      address recipient = instructions[i].recipient;
      address targetToken = instructions[i].targetToken;

      SafeERC20.safeTransfer(IERC20(targetToken), recipient == address(0) ? defaultRecepient : recipient, tokenAmounts[i]);

      if (fees[i] > 0) {
        _collectedFees[targetToken] += fees[i];
      }
    }
  }

  function _swapTokens(
    address poolToken,
    address account,
    SwapInstruction[] calldata instructions,
    uint256 drawdownValue
  ) private returns (uint256[] memory tokenAmounts, uint256[] memory fees) {
    BalancerLib2.AssetBalancer storage balancer = _balancers[poolToken];

    uint256 drawdownBalance = drawdownValue;

    tokenAmounts = new uint256[](instructions.length);
    fees = new uint256[](instructions.length);

    Balances.RateAcc memory totalOrig = balancer.totalBalance;
    Balances.RateAcc memory totalSum;
    (totalSum.accum, totalSum.rate, totalSum.updatedAt) = (totalOrig.accum, totalOrig.rate, totalOrig.updatedAt);
    Balances.RateAcc memory total;

    uint256 totalValue;
    uint256 totalExtValue;
    for (uint256 i = 0; i < instructions.length; i++) {
      if (_collateral == instructions[i].targetToken) {
        (tokenAmounts[i], fees[i]) = balancer.swapExternalAssetInBatch(
          instructions[i].targetToken,
          instructions[i].valueToSwap,
          instructions[i].minAmount,
          drawdownBalance,
          total
        );

        if (tokenAmounts[i] > 0) {
          totalExtValue += instructions[i].valueToSwap;
          drawdownBalance -= tokenAmounts[i];
        }
      } else {
        (total.accum, total.rate, total.updatedAt) = (totalOrig.accum, totalOrig.rate, totalOrig.updatedAt);

        (tokenAmounts[i], fees[i]) = balancer.swapAssetInBatch(
          instructions[i].targetToken,
          instructions[i].valueToSwap,
          instructions[i].minAmount,
          drawdownValue,
          _replenishFn,
          total
        );

        if (tokenAmounts[i] > 0) {
          totalValue += instructions[i].valueToSwap;
          _mergeTotals(totalSum, totalOrig, total);
        }
      }
    }

    if (totalValue > 0) {
      IPremiumSource(poolToken).burnPremium(account, totalValue, address(this));
    }

    if (totalExtValue > 0) {
      IPremiumSource(poolToken).burnPremium(account, totalValue, address(0));
    }

    balancer.totalBalance = totalSum;
  }

  function _mergeValue(
    uint256 vSum,
    uint256 vOrig,
    uint256 v,
    uint256 max
  ) private pure returns (uint256) {
    if (vOrig >= v) {
      unchecked {
        v = vOrig - v;
      }
      v = vSum - v;
    } else {
      unchecked {
        v = v - vOrig;
      }
      require((v = vSum + v) <= max);
    }
    return v;
  }

  function _mergeTotals(
    Balances.RateAcc memory totalSum,
    Balances.RateAcc memory totalOrig,
    Balances.RateAcc memory total
  ) private pure {
    if (totalSum.updatedAt != total.updatedAt) {
      totalSum.sync(total.updatedAt);
    }
    totalSum.accum = uint128(_mergeValue(totalSum.accum, totalOrig.accum, total.accum, type(uint128).max));
    totalSum.rate = uint96(_mergeValue(totalSum.rate, totalOrig.rate, total.rate, type(uint96).max));
  }

  function _swapTokensOne(
    address poolToken,
    address account,
    address defaultRecepient,
    SwapInstruction calldata instruction
  ) private returns (uint256[] memory tokenAmounts) {
    tokenAmounts = new uint256[](1);

    tokenAmounts[0] = swapAsset(
      poolToken,
      account,
      instruction.recipient != address(0) ? instruction.recipient : defaultRecepient,
      instruction.valueToSwap,
      instruction.targetToken,
      instruction.valueToSwap
    );
  }
}
