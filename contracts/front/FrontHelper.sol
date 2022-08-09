// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/Errors.sol';
import '../tools/tokens/IERC20Details.sol';
import '../interfaces/IProxyFactory.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IPremiumActuary.sol';
import '../funds/interfaces/ICollateralFund.sol';
import '../premium/interfaces/IPremiumFund.sol';
import '../access/AccessHelper.sol';
import '../governance/interfaces/IApprovalCatalog.sol';

contract FrontHelper is AccessHelper {
  constructor(IAccessController acl) AccessHelper(acl) {}

  struct CollateralFundInfo {
    address fund;
    address collateral;
    address[] assets;
  }

  struct InsurerInfo {
    address pool;
    address collateral;
    address premiumFund;
    bool chartered;
  }

  function getAddresses()
    external
    view
    returns (
      address accessController,
      address proxyCatalog,
      address approvalCatalog,
      address priceRouter,
      CollateralFundInfo[] memory collateralFunds,
      InsurerInfo[] memory insurers
    )
  {
    IAccessController ac = remoteAcl();
    accessController = address(ac);

    proxyCatalog = ac.getAddress(AccessFlags.PROXY_FACTORY);
    approvalCatalog = ac.getAddress(AccessFlags.APPROVAL_CATALOG);
    priceRouter = ac.getAddress(AccessFlags.PRICE_ROUTER);

    address[] memory list = ac.roleHolders(AccessFlags.COLLATERAL_FUND_LISTING);

    collateralFunds = new CollateralFundInfo[](list.length);
    for (uint256 i = list.length; i > 0; ) {
      i--;
      ICollateralFund fund = ICollateralFund(collateralFunds[i].fund = list[i]);
      // slither-ignore-next-line calls-loop
      collateralFunds[i].collateral = fund.collateral();
      // slither-ignore-next-line calls-loop
      collateralFunds[i].assets = fund.assets();
    }

    list = ac.roleHolders(AccessFlags.INSURER_POOL_LISTING);

    insurers = new InsurerInfo[](list.length);
    for (uint256 i = list.length; i > 0; ) {
      i--;
      IInsurerPool insurer = IInsurerPool(insurers[i].pool = list[i]);
      // slither-ignore-next-line calls-loop
      insurers[i].collateral = insurer.collateral();
      // slither-ignore-next-line calls-loop
      insurers[i].chartered = insurer.charteredDemand();
      // slither-ignore-next-line calls-loop
      insurers[i].premiumFund = IPremiumActuary(address(insurer)).premiumDistributor();
    }
  }

  struct PremiumFundInfo {
    address fund;
    PremiumTokenInfo[] knownTokens;
  }

  struct PremiumTokenInfo {
    address token;
    PremiumActuaryInfo[] actuaries;
  }

  struct PremiumActuaryInfo {
    address actuary;
    address[] activeSources;
  }

  function getDistribution(address[] calldata premiumFunds) external view returns (PremiumFundInfo[] memory funds) {
    funds = new PremiumFundInfo[](premiumFunds.length);
    for (uint256 i = premiumFunds.length; i > 0; ) {
      i--;
      funds[i] = _getDistributorInfo(IPremiumFund(premiumFunds[i]));
    }
  }

  function _getDistributorInfo(IPremiumFund fund) private view returns (PremiumFundInfo memory info) {
    info.fund = address(fund);

    address[] memory knownTokens = fund.knownTokens();

    if (knownTokens.length > 0) {
      info.knownTokens = new PremiumTokenInfo[](knownTokens.length);

      for (uint256 i = knownTokens.length; i > 0; ) {
        i--;
        info.knownTokens[i] = _getDistributorTokenInfo(fund, knownTokens[i]);
      }
    }
  }

  function _getDistributorTokenInfo(IPremiumFund fund, address token) private view returns (PremiumTokenInfo memory info) {
    info.token = token;

    // slither-ignore-next-line calls-loop
    address[] memory actuaries = fund.actuariesOfToken(token);

    if (actuaries.length > 0) {
      info.actuaries = new PremiumActuaryInfo[](actuaries.length);

      for (uint256 i = actuaries.length; i > 0; ) {
        i--;
        // slither-ignore-next-line calls-loop
        address[] memory sources = fund.activeSourcesOf(actuaries[i], token);
        info.actuaries[i] = PremiumActuaryInfo({actuary: actuaries[i], activeSources: sources});
      }
    }
  }

  function batchBalanceOf(address[] calldata users, address[] calldata tokens) external view returns (uint256[] memory balances) {
    balances = new uint256[](users.length * tokens.length);

    for (uint256 i = 0; i < users.length; i++) {
      for (uint256 j = 0; j < tokens.length; j++) {
        // slither-ignore-next-line calls-loop
        balances[i * tokens.length + j] = IERC20(tokens[j]).balanceOf(users[i]);
      }
    }
  }

  struct TokenDetails {
    string symbol;
    string name;
    uint8 decimals;
  }

  function batchTokenDetails(address[] calldata tokens) external view returns (TokenDetails[] memory details) {
    details = new TokenDetails[](tokens.length);

    for (uint256 j = 0; j < tokens.length; j++) {
      IERC20Details token = IERC20Details(tokens[j]);
      // slither-ignore-next-line calls-loop
      details[j] = TokenDetails({symbol: token.symbol(), name: token.name(), decimals: token.decimals()});
    }
  }
}
