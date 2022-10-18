// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../access/interfaces/IAccessController.sol';
import '../interfaces/IInsuredPoolInit.sol';
import '../interfaces/IWeightedPool.sol';
import '../interfaces/IPremiumFundInit.sol';
import '../interfaces/ICollateralFundInit.sol';
import '../interfaces/ICollateralCurrencyInit.sol';
import '../interfaces/IReinvestorInit.sol';
import '../insurer/WeightedPoolConfig.sol';

/// @dev A set of proxy types and initializers.
library ProxyTypes {
  bytes32 internal constant APPROVAL_CATALOG = 'APPROVAL_CATALOG';
  bytes32 internal constant ORACLE_ROUTER = 'ORACLE_ROUTER';

  bytes32 internal constant INSURED_POOL = 'INSURED_POOL';

  function insuredInit(address governor) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IInsuredPoolInit.initializeInsured.selector, governor);
  }

  bytes32 internal constant PERPETUAL_INDEX_POOL = 'PERPETUAL_INDEX_POOL';
  bytes32 internal constant IMPERPETUAL_INDEX_POOL = 'IMPERPETUAL_INDEX_POOL';

  function weightedPoolInit(
    address governor,
    string calldata tokenName,
    string calldata tokenSymbol,
    WeightedPoolParams calldata params
  ) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IWeightedPoolInit.initializeWeighted.selector, governor, tokenName, tokenSymbol, params);
  }

  bytes32 internal constant PREMIUM_FUND = 'PREMIUM_FUND';

  function premiumFundInit() internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IPremiumFundInit.initializePremiumFund.selector);
  }

  bytes32 internal constant COLLATERAL_CCY = 'COLLATERAL_CCY';

  function collateralCurrencyInit(string memory name, string memory symbol) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(ICollateralCurrencyInit.initializeCollateralCurrency.selector, name, symbol);
  }

  bytes32 internal constant COLLATERAL_FUND = 'COLLATERAL_FUND';

  function collateralFundInit() internal pure returns (bytes memory) {
    return abi.encodeWithSelector(ICollateralFundInit.initializeCollateralFund.selector);
  }

  bytes32 internal constant REINVESTOR = 'REINVESTOR';

  function reinvestorInit() internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IReinvestorInit.initializeReinvestor.selector);
  }
}
