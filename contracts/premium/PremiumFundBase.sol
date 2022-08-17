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
import '../access/AccessHelper.sol';
import '../pricing/PricingHelper.sol';
import '../funds/Collateralized.sol';
import '../interfaces/IPremiumDistributor.sol';
import '../interfaces/IPremiumActuary.sol';
import '../interfaces/IPremiumSource.sol';
import '../interfaces/IInsuredPool.sol';
import '../tools/math/WadRayMath.sol';
import './BalancerLib2.sol';

import 'hardhat/console.sol';

contract PremiumFundBase is IPremiumDistributor, AccessHelper, PricingHelper, Collateralized {
  using WadRayMath for uint256;
  using SafeERC20 for IERC20;
  using BalancerLib2 for BalancerLib2.AssetBalancer;
  using Balances for Balances.RateAcc;
  using EnumerableSet for EnumerableSet.AddressSet;

  mapping(address => BalancerLib2.AssetBalancer) internal _balancers; // [actuary]

  enum ActuaryState {
    Unknown,
    Inactive,
    Active,
    Paused
  }

  struct TokenInfo {
    EnumerableSet.AddressSet activeSources;
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
    mapping(address => SourceBalance) sourceBalances; // [source] - to support shared tokens among different sources
    BalancerLib2.AssetConfig defaultConfig;
    ActuaryState state;
  }

  mapping(address => ActuaryConfig) internal _configs; // [actuary]
  mapping(address => TokenState) private _tokens; // [token]
  mapping(address => EnumerableSet.AddressSet) private _tokenActuaries; // [token]

  address[] private _knownTokens;

  constructor(IAccessController acl, address collateral_) AccessHelper(acl) Collateralized(collateral_) PricingHelper(_getPricerByAcl(acl)) {}

  function remoteAcl() internal view override(AccessHelper, PricingHelper) returns (IAccessController pricer) {
    return AccessHelper.remoteAcl();
  }

  event ActuaryAdded(address indexed actuary);
  event ActuaryRemoved(address indexed actuary);

  function registerPremiumActuary(address actuary, bool register) external virtual aclHas(AccessFlags.INSURER_ADMIN) {
    ActuaryConfig storage config = _configs[actuary];
    address cc = collateral();

    if (register) {
      State.require(config.state < ActuaryState.Active);
      Value.require(IPremiumActuary(actuary).collateral() == cc);
      if (_markTokenAsPresent(cc)) {
        _balancers[actuary].configs[cc].price = uint152(WadRayMath.WAD);
      }

      config.state = ActuaryState.Active;
      _tokenActuaries[cc].add(actuary);
      emit ActuaryAdded(actuary);
    } else if (config.state >= ActuaryState.Active) {
      config.state = ActuaryState.Inactive;
      _tokenActuaries[cc].remove(actuary);
      emit ActuaryRemoved(actuary);
    }
  }

  event ActuaryPaused(address indexed actuary, bool paused);
  event ActuaryTokenPaused(address indexed actuary, address indexed token, bool paused);
  event TokenPaused(address indexed token, bool paused);

  function setPaused(address actuary, bool paused) external onlyEmergencyAdmin {
    ActuaryConfig storage config = _configs[actuary];
    State.require(config.state >= ActuaryState.Active);

    config.state = paused ? ActuaryState.Paused : ActuaryState.Active;
    emit ActuaryPaused(actuary, paused);
  }

  function isPaused(address actuary) public view returns (bool) {
    return _configs[actuary].state == ActuaryState.Paused;
  }

  function setPaused(
    address actuary,
    address token,
    bool paused
  ) external onlyEmergencyAdmin {
    ActuaryConfig storage config = _configs[actuary];
    State.require(config.state > ActuaryState.Unknown);
    Value.require(token != address(0));

    BalancerLib2.AssetConfig storage assetConfig = _balancers[actuary].configs[token];
    uint16 flags = assetConfig.flags;
    assetConfig.flags = paused ? flags | BalancerLib2.BF_SUSPENDED : flags & ~BalancerLib2.BF_SUSPENDED;
    emit ActuaryTokenPaused(actuary, token, paused);
  }

  function isPaused(address actuary, address token) public view returns (bool) {
    ActuaryState state = _configs[actuary].state;
    if (state == ActuaryState.Active) {
      return _balancers[actuary].configs[token].flags & BalancerLib2.BF_SUSPENDED != 0;
    }
    return state == ActuaryState.Paused;
  }

  function setPausedToken(address token, bool paused) external onlyEmergencyAdmin {
    Value.require(token != address(0));

    TokenState storage state = _tokens[token];
    uint8 flags = state.flags;
    state.flags = paused ? flags | TS_SUSPENDED : flags & ~TS_SUSPENDED;
    emit TokenPaused(token, paused);
  }

  function isPausedToken(address token) public view returns (bool) {
    return _tokens[token].flags & TS_SUSPENDED != 0;
  }

  uint8 private constant SOURCE_MULTI_MODE_MASK = 3;
  uint8 private constant SMM_SOLO = 0;
  uint8 private constant SMM_MANY_NO_LIST = 1;
  uint8 private constant SMM_LIST = 2;

  event ActuarySourceAdded(address indexed actuary, address indexed source, address indexed token);
  event ActuarySourceRemoved(address indexed actuary, address indexed source, address indexed token);

  function registerPremiumSource(address source, bool register) external override {
    address actuary = msg.sender;

    ActuaryConfig storage config = _configs[actuary];
    State.require(config.state >= ActuaryState.Active);

    if (register) {
      Value.require(source != address(0) && source != collateral());
      // NB! a source will actually be added on non-zero rate only
      require(config.sourceToken[source] == address(0));

      address targetToken = IPremiumSource(source).premiumToken();
      _ensureNonCollateral(actuary, targetToken);
      _markTokenAsPresent(targetToken);
      config.sourceToken[source] = targetToken;
      _tokenActuaries[targetToken].add(actuary);
      emit ActuarySourceAdded(actuary, source, targetToken);
    } else {
      address targetToken = config.sourceToken[source];
      if (targetToken != address(0)) {
        if (_removePremiumSource(config, _balancers[actuary], source, targetToken)) {
          _tokenActuaries[targetToken].remove(actuary);
        }
        emit ActuarySourceRemoved(actuary, source, targetToken);
      }
    }
  }

  function _ensureNonCollateral(address actuary, address token) private view {
    Value.require(token != IPremiumActuary(actuary).collateral());
  }

  function _markTokenAsPresent(address token) private returns (bool) {
    require(token != address(0));
    TokenState storage state = _tokens[token];
    uint8 flags = state.flags;
    if (flags & TS_PRESENT == 0) {
      state.flags = flags | TS_PRESENT;
      _knownTokens.push(token);
      return true;
    }
    return false;
  }

  function _addPremiumSource(
    ActuaryConfig storage config,
    BalancerLib2.AssetBalancer storage balancer,
    address targetToken,
    address source
  ) private {
    EnumerableSet.AddressSet storage activeSources = config.tokens[targetToken].activeSources;

    State.require(activeSources.add(source));

    if (activeSources.length() == 1) {
      BalancerLib2.AssetBalance storage balance = balancer.balances[source];

      require(balance.rateValue == 0);
      // re-activation should keep price
      uint152 price = balance.accumAmount == 0 ? 0 : balancer.configs[targetToken].price;
      balancer.configs[targetToken] = config.defaultConfig;
      balancer.configs[targetToken].price = price;
    }
  }

  function _removePremiumSource(
    ActuaryConfig storage config,
    BalancerLib2.AssetBalancer storage balancer,
    address source,
    address targetToken
  ) private returns (bool allRemoved) {
    delete config.sourceToken[source];
    EnumerableSet.AddressSet storage activeSources = config.tokens[targetToken].activeSources;

    if (activeSources.remove(source)) {
      BalancerLib2.AssetConfig storage balancerConfig = balancer.configs[targetToken];

      SourceBalance storage sBalance = config.sourceBalances[source];
      uint96 rate = balancer.decRate(targetToken, sBalance.rate);

      delete config.sourceBalances[source];

      if (activeSources.length() == 0) {
        require(rate == 0);
        balancerConfig.flags |= BalancerLib2.BF_FINISHED;

        allRemoved = true;
      }
    } else {
      allRemoved = activeSources.length() == 0;
    }
  }

  function _ensureActuary(address actuary) private view returns (ActuaryConfig storage config) {
    config = _configs[actuary];
    State.require(config.state >= ActuaryState.Active);
  }

  function _ensureActiveActuary(address actuary) private view returns (ActuaryConfig storage config) {
    config = _configs[actuary];
    State.require(config.state == ActuaryState.Active);
  }

  event PremiumAllocationUpdated(
    address indexed actuary,
    address indexed source,
    address indexed token,
    uint256 increment,
    uint256 rate,
    bool underprovisioned
  );

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
      // this is a call from the actuary - it doesnt know about tokens, only about sources
      targetToken = config.sourceToken[source];
      Value.require(targetToken != address(0));

      if (updatedAt == 0 && rate > 0) {
        _addPremiumSource(config, balancer, targetToken, source);
      }
    } else {
      // this is a sync call from a user - who knows about tokens, but not about sources
      targetToken = token;
      rate = lastRate;
      increment = rate * (uint32(block.timestamp - updatedAt));
    }

    bool underprovisioned = !balancer.replenishAsset(
      BalancerLib2.ReplenishParams({actuary: actuary, source: source, token: targetToken, replenishFn: _replenishFn}),
      increment,
      uint96(rate),
      lastRate,
      checkSuspended
    );
    emit PremiumAllocationUpdated(actuary, source, token, increment, rate, underprovisioned);

    if (underprovisioned) {
      // the source failed to keep the promised premium rate, stop the rate to avoid false inflow
      sBalance.rate = 0;
    } else if (lastRate != rate) {
      Value.require((sBalance.rate = uint96(rate)) == rate);
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
    emit ActuarySourceRemoved(msg.sender, source, targetToken);
  }

  function _replenishFn(BalancerLib2.ReplenishParams memory params, uint256 requiredValue)
    private
    returns (
      uint256 replenishedAmount,
      uint256 replenishedValue,
      uint256 expectedValue
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

    if (params.source == address(0)) {
      // this is called by auto-replenishment during swap - it is not related to any specific source
      // will auto-replenish from one source only to keep gas cost stable
      params.source = _sourceForReplenish(config, params.token);
    }

    SourceBalance storage balance = config.sourceBalances[params.source];
    {
      uint32 cur = uint32(block.timestamp);
      if (cur > balance.updatedAt) {
        expectedValue = uint256(cur - balance.updatedAt) * balance.rate;
        balance.updatedAt = cur;
      } else {
        require(cur == balance.updatedAt);
        return (0, 0, 0);
      }
    }
    if (requiredValue < expectedValue) {
      requiredValue = expectedValue;
    }

    uint256 debtValue = balance.debt;
    requiredValue += debtValue;

    if (requiredValue > 0) {
      uint256 missingValue;
      uint256 price = internalPriceOf(params.token);

      (replenishedAmount, missingValue) = _collectPremium(params, requiredValue, price);

      if (debtValue != missingValue) {
        require((balance.debt = uint128(missingValue)) == missingValue);
      }

      replenishedValue = replenishedAmount.wadMul(price);
    }
  }

  function _sourceForReplenish(ActuaryConfig storage config, address token) private returns (address) {
    TokenInfo storage tokenInfo = config.tokens[token];

    uint32 index = tokenInfo.nextReplenish;
    EnumerableSet.AddressSet storage activeSources = tokenInfo.activeSources;
    uint256 length = activeSources.length();
    if (index >= length) {
      index = 0;
    }
    tokenInfo.nextReplenish = index + 1;

    return activeSources.at(index);
  }

  function _collectPremium(
    BalancerLib2.ReplenishParams memory params,
    uint256 requiredValue,
    uint256 price
  ) private returns (uint256 collectedAmount, uint256 missingValue) {
    uint256 requiredAmount = requiredValue.wadDiv(price);
    collectedAmount = _collectPremiumCall(params.actuary, params.source, IERC20(params.token), requiredAmount, requiredValue);
    if (collectedAmount < requiredAmount) {
      missingValue = (requiredAmount - collectedAmount).wadMul(price);

      /*

      // This section of code enables use of CC as an additional way of premium payment

      if (missingValue > 0) {
        // assert(params.token != collateral());
        uint256 collectedValue = _collectPremiumCall(params.actuary, params.source, IERC20(collateral()), missingValue, missingValue);

        if (collectedValue > 0) {
          missingValue -= collectedValue;
          collectedAmount += collectedValue.wadDiv(price);
        }
      }

      */
    }
  }

  event PremiumCollectionFailed(address indexed source, address indexed token, uint256 amount, bool isPanic, bytes reason);

  function _collectPremiumCall(
    address actuary,
    address source,
    IERC20 token,
    uint256 amount,
    uint256 value
  ) private returns (uint256) {
    uint256 balance = token.balanceOf(address(this));

    bool isPanic;
    bytes memory errReason;

    try IPremiumSource(source).collectPremium(actuary, address(token), amount, value) {
      return token.balanceOf(address(this)) - balance;
    } catch Error(string memory reason) {
      errReason = bytes(reason);
    } catch (bytes memory reason) {
      isPanic = true;
      errReason = reason;
    }
    emit PremiumCollectionFailed(source, address(token), amount, isPanic, errReason);

    return 0;
  }

  function priceOf(address token) public view returns (uint256) {
    return internalPriceOf(token);
  }

  function internalPriceOf(address token) internal view virtual returns (uint256) {
    return getPricer().getAssetPrice(token);
  }

  function _ensureToken(address token) private view {
    uint8 flags = _tokens[token].flags;
    State.require(flags & TS_PRESENT != 0);
    if (flags & TS_SUSPENDED != 0) {
      revert Errors.OperationPaused();
    }
  }

  // slither-disable-next-line calls-loop
  function _syncAsset(
    ActuaryConfig storage config,
    address actuary,
    address token,
    uint256 sourceLimit
  ) private returns (uint256) {
    _ensureToken(token);
    Value.require(token != address(0));
    if (collateral() == token) {
      IPremiumActuary(actuary).collectDrawdownPremium();
      return sourceLimit == 0 ? 0 : sourceLimit - 1;
    }

    TokenInfo storage tokenInfo = config.tokens[token];
    EnumerableSet.AddressSet storage activeSources = tokenInfo.activeSources;
    uint256 length = activeSources.length();

    if (length > 0) {
      uint32 index = tokenInfo.nextReplenish;
      if (index >= length) {
        index = 0;
      }
      uint256 stop = index;

      for (; sourceLimit > 0; sourceLimit--) {
        _premiumAllocationUpdated(config, actuary, activeSources.at(index), token, 0, 0, true);
        index++;
        if (index >= length) {
          index = 0;
        }
        if (index == stop) {
          break;
        }
      }

      tokenInfo.nextReplenish = index;
    }

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

    ActuaryConfig storage config = _ensureActiveActuary(actuary);
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

    ActuaryConfig storage config = _ensureActiveActuary(actuary);

    for (; i < targetTokens.length; i++) {
      sourceLimit = _syncAsset(config, actuary, targetTokens[i], sourceLimit);
      if (sourceLimit == 0) {
        break;
      }
    }
  }

  function assetBalance(address actuary, address asset)
    external
    view
    returns (
      uint256 amount,
      uint256 stravation,
      uint256 price,
      uint256 feeFactor
    )
  {
    ActuaryConfig storage config = _configs[actuary];
    if (config.state > ActuaryState.Unknown) {
      (, amount, stravation, price, feeFactor) = _balancers[actuary].assetState(asset);
    }
  }

  function swapAsset(
    address actuary,
    address account,
    address recipient,
    uint256 valueToSwap,
    address targetToken,
    uint256 minAmount
  ) public returns (uint256 tokenAmount) {
    _ensureActiveActuary(actuary);
    _ensureToken(targetToken);
    Value.require(recipient != address(0));

    uint256 fee;
    address burnReceiver;
    uint256 drawdownValue = IPremiumActuary(actuary).collectDrawdownPremium();
    BalancerLib2.AssetBalancer storage balancer = _balancers[actuary];

    if (collateral() == targetToken) {
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
      (tokenAmount, fee) = balancer.swapAsset(_replenishParams(actuary, targetToken), valueToSwap, minAmount, drawdownValue);
    }

    if (tokenAmount > 0) {
      IPremiumActuary(actuary).burnPremium(account, valueToSwap, burnReceiver);
      if (burnReceiver != recipient) {
        SafeERC20.safeTransfer(IERC20(targetToken), recipient, tokenAmount);
      }
    }

    if (fee > 0) {
      _addFee(_configs[actuary], targetToken, fee);
    }
  }

  function _addFee(
    ActuaryConfig storage,
    address targetToken,
    uint256 fee
  ) private {
    require((_tokens[targetToken].collectedFees += uint128(fee)) >= fee);
  }

  function availableFee(address targetToken) external view returns (uint256) {
    return _tokens[targetToken].collectedFees;
  }

  function collectFees(
    address[] calldata tokens,
    uint256 minAmount,
    address recipient
  ) external aclHas(AccessFlags.TREASURY) returns (uint256[] memory fees) {
    Value.require(recipient != address(0));
    if (minAmount == 0) {
      minAmount = 1;
    }

    fees = new uint256[](tokens.length);
    for (uint256 i = tokens.length; i > 0; ) {
      i--;
      TokenState storage state = _tokens[tokens[i]];

      uint256 fee = state.collectedFees;
      if (fee >= minAmount) {
        state.collectedFees = 0;
        IERC20(tokens[i]).safeTransfer(recipient, fees[i] = fee);
      }
    }
  }

  struct SwapInstruction {
    uint256 valueToSwap;
    address targetToken;
    uint256 minAmount;
    address recipient;
  }

  function swapAssets(
    address actuary,
    address account,
    address defaultRecepient,
    SwapInstruction[] calldata instructions
  ) external returns (uint256[] memory tokenAmounts) {
    if (instructions.length <= 1) {
      // _ensureActiveActuary is applied inside swapToken invoked via _swapTokensOne
      return instructions.length == 0 ? tokenAmounts : _swapTokensOne(actuary, account, defaultRecepient, instructions[0]);
    }

    _ensureActiveActuary(actuary);

    uint256[] memory fees;
    (tokenAmounts, fees) = _swapTokens(actuary, account, instructions, IPremiumActuary(actuary).collectDrawdownPremium());
    ActuaryConfig storage config = _configs[actuary];

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
    address actuary,
    address account,
    SwapInstruction[] calldata instructions,
    uint256 drawdownValue
  ) private returns (uint256[] memory tokenAmounts, uint256[] memory fees) {
    BalancerLib2.AssetBalancer storage balancer = _balancers[actuary];

    uint256 drawdownBalance = drawdownValue;

    tokenAmounts = new uint256[](instructions.length);
    fees = new uint256[](instructions.length);

    Balances.RateAcc memory totalOrig = balancer.totalBalance;
    Balances.RateAcc memory totalSum;
    (totalSum.accum, totalSum.rate, totalSum.updatedAt) = (totalOrig.accum, totalOrig.rate, totalOrig.updatedAt);
    BalancerLib2.ReplenishParams memory params = _replenishParams(actuary, address(0));

    uint256 totalValue;
    uint256 totalExtValue;
    for (uint256 i = 0; i < instructions.length; i++) {
      _ensureToken(instructions[i].targetToken);

      Balances.RateAcc memory total;
      (total.accum, total.rate, total.updatedAt) = (totalOrig.accum, totalOrig.rate, totalOrig.updatedAt);

      if (collateral() == instructions[i].targetToken) {
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
      IPremiumActuary(actuary).burnPremium(account, totalValue, address(0));
    }

    if (totalExtValue > 0) {
      IPremiumActuary(actuary).burnPremium(account, totalExtValue, address(this));
    }

    balancer.totalBalance = totalSum;
  }

  function _replenishParams(address actuary, address targetToken) private pure returns (BalancerLib2.ReplenishParams memory) {
    return BalancerLib2.ReplenishParams({actuary: actuary, source: address(0), token: targetToken, replenishFn: _replenishFn});
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
    address actuary,
    address account,
    address defaultRecepient,
    SwapInstruction calldata instruction
  ) private returns (uint256[] memory tokenAmounts) {
    tokenAmounts = new uint256[](1);

    tokenAmounts[0] = swapAsset(
      actuary,
      account,
      instruction.recipient != address(0) ? instruction.recipient : defaultRecepient,
      instruction.valueToSwap,
      instruction.targetToken,
      instruction.minAmount
    );
  }

  function knownTokens() external view returns (address[] memory) {
    return _knownTokens;
  }

  function actuariesOfToken(address token) public view returns (address[] memory) {
    return _tokenActuaries[token].values();
  }

  function actuaries() external view returns (address[] memory) {
    return actuariesOfToken(collateral());
  }

  function activeSourcesOf(address actuary, address token) external view returns (address[] memory) {
    return _configs[actuary].tokens[token].activeSources.values();
  }
}
