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
import './interfaces/IPremiumFund.sol';
import '../interfaces/IPremiumActuary.sol';
import '../interfaces/IPremiumSource.sol';
import '../interfaces/IInsuredPool.sol';
import '../tools/math/WadRayMath.sol';
import './BalancerLib2.sol';

import 'hardhat/console.sol';

contract PremiumFundBase is IPremiumDistributor, IPremiumFund, AccessHelper, PricingHelper, Collateralized {
  using WadRayMath for uint256;
  using SafeERC20 for IERC20;
  using BalancerLib2 for BalancerLib2.AssetBalancer;
  using Balances for Balances.RateAcc;
  using EnumerableSet for EnumerableSet.AddressSet;
  using CalcConfig for CalcConfigValue;

  uint256 internal constant APPROVE_SWAP = 1 << 0;
  mapping(address => mapping(address => uint256)) private _approvals; // [account][operator]

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
    uint128 lastPremium;
    uint96 rate;
    uint32 updatedAt;
  }

  uint8 private constant TS_PRESENT = 1 << 0;
  uint8 private constant TS_SUSPENDED = 1 << 1;

  struct TokenState {
    uint8 flags;
    uint128 collectedFees;
  }

  struct ActuaryConfig {
    ActuaryState state;
    mapping(address => TokenInfo) tokens; // [token]
    mapping(address => address) sourceToken; // [source] => token
    mapping(address => SourceBalance) sourceBalances; // [source] - to support shared tokens among different sources
  }

  mapping(address => ActuaryConfig) internal _configs; // [actuary]
  mapping(address => TokenState) private _tokens; // [token]
  mapping(address => EnumerableSet.AddressSet) private _tokenActuaries; // [token]

  address[] private _knownTokens;

  constructor(IAccessController acl, address collateral_) AccessHelper(acl) Collateralized(collateral_) {}

  function remoteAcl() internal view override(AccessHelper, PricingHelper) returns (IAccessController pricer) {
    return AccessHelper.remoteAcl();
  }

  event ActuaryAdded(address indexed actuary);
  event ActuaryRemoved(address indexed actuary);

  function _initializeTemplate(address cc) internal {
    _balancers[address(0)].configs[cc].calc = CalcConfig.newValue(
      uint144(WadRayMath.WAD),
      0,
      // by default a user can swap for free 1/5 (20%) of availableDrawdown * user's share in the insurer
      CalcConfig.SP_EXTERNAL_N_BASE / 5,
      CalcConfig.BF_EXTERNAL
    );
  }

  function registerPremiumActuary(address actuary, bool register) external virtual aclHas(AccessFlags.INSURER_ADMIN) {
    ActuaryConfig storage config = _configs[actuary];
    address cc = collateral();

    if (register) {
      State.require(config.state < ActuaryState.Active);
      Value.require(IPremiumActuary(actuary).collateral() == cc);
      _markTokenAsPresent(cc);

      BalancerLib2.AssetBalancer storage templateBalancer = _balancers[address(0)];

      _balancers[actuary].spConst = templateBalancer.spConst;
      _balancers[actuary].spFactor = templateBalancer.spFactor;
      _balancers[actuary].configs[cc] = templateBalancer.configs[cc];
      _balancers[actuary].configs[address(0)] = templateBalancer.configs[address(0)];

      config.state = ActuaryState.Active;
      _tokenActuaries[cc].add(actuary);
      emit ActuaryAdded(actuary);
    } else if (config.state >= ActuaryState.Active) {
      config.state = ActuaryState.Inactive;
      _tokenActuaries[cc].remove(actuary);
      emit ActuaryRemoved(actuary);
    }
  }

  function _setAssetConfig(
    address actuary,
    address token,
    BalancerLib2.AssetConfig memory ac
  ) private {
    _balancers[actuary].configs[token] = ac;
  }

  function setActuaryGlobals(
    address actuary,
    uint160 spConst,
    uint32 spFactor
  ) external aclHas(AccessFlags.INSURER_ADMIN) {
    BalancerLib2.AssetBalancer storage balancer = _balancers[actuary];
    balancer.spConst = spConst;
    balancer.spFactor = spFactor;
  }

  function getActuaryGlobals(address actuary) external view returns (uint256, uint32) {
    BalancerLib2.AssetBalancer storage balancer = _balancers[actuary];
    return (balancer.spConst, balancer.spFactor);
  }

  function setAssetConfig(
    address actuary,
    address asset,
    BalancerLib2.AssetConfig memory ac
  ) external aclHas(AccessFlags.INSURER_ADMIN) {
    CalcConfigValue c = ac.calc;
    uint16 flags = c.flags() & (CalcConfig.BF_FINISHED | CalcConfig.BF_EXTERNAL);
    Value.require(c.price() == 0);

    uint144 price;
    if (asset == collateral()) {
      Value.require(flags == CalcConfig.BF_EXTERNAL);
      price = uint144(WadRayMath.WAD);
    } else {
      Value.require(flags == 0);
      if (actuary == address(0)) {
        Value.require(asset == address(0));
      } else {
        _ensureActuary(actuary);

        CalcConfigValue cv = _balancers[actuary].configs[asset].calc;
        Value.require(ac.calc.isSuspended() == cv.isSuspended());
        price = cv.price();
      }
    }
    ac.calc = ac.calc.setPrice(price);

    _balancers[actuary].configs[asset] = ac;
  }

  function getAssetConfig(address actuary, address asset) external view returns (BalancerLib2.AssetConfig memory) {
    return _balancers[actuary].configs[asset];
  }

  function getActuaryState(address actuary) external view returns (ActuaryState) {
    return _configs[actuary].state;
  }

  event ActuaryTokenPaused(address indexed actuary, address indexed token, bool paused);

  function setPaused(
    address actuary,
    address token,
    bool paused
  ) external onlyEmergencyAdmin {
    if (actuary == address(0)) {
      TokenState storage state = _tokens[token];
      uint8 flags = state.flags;
      state.flags = paused ? flags | TS_SUSPENDED : flags & ~TS_SUSPENDED;
    } else {
      ActuaryConfig storage config = _configs[actuary];

      if (token == address(0)) {
        State.require(config.state >= ActuaryState.Active);

        config.state = paused ? ActuaryState.Paused : ActuaryState.Active;
      } else {
        State.require(config.state > ActuaryState.Unknown);

        BalancerLib2.AssetConfig storage ac = _balancers[actuary].configs[token];
        ac.calc = ac.calc.setSuspended(paused);
      }
    }
    emit ActuaryTokenPaused(actuary, token, paused);
  }

  function isPaused(address actuary, address token) public view returns (bool) {
    if (_tokens[token].flags & TS_SUSPENDED != 0) {
      return true;
    }

    ActuaryState state = _configs[actuary].state;
    return state == ActuaryState.Paused || _balancers[actuary].configs[token].calc.isSuspended();
  }

  event ActuarySourceAdded(address indexed actuary, address indexed source, address indexed token);
  event ActuarySourceRemoved(address indexed actuary, address indexed source, address indexed token);

  function registerPremiumSource(address source, bool register) external override {
    address actuary = msg.sender;

    ActuaryConfig storage config = _configs[actuary];
    State.require(config.state >= ActuaryState.Active);

    if (register) {
      Value.require(source != address(0) && source != collateral());
      // NB! a source will actually be added on non-zero rate only
      State.require(config.sourceToken[source] == address(0));

      address targetToken = IPremiumSource(source).premiumToken();
      _ensureNonCollateral(actuary, targetToken);
      _markTokenAsPresent(targetToken);
      config.sourceToken[source] = targetToken;
      _tokenActuaries[targetToken].add(actuary);

      BalancerLib2.AssetBalancer storage balancer = _balancers[actuary];
      BalancerLib2.AssetConfig memory ac = balancer.configs[address(0)];

      // re-activation should keep the price
      ac.calc = ac.calc.setPrice(balancer.configs[targetToken].calc.price());
      balancer.configs[targetToken] = ac;

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

  function _markTokenAsPresent(address token) private {
    Value.require(token != address(0));
    TokenState storage state = _tokens[token];
    uint8 flags = state.flags;
    if (flags & TS_PRESENT == 0) {
      state.flags = flags | TS_PRESENT;
      _knownTokens.push(token);
    }
  }

  function _addPremiumSource(
    ActuaryConfig storage config,
    BalancerLib2.AssetBalancer storage balancer,
    address targetToken,
    address source
  ) private {
    EnumerableSet.AddressSet storage activeSources = config.tokens[targetToken].activeSources;

    if (activeSources.add(source) && activeSources.length() == 1) {
      BalancerLib2.AssetBalance storage balance = balancer.balances[source];
      Sanity.require(balance.rateValue == 0);
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
        Sanity.require(rate == 0);
        balancerConfig.calc = balancerConfig.calc.setFinished();

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
    uint256 premium,
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
    uint96 lastRate = sBalance.rate;

    if (token == address(0)) {
      // this is a call from the actuary - it doesnt know about tokens, only about sources
      targetToken = config.sourceToken[source];
      Value.require(targetToken != address(0));

      premium -= sBalance.lastPremium;

      if (rate > 0 && sBalance.updatedAt == sBalance.updatedAt) {
        _addPremiumSource(config, balancer, targetToken, source);
      }
    } else {
      // this is a sync call from a user - who knows about tokens, but not about sources
      targetToken = token;
      rate = lastRate;
      premium = 0;
    }

    bool underprovisioned = !balancer.replenishAsset(
      BalancerLib2.ReplenishParams({actuary: actuary, source: source, token: targetToken, replenishFn: _replenishFn}),
      premium,
      uint96(rate),
      lastRate,
      checkSuspended
    );
    emit PremiumAllocationUpdated(actuary, source, token, premium, rate, underprovisioned);

    if (underprovisioned) {
      // the source failed to keep the promised premium rate, stop the rate to avoid false inflow
      sBalance.rate = 0;
    } else if (lastRate != rate) {
      Arithmetic.require((sBalance.rate = uint96(rate)) == rate);
    }
    sBalance.updatedAt = uint32(block.timestamp); // not needed
  }

  function premiumAllocationUpdated(
    address source,
    uint256 totalPremium,
    uint256 rate
  ) external override {
    ActuaryConfig storage config = _ensureActuary(msg.sender);
    Value.require(rate > 0);

    _premiumAllocationUpdated(config, msg.sender, source, address(0), totalPremium, rate, false);
  }

  function premiumAllocationFinished(address source, uint256 totalPremium) external override returns (uint256 premiumDebt) {
    ActuaryConfig storage config = _ensureActuary(msg.sender);
    Value.require(source != address(0));

    (address targetToken, BalancerLib2.AssetBalancer storage balancer, SourceBalance storage sBalance) = _premiumAllocationUpdated(
      config,
      msg.sender,
      source,
      address(0),
      totalPremium,
      0,
      false
    );

    premiumDebt = totalPremium - sBalance.lastPremium;
    // sBalance.lastPremium = totalPremium;

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

    SourceBalance storage sBalance = config.sourceBalances[params.source];
    {
      uint32 cur = uint32(block.timestamp);
      if (cur > sBalance.updatedAt) {
        expectedValue = uint256(cur - sBalance.updatedAt) * sBalance.rate;
        sBalance.updatedAt = cur;
      } else {
        Sanity.require(cur == sBalance.updatedAt);
        return (0, 0, 0);
      }
    }
    if (requiredValue < expectedValue) {
      requiredValue = expectedValue;
    }

    if (requiredValue > 0) {
      uint256 price = internalPriceOf(params.token);
      uint256 amount;

      (replenishedAmount, amount) = _collectPremium(params, requiredValue, price);
      amount -= replenishedAmount;
      replenishedValue = amount == 0 ? requiredValue : requiredValue - amount.wadMul(price);

      Arithmetic.require((sBalance.lastPremium += uint128(replenishedValue)) >= replenishedValue);
      // console.log('_replenishFn', sBalance.lastPremium, missingValue, requiredValue);
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
  ) private returns (uint256 collectedAmount, uint256 requiredAmount) {
    requiredAmount = requiredValue.wadDiv(price);
    collectedAmount = _collectPremiumCall(params.actuary, params.source, IERC20(params.token), requiredAmount, requiredValue);
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

  function assetBalance(address actuary, address asset) external view returns (AssetBalanceInfo memory r) {
    ActuaryConfig storage config = _configs[actuary];
    if (config.state > ActuaryState.Unknown) {
      (, r.amount, r.stravation, r.price, r.feeFactor, r.valueRate, r.since) = _balancers[actuary].assetState(asset);
    }
  }

  function _drawdownFlatLimit(
    address actuary,
    address account,
    uint256 maxDrawdown
  ) private view returns (uint256) {
    uint256 total = IERC20(actuary).totalSupply();
    return total == 0 ? maxDrawdown : (maxDrawdown * IERC20(actuary).balanceOf(account)).divUp(total);
  }

  function swapAsset(
    address actuary,
    address account,
    address recipient,
    uint256 valueToSwap,
    address targetToken,
    uint256 minAmount
  ) public onlyApprovedFor(account, APPROVE_SWAP) returns (uint256 tokenAmount) {
    _ensureActiveActuary(actuary);
    _ensureToken(targetToken);
    Value.require(recipient != address(0));

    uint256 fee;
    address burnReceiver;

    if (collateral() == targetToken) {
      (tokenAmount, fee) = _swapExtAsset(actuary, account, valueToSwap, minAmount);

      if (tokenAmount > 0) {
        if (fee == 0) {
          // use a direct transfer when no fees
          State.require(tokenAmount == valueToSwap);
          burnReceiver = recipient;
        } else {
          burnReceiver = address(this);
        }
      }
    } else {
      BalancerLib2.AssetBalancer storage balancer = _balancers[actuary];
      (tokenAmount, fee) = balancer.swapAsset(_replenishParams(actuary, targetToken), valueToSwap, minAmount);
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

  event FeeCollected(address indexed token, uint256 amount);

  function _addFee(
    ActuaryConfig storage,
    address targetToken,
    uint256 fee
  ) private {
    Arithmetic.require((_tokens[targetToken].collectedFees += uint128(fee)) >= fee);
    emit FeeCollected(targetToken, fee);
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

  function swapAssets(
    address actuary,
    address account,
    SwapInstruction[] calldata instructions
  ) external onlyApprovedFor(account, APPROVE_SWAP) returns (uint256[] memory tokenAmounts) {
    if (instructions.length <= 1) {
      // _ensureActiveActuary is applied inside swapToken invoked via _swapTokensOne
      return instructions.length == 0 ? tokenAmounts : _swapTokensOne(actuary, account, instructions[0]);
    }

    _ensureActiveActuary(actuary);

    uint256[] memory fees;
    (tokenAmounts, fees) = _swapTokens(actuary, account, instructions);
    ActuaryConfig storage config = _configs[actuary];

    for (uint256 i = 0; i < instructions.length; i++) {
      address targetToken = instructions[i].targetToken;

      SafeERC20.safeTransfer(IERC20(targetToken), instructions[i].recipient, tokenAmounts[i]);

      if (fees[i] > 0) {
        _addFee(config, targetToken, fees[i]);
      }
    }
  }

  function _swapTokens(
    address actuary,
    address account,
    SwapInstruction[] calldata instructions
  ) private returns (uint256[] memory tokenAmounts, uint256[] memory fees) {
    BalancerLib2.AssetBalancer storage balancer = _balancers[actuary];

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
        // drawdown is only handled once per batch to incease cost of multiple drawdowns
        if (totalExtValue > 0) {
          continue;
        }

        (tokenAmounts[i], fees[i]) = _swapExtTokenInBatch(instructions[i], actuary, account, total);

        if (tokenAmounts[i] > 0) {
          totalExtValue += instructions[i].valueToSwap;
        }
      } else {
        (tokenAmounts[i], fees[i]) = _swapTokenInBatch(balancer, instructions[i], params, total);

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
    BalancerLib2.ReplenishParams memory params,
    Balances.RateAcc memory total
  ) private returns (uint256 tokenAmount, uint256 fee) {
    params.token = instruction.targetToken;
    (tokenAmount, fee, ) = balancer.swapAssetInBatch(params, instruction.valueToSwap, instruction.minAmount, total);
  }

  function _swapExtTokenInBatch(
    SwapInstruction calldata instruction,
    address actuary,
    address account,
    Balances.RateAcc memory total
  ) private returns (uint256 tokenAmount, uint256 fee) {
    (, uint256 drawdownBalance) = IPremiumActuary(actuary).collectDrawdownPremium();
    if (drawdownBalance > 0) {
      uint256 drawdownLimit = _drawdownFlatLimit(actuary, account, drawdownBalance);
      BalancerLib2.AssetBalancer storage balancer = _balancers[actuary];

      (tokenAmount, fee) = balancer.swapExternalAssetInBatch(
        instruction.targetToken,
        instruction.valueToSwap,
        instruction.minAmount,
        drawdownBalance,
        drawdownLimit,
        total
      );

      Sanity.require(drawdownBalance >= tokenAmount);
    }
  }

  function _swapExtAsset(
    address actuary,
    address account,
    uint256 valueToSwap,
    uint256 minAmount
  ) private returns (uint256 tokenAmount, uint256 fee) {
    (, uint256 availDrawdown) = IPremiumActuary(actuary).collectDrawdownPremium();
    if (availDrawdown > 0) {
      uint256 drawdownLimit = _drawdownFlatLimit(actuary, account, availDrawdown);
      BalancerLib2.AssetBalancer storage balancer = _balancers[actuary];

      (tokenAmount, fee) = balancer.swapExternalAsset(collateral(), valueToSwap, minAmount, availDrawdown, drawdownLimit);
    }
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
      Arithmetic.require((v = vSum + v) <= max);
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
    SwapInstruction calldata instruction
  ) private returns (uint256[] memory tokenAmounts) {
    tokenAmounts = new uint256[](1);

    tokenAmounts[0] = swapAsset(actuary, account, instruction.recipient, instruction.valueToSwap, instruction.targetToken, instruction.minAmount);
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

  function setApprovalsFor(
    address operator,
    uint256 access,
    bool approved
  ) external {
    Value.require(operator != address(0));
    if (approved) {
      _approvals[msg.sender][operator] |= access;
    } else {
      _approvals[msg.sender][operator] &= ~access;
    }
  }

  function isApprovedFor(
    address account,
    address operator,
    uint256 access
  ) public view returns (bool) {
    return _approvals[account][operator] & access == access;
  }

  function _onlyApprovedFor(address account, uint256 access) private view {
    Access.require(account == msg.sender || isApprovedFor(account, msg.sender, access));
  }

  modifier onlyApprovedFor(address account, uint256 access) {
    _onlyApprovedFor(account, access);
    _;
  }
}
