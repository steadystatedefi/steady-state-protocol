// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';
import '../tools/SafeERC20.sol';
import '../tools/Errors.sol';
import '../tools/tokens/ERC20BalancelessBase.sol';
import '../libraries/Balances.sol';
import '../tools/tokens/IERC20.sol';
import '../interfaces/IPremiumDistributor.sol';
import '../interfaces/IPremiumActuary.sol';
import '../interfaces/IPremiumSource.sol';
import '../interfaces/IInsuredPool.sol';
import '../tools/math/WadRayMath.sol';
import './BalancerLib2.sol';

import 'hardhat/console.sol';

contract PremiumFund is IPremiumDistributor {
  using WadRayMath for uint256;
  using SafeERC20 for IERC20;
  using BalancerLib2 for BalancerLib2.AssetBalancer;
  using Balances for Balances.RateAcc;

  mapping(address => BalancerLib2.AssetBalancer) private _balancers; // [actuary]

  enum ActuaryState {
    Unknown,
    Inactive,
    Active,
    Paused
  }

  struct ActuaryConfig {
    mapping(address => address) defaultSourceByToken; // [token]
    mapping(address => address) tokenBySource; // [token]
    mapping(address => uint256) debts; // [token]
    ActuaryState state;
    BalancerLib2.AssetConfig defaultConfig;
  }

  mapping(address => ActuaryConfig) private _configs; // [actuary]
  mapping(address => uint256) private _collectedFees; // [token]
  address private _collateral;

  constructor(address collateral_) {
    _collateral = collateral_;
  }

  function collateral() public view override returns (address) {
    return _collateral;
  }

  modifier onlyAdmin() virtual {
    // TODO
    _;
  }

  // TODO collectedFee / withdrawFee
  // TODO balanceOf
  // TODO balanceOfSource/Prepay, prepay/withdraw

  function registerPremiumActuary(address actuary, bool register) external onlyAdmin {
    ActuaryConfig storage config = _configs[actuary];
    if (register) {
      State.require(config.state < ActuaryState.Active);
      Value.require(IPremiumActuary(actuary).collateral() == collateral());

      config.state = ActuaryState.Active;
    } else if (config.state >= ActuaryState.Active) {
      config.state = ActuaryState.Inactive;
    }
  }

  function setPaused(address actuary, bool paused) external onlyAdmin {
    ActuaryConfig storage config = _configs[actuary];
    State.require(config.state >= ActuaryState.Active);

    config.state = paused ? ActuaryState.Paused : ActuaryState.Active;
  }

  function setPaused(
    address actuary,
    address token,
    bool paused
  ) external onlyAdmin {
    ActuaryConfig storage config = _configs[actuary];
    State.require(config.state > ActuaryState.Unknown);

    BalancerLib2.AssetConfig storage assetConfig = _balancers[actuary].configs[token];
    uint16 flags = assetConfig.flags;
    assetConfig.flags = paused ? flags | BalancerLib2.SPM_SUSPENDED : flags & ~BalancerLib2.SPM_SUSPENDED;
  }

  function registerPremiumSource(address source, bool register) external override {
    address actuary = msg.sender;

    ActuaryConfig storage config = _configs[actuary];
    State.require(config.state >= ActuaryState.Active);
    Value.require(source != address(this));

    BalancerLib2.AssetBalancer storage balancer = _balancers[actuary];

    if (register) {
      require(config.tokenBySource[source] == address(0));
      address targetToken = IPremiumSource(source).premiumToken();
      require(targetToken != address(0));
      config.tokenBySource[source] = targetToken;

      if (config.defaultSourceByToken[targetToken] == address(0)) {
        config.defaultSourceByToken[targetToken] = source;

        BalancerLib2.AssetConfig storage balancerConfig = balancer.configs[targetToken];

        Balances.RateAcc storage balance = balancer.balances[source];

        // re-registration should keep price of accumulated assets
        require(balance.rate == 0);
        uint152 price = balance.accum != 0 ? balancerConfig.price : 0;

        balancer.configs[targetToken] = config.defaultConfig;
        if (price != 0) {
          balancerConfig.price = price;
        }
      }
    } else {
      address targetToken = config.tokenBySource[source];
      delete config.tokenBySource[source];

      if (targetToken != address(0) && config.defaultSourceByToken[targetToken] == targetToken) {
        delete config.defaultSourceByToken[targetToken];

        BalancerLib2.AssetConfig storage balancerConfig = balancer.configs[targetToken];
        uint16 flags = balancerConfig.flags;

        if (flags & BalancerLib2.SPM_FINISHED == 0) {
          balancer.changeRate(targetToken, 0);
          balancerConfig.flags = flags | BalancerLib2.SPM_FINISHED | BalancerLib2.SPM_SUSPENDED;
        }
      }
    }
  }

  function premiumAllocationUpdated(
    address source,
    uint256 accumulated,
    uint256 increment,
    uint256 rate
  ) external override {
    _premiumAllocationUpdated(source, accumulated, increment, rate);
  }

  function _premiumAllocationUpdated(
    address source,
    uint256 accumulated,
    uint256 increment,
    uint256 rate
  )
    private
    returns (
      address targetToken,
      ActuaryConfig storage config,
      BalancerLib2.AssetBalancer storage balancer
    )
  {
    config = _configs[msg.sender];
    State.require(config.state >= ActuaryState.Active);

    targetToken = config.tokenBySource[source];
    Value.require(targetToken != address(0));

    balancer = _balancers[msg.sender];
    require(
      balancer.replenishAsset(
        BalancerLib2.ReplenishParams({actuary: msg.sender, source: source, token: targetToken, replenishFn: _replenishFn}),
        increment,
        rate
      ) <= accumulated
    );
  }

  function premiumAllocationFinished(
    address source,
    uint256 accumulated,
    uint256 increment
  ) external override returns (uint256 premiumDebt) {
    (address targetToken, ActuaryConfig storage config, BalancerLib2.AssetBalancer storage balancer) = _premiumAllocationUpdated(
      source,
      accumulated,
      increment,
      0
    );

    if (config.defaultSourceByToken[targetToken] == source) {
      BalancerLib2.AssetConfig storage balancerConfig = balancer.configs[targetToken];
      balancerConfig.spConst = 0;
      balancerConfig.flags = BalancerLib2.SPM_CONSTANT | BalancerLib2.SPM_FINISHED;
    }

    premiumDebt = config.debts[source];
    if (premiumDebt > 0) {
      delete config.debts[source];
    }
  }

  function _replenishFn(BalancerLib2.ReplenishParams memory params, uint256 requiredAmount)
    private
    returns (uint256 replenishedAmount, uint256 replenishedValue)
  {
    ActuaryConfig storage config = _configs[params.actuary];
    uint256 price = priceOf(params.token);

    if (params.source == address(0)) {
      params.source = config.defaultSourceByToken[params.token];
    }

    uint256 debtValue = config.debts[params.source];
    if (debtValue > 0) {
      requiredAmount += uint256(debtValue).wadDiv(price);
      debtValue = 0;
    }

    if (requiredAmount > 0) {
      uint256 missingValue;
      (replenishedAmount, missingValue) = _collectPremium(params, requiredAmount, price);
      debtValue += missingValue;

      replenishedValue = replenishedAmount.wadMul(price);
    }
    config.debts[params.source] = debtValue;
  }

  function _collectPremium(
    BalancerLib2.ReplenishParams memory params,
    uint256 requiredAmount,
    uint256 price
  ) private returns (uint256 collectedAmount, uint256 missingValue) {
    collectedAmount = internalCollectPremium(params.actuary, params.source, IERC20(params.token), requiredAmount, requiredAmount.wadMul(price));
    if (collectedAmount < requiredAmount) {
      missingValue = (requiredAmount - collectedAmount).wadMul(price);

      if (missingValue > 0) {
        // assert(params.token != collateral());
        uint256 collectedValue = internalCollectPremium(params.actuary, params.source, IERC20(collateral()), missingValue, missingValue);

        if (collectedValue > 0) {
          missingValue -= collectedValue;
          collectedAmount += collectedValue.wadDiv(price);
        }
      }
    }
  }

  function priceOf(address token) public pure returns (uint256) {
    token;
    return WadRayMath.WAD;
    // TODO price oracle
  }

  event PremiumCollectionFailed(address indexed source, address indexed token, uint256 amount, string failureType, bytes reason);

  function internalCollectPremium(
    address actuary,
    address source,
    IERC20 token,
    uint256 amount,
    uint256 value
  ) internal virtual returns (uint256) {
    uint256 balance = token.balanceOf(address(this));

    string memory errType;
    bytes memory errReason;

    try IPremiumSource(source).collectPremium(actuary, address(token), amount, value) {
      return token.balanceOf(address(this)) - balance;
    } catch Error(string memory reason) {
      errType = 'error';
      errReason = bytes(reason);
    } catch (bytes memory reason) {
      errType = 'panic';
      errReason = reason;
    }
    emit PremiumCollectionFailed(source, address(token), amount, errType, errReason);

    return 0;
  }

  function syncAsset(address actuaryToken, address targetToken) public {
    if (_collateral == targetToken) {
      IPremiumActuary(actuaryToken).collectDrawdownPremium();
    } else {
      BalancerLib2.AssetBalancer storage balancer = _balancers[actuaryToken];
      balancer.replenishAsset(
        BalancerLib2.ReplenishParams({actuary: actuaryToken, source: address(0), token: targetToken, replenishFn: _replenishFn}),
        0
      );
    }
  }

  function syncAssets(address actuaryToken, address[] calldata targetTokens) external {
    for (uint256 i = 0; i < targetTokens.length; i++) {
      syncAsset(actuaryToken, targetTokens[i]);
    }
  }

  function swapAsset(
    address actuaryToken, // aka actuary
    address account,
    address recipient,
    uint256 valueToSwap,
    address targetToken,
    uint256 minAmount
  ) public returns (uint256 tokenAmount) {
    Value.require(recipient != address(0));

    uint256 fee;
    address burnReceiver;
    uint256 drawdownValue = IPremiumActuary(actuaryToken).collectDrawdownPremium();
    BalancerLib2.AssetBalancer storage balancer = _balancers[actuaryToken];

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
      (tokenAmount, fee) = balancer.swapAsset(_replenishParams(actuaryToken, targetToken), valueToSwap, minAmount, drawdownValue);
    }

    if (tokenAmount > 0) {
      IPremiumActuary(actuaryToken).burnPremium(account, valueToSwap, burnReceiver);
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
    address actuaryToken,
    address account,
    address defaultRecepient,
    SwapInstruction[] calldata instructions
  ) external returns (uint256[] memory tokenAmounts) {
    if (instructions.length <= 1) {
      return instructions.length == 0 ? tokenAmounts : _swapTokensOne(actuaryToken, account, defaultRecepient, instructions[0]);
    }

    uint256[] memory fees;
    (tokenAmounts, fees) = _swapTokens(actuaryToken, account, instructions, IPremiumActuary(actuaryToken).collectDrawdownPremium());

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
    address actuaryToken,
    address account,
    SwapInstruction[] calldata instructions,
    uint256 drawdownValue
  ) private returns (uint256[] memory tokenAmounts, uint256[] memory fees) {
    BalancerLib2.AssetBalancer storage balancer = _balancers[actuaryToken];

    uint256 drawdownBalance = drawdownValue;

    tokenAmounts = new uint256[](instructions.length);
    fees = new uint256[](instructions.length);

    Balances.RateAcc memory totalOrig = balancer.totalBalance;
    Balances.RateAcc memory totalSum;
    (totalSum.accum, totalSum.rate, totalSum.updatedAt) = (totalOrig.accum, totalOrig.rate, totalOrig.updatedAt);
    BalancerLib2.ReplenishParams memory params = _replenishParams(actuaryToken, address(0));

    uint256 totalValue;
    uint256 totalExtValue;
    for (uint256 i = 0; i < instructions.length; i++) {
      Balances.RateAcc memory total;
      (total.accum, total.rate, total.updatedAt) = (totalOrig.accum, totalOrig.rate, totalOrig.updatedAt);

      if (_collateral == instructions[i].targetToken) {
        (tokenAmounts[i], fees[i]) = _swapExtTokenInBatch(balancer, instructions[i], drawdownBalance, total);

        if (tokenAmounts[i] > 0) {
          totalExtValue += instructions[i].valueToSwap;
          drawdownBalance -= tokenAmounts[i];
        }
      } else {
        (tokenAmounts[i], fees[i]) = _swapTokenInBatch(balancer, instructions[i], drawdownValue, params, total);

        if (tokenAmounts[i] > 0) {
          _mergeTotals(totalSum, totalOrig, total);
          totalValue += instructions[i].valueToSwap;
        }
      }
    }

    if (totalValue > 0) {
      IPremiumActuary(actuaryToken).burnPremium(account, totalValue, address(this));
    }

    if (totalExtValue > 0) {
      IPremiumActuary(actuaryToken).burnPremium(account, totalValue, address(0));
    }

    balancer.totalBalance = totalSum;
  }

  function _replenishParams(address actuaryToken, address targetToken) private pure returns (BalancerLib2.ReplenishParams memory) {
    return BalancerLib2.ReplenishParams({actuary: actuaryToken, source: address(0), token: targetToken, replenishFn: _replenishFn});
  }

  function _swapTokenInBatch(
    BalancerLib2.AssetBalancer storage balancer,
    SwapInstruction calldata instruction,
    uint256 drawdownValue,
    BalancerLib2.ReplenishParams memory params,
    Balances.RateAcc memory total
  ) private returns (uint256 tokenAmount, uint256 fee) {
    params.token = instruction.targetToken;
    return balancer.swapAssetInBatch(params, instruction.valueToSwap, instruction.minAmount, drawdownValue, total);
  }

  function _swapExtTokenInBatch(
    BalancerLib2.AssetBalancer storage balancer,
    SwapInstruction calldata instruction,
    uint256 drawdownBalance,
    Balances.RateAcc memory total
  ) private view returns (uint256 tokenAmount, uint256 fee) {
    return balancer.swapExternalAssetInBatch(instruction.targetToken, instruction.valueToSwap, instruction.minAmount, drawdownBalance, total);
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
    address actuaryToken,
    address account,
    address defaultRecepient,
    SwapInstruction calldata instruction
  ) private returns (uint256[] memory tokenAmounts) {
    tokenAmounts = new uint256[](1);

    tokenAmounts[0] = swapAsset(
      actuaryToken,
      account,
      instruction.recipient != address(0) ? instruction.recipient : defaultRecepient,
      instruction.valueToSwap,
      instruction.targetToken,
      instruction.valueToSwap
    );
  }
}
