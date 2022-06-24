// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../tools/SafeERC20.sol';
import '../tools/Errors.sol';
import '../tools/tokens/ERC20BalancelessBase.sol';
import '../libraries/Balances.sol';
import '../libraries/AddressExt.sol';
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
  using EnumerableSet for EnumerableSet.AddressSet;

  mapping(address => BalancerLib2.AssetBalancer) private _balancers; // [actuary]

  enum ActuaryState {
    Unknown,
    Inactive,
    Active,
    Paused
  }

  struct TokenInfo {
    EnumerableSet.AddressSet sources;
    uint32 nextReplenish;
  }

  struct SourceBalance {
    uint128 debt;
    uint96 rate;
    uint32 updatedAt;
  }

  uint8 private constant TS_PRESENT = 1 << 0;
  uint8 private constant TS_SUSPENDED = 1 << 1;

  struct TokenState {
    uint128 collectedFees;
    uint8 flags;
  }

  struct ActuaryConfig {
    mapping(address => TokenInfo) tokens; // [token]
    mapping(address => address) sourceToken; // [source] => token
    mapping(address => SourceBalance) sourceBalances; // [source] - only for sources with a shared token
    BalancerLib2.AssetConfig defaultConfig;
    ActuaryState state;
  }

  mapping(address => ActuaryConfig) private _configs; // [actuary]
  mapping(address => TokenState) private _tokens; // [token]

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
      _markTokenAsPresent(collateral());

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
    Value.require(token != address(0));

    BalancerLib2.AssetConfig storage assetConfig = _balancers[actuary].configs[token];
    uint16 flags = assetConfig.flags;
    assetConfig.flags = paused ? flags | BalancerLib2.BF_SUSPENDED : flags & ~BalancerLib2.BF_SUSPENDED;
  }

  function setPausedToken(address token, bool paused) external onlyAdmin {
    Value.require(token != address(0));

    TokenState storage state = _tokens[token];
    uint8 flags = state.flags;
    state.flags = paused ? flags | TS_SUSPENDED : flags & ~TS_SUSPENDED;
  }

  uint8 private constant SOURCE_MULTI_MODE_MASK = 3;
  uint8 private constant SMM_SOLO = 0;
  uint8 private constant SMM_MANY_NO_LIST = 1;
  uint8 private constant SMM_LIST = 2;

  function registerPremiumSource(address source, bool register) external override {
    address actuary = msg.sender;

    ActuaryConfig storage config = _configs[actuary];
    State.require(config.state >= ActuaryState.Active);
    Value.require(source != address(this));

    if (register) {
      // NB! a source will actually be added on non-zero rate only
      require(config.sourceToken[source] == address(0));

      address targetToken = IPremiumSource(source).premiumToken();
      _markTokenAsPresent(targetToken);
      config.sourceToken[source] = targetToken;
    } else {
      address targetToken = config.sourceToken[source];
      if (targetToken != address(0)) {
        _removePremiumSource(config, _balancers[actuary], source, targetToken);
      }
    }
  }

  function _markTokenAsPresent(address token) private {
    require(token != address(0));
    TokenState storage state = _tokens[token];
    uint8 flags = state.flags;
    if (flags & TS_PRESENT == 0) {
      state.flags = flags | TS_PRESENT;
    }
  }

  function _addPremiumSource(
    ActuaryConfig storage config,
    BalancerLib2.AssetBalancer storage balancer,
    address targetToken,
    address source
  ) private {
    EnumerableSet.AddressSet storage tokenSources = config.tokens[targetToken].sources;

    State.require(tokenSources.add(source));

    if (tokenSources.length() == 1) {
      BalancerLib2.AssetBalance storage balance = balancer.balances[source];

      require(balance.rate == 0);
      // re-activation should keep price
      uint152 price = balance.accum == 0 ? 0 : balancer.configs[targetToken].price;
      balancer.configs[targetToken] = config.defaultConfig;
      balancer.configs[targetToken].price = price;
    }
  }

  function _removePremiumSource(
    ActuaryConfig storage config,
    BalancerLib2.AssetBalancer storage balancer,
    address source,
    address targetToken
  ) private {
    delete config.sourceToken[source];
    EnumerableSet.AddressSet storage tokenSources = config.tokens[targetToken].sources;

    if (tokenSources.remove(source)) {
      BalancerLib2.AssetConfig storage balancerConfig = balancer.configs[targetToken];

      SourceBalance storage sBalance = config.sourceBalances[source];
      uint96 rate = balancer.decRate(targetToken, sBalance.rate);

      delete config.sourceBalances[source];

      if (tokenSources.length() == 0) {
        require(rate == 0);
        balancerConfig.flags |= BalancerLib2.BF_FINISHED;
      }
    }
  }

  function _ensureActuary(address actuary) private view returns (ActuaryConfig storage config) {
    config = _configs[actuary];
    State.require(config.state >= ActuaryState.Active);
  }

  function _premiumAllocationUpdated(
    ActuaryConfig storage config,
    address actuary,
    address source,
    address token,
    uint256 increment,
    uint256 rate,
    bool checkSuspended
  )
    private
    returns (
      address targetToken,
      BalancerLib2.AssetBalancer storage balancer,
      SourceBalance storage sBalance
    )
  {
    Value.require(source != address(0));
    balancer = _balancers[actuary];

    sBalance = config.sourceBalances[source];
    (uint96 lastRate, uint32 updatedAt) = (sBalance.rate, sBalance.updatedAt);

    if (token == address(0)) {
      // this is a call from the actuary
      targetToken = config.sourceToken[source];
      Value.require(targetToken != address(0));

      if (updatedAt == 0 && rate > 0) {
        _addPremiumSource(config, balancer, targetToken, source);
      }
    } else {
      // this is a sync call from a user
      targetToken = token;
      rate = lastRate;
      increment = rate * (uint32(block.timestamp - updatedAt));
    }

    if (
      !balancer.replenishAsset(
        BalancerLib2.ReplenishParams({actuary: actuary, source: source, token: targetToken, replenishFn: _replenishFn}),
        increment,
        uint96(rate),
        lastRate,
        checkSuspended
      )
    ) {
      rate = 0;
    }

    if (lastRate != rate) {
      require((sBalance.rate = uint96(rate)) == rate);
    }
    sBalance.updatedAt = uint32(block.timestamp);
  }

  function premiumAllocationUpdated(
    address source,
    uint256,
    uint256 increment,
    uint256 rate
  ) external override {
    ActuaryConfig storage config = _ensureActuary(msg.sender);
    Value.require(source != address(0));
    Value.require(rate > 0);

    _premiumAllocationUpdated(config, msg.sender, source, address(0), increment, rate, false);
  }

  function premiumAllocationFinished(
    address source,
    uint256,
    uint256 increment
  ) external override returns (uint256 premiumDebt) {
    ActuaryConfig storage config = _ensureActuary(msg.sender);
    Value.require(source != address(0));

    (address targetToken, BalancerLib2.AssetBalancer storage balancer, SourceBalance storage sBalance) = _premiumAllocationUpdated(
      config,
      msg.sender,
      source,
      address(0),
      increment,
      0,
      false
    );

    premiumDebt = sBalance.debt;
    if (premiumDebt > 0) {
      sBalance.debt = 0;
    }

    _removePremiumSource(config, balancer, source, targetToken);
  }

  function _replenishFn(BalancerLib2.ReplenishParams memory params, uint256 requiredAmount)
    private
    returns (
      uint256 replenishedAmount,
      uint256 replenishedValue,
      uint256 expectedAmount
    )
  {
    /* ============================================================ */
    /* ============================================================ */
    /* ============================================================ */
    /* WARNING! Balancer logic and state MUST NOT be accessed here! */
    /* ============================================================ */
    /* ============================================================ */
    /* ============================================================ */

    ActuaryConfig storage config = _configs[params.actuary];
    uint256 price = priceOf(params.token);

    if (params.source == address(0)) {
      params.source = _sourceForReplenish(config, params.token);
    }

    SourceBalance storage balance = config.sourceBalances[params.source];
    {
      uint32 cur = uint32(block.timestamp);
      if (cur > balance.updatedAt) {
        expectedAmount = uint256(cur - balance.updatedAt) * balance.rate;
        balance.updatedAt = cur;
      } else {
        require(cur == balance.updatedAt);
        return (0, 0, 0);
      }
    }
    uint256 debtValue = balance.debt;
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
    require((balance.debt = uint128(debtValue)) == debtValue);
  }

  function _sourceForReplenish(ActuaryConfig storage config, address token) private returns (address) {
    TokenInfo storage tokenInfo = config.tokens[token];

    uint32 index = tokenInfo.nextReplenish;
    uint256 length = tokenInfo.sources.length();
    if (index >= length) {
      index = 0;
    }
    tokenInfo.nextReplenish = index + 1;

    return tokenInfo.sources.at(index);
  }

  function _collectPremium(
    BalancerLib2.ReplenishParams memory params,
    uint256 requiredAmount,
    uint256 price
  ) private returns (uint256 collectedAmount, uint256 missingValue) {
    collectedAmount = _collectPremiumCall(params.actuary, params.source, IERC20(params.token), requiredAmount, requiredAmount.wadMul(price));
    if (collectedAmount < requiredAmount) {
      missingValue = (requiredAmount - collectedAmount).wadMul(price);

      if (missingValue > 0) {
        // assert(params.token != collateral());
        uint256 collectedValue = _collectPremiumCall(params.actuary, params.source, IERC20(collateral()), missingValue, missingValue);

        if (collectedValue > 0) {
          missingValue -= collectedValue;
          collectedAmount += collectedValue.wadDiv(price);
        }
      }
    }
  }

  event PremiumCollectionFailed(address indexed source, address indexed token, uint256 amount, string failureType, bytes reason);

  function _collectPremiumCall(
    address actuary,
    address source,
    IERC20 token,
    uint256 amount,
    uint256 value
  ) private returns (uint256) {
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

  function priceOf(address token) public pure returns (uint256) {
    token;
    return WadRayMath.WAD;
    // TODO price oracle
  }

  function _ensureToken(address token) private view {
    uint8 flags = _tokens[token].flags;
    State.require(flags & TS_PRESENT != 0);
    if (flags & TS_SUSPENDED != 0) {
      revert Errors.OperationPaused();
    }
  }

  function _syncAsset(
    ActuaryConfig storage config,
    address actuary,
    address token,
    uint256 sourceLimit
  ) private returns (uint256) {
    _ensureToken(token);
    Value.require(token != address(0));
    if (_collateral == token) {
      IPremiumActuary(actuary).collectDrawdownPremium();
    }

    TokenInfo storage tokenInfo = config.tokens[token];

    uint32 index = tokenInfo.nextReplenish;
    uint256 length = tokenInfo.sources.length();

    if (index >= length) {
      index = 0;
    }
    uint256 stop = index;

    for (; sourceLimit > 0; sourceLimit--) {
      _premiumAllocationUpdated(config, actuary, tokenInfo.sources.at(index), token, 0, 0, true);
      index++;
      if (index >= length) {
        index = 0;
      }
      if (index == stop) {
        break;
      }
    }

    tokenInfo.nextReplenish = index;

    return sourceLimit;
  }

  function syncAsset(
    address actuary,
    uint256 sourceLimit,
    address targetToken
  ) public {
    if (sourceLimit == 0) {
      sourceLimit = ~sourceLimit;
    }

    ActuaryConfig storage config = _ensureActuary(actuary);
    _syncAsset(config, actuary, targetToken, sourceLimit);
  }

  function syncAssets(
    address actuary,
    uint256 sourceLimit,
    address[] calldata targetTokens
  ) external returns (uint256 i) {
    if (sourceLimit == 0) {
      sourceLimit = ~sourceLimit;
    }

    ActuaryConfig storage config = _ensureActuary(actuary);

    for (; i < targetTokens.length; i++) {
      sourceLimit = _syncAsset(config, actuary, targetTokens[i], sourceLimit);
      if (sourceLimit == 0) {
        break;
      }
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
    _ensureToken(targetToken);
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
      _addFee(_configs[actuaryToken], targetToken, fee);
    }
  }

  function _addFee(
    ActuaryConfig storage,
    address targetToken,
    uint256 fee
  ) private {
    require((_tokens[targetToken].collectedFees += uint128(fee)) >= fee);
  }

  struct SwapInstruction {
    uint256 valueToSwap;
    address targetToken;
    uint256 minAmount;
    address recipient;
  }

  function swapAssets(
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
    ActuaryConfig storage config = _configs[actuaryToken];

    for (uint256 i = 0; i < instructions.length; i++) {
      address recipient = instructions[i].recipient;
      address targetToken = instructions[i].targetToken;

      SafeERC20.safeTransfer(IERC20(targetToken), recipient == address(0) ? defaultRecepient : recipient, tokenAmounts[i]);

      if (fees[i] > 0) {
        _addFee(config, targetToken, fees[i]);
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
      _ensureToken(instructions[i].targetToken);

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
    (tokenAmount, fee, ) = balancer.swapAssetInBatch(params, instruction.valueToSwap, instruction.minAmount, drawdownValue, total);
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
