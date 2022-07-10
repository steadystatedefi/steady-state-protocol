// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../access/interfaces/IAccessController.sol';
import '../interfaces/IInsuredPoolInit.sol';
import '../interfaces/IWeightedPool.sol';
import '../interfaces/IPremiumFundInit.sol';
import '../interfaces/ICollateralFundInit.sol';
import '../insurer/WeightedPoolConfig.sol';

library ProxyTypes {
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

  function collateralFundInit() internal pure returns (bytes memory) {
    return abi.encodeWithSelector(ICollateralFundInit.initializeCollateralFund.selector);
  }
}
