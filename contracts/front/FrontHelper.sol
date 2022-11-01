// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/Errors.sol';
import '../tools/tokens/IERC20Details.sol';
import '../interfaces/IProxyFactory.sol';
import '../interfaces/IInsuredPool.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IPremiumActuary.sol';
import '../interfaces/IPremiumSource.sol';
import '../interfaces/IPremiumCollector.sol';
import '../interfaces/IManagedCollateralCurrency.sol';
import '../funds/interfaces/ICollateralFund.sol';
import '../premium/interfaces/IPremiumFund.sol';
import '../access/AccessHelper.sol';
import '../governance/interfaces/IApprovalCatalog.sol';
import '../insured/InsuredPoolBase.sol';

contract FrontHelper is AccessHelper {
  constructor(IAccessController acl) AccessHelper(acl) {}

  struct CollateralFundInfo {
    address fund;
    address collateral;
    address yieldDistributor;
    address[] assets;
  }

  struct InsurerInfo {
    address pool;
    address collateral;
    address premiumFund;
    bool chartered;
  }

  // slither-disable-next-line calls-loop
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
      address cc = fund.collateral();
      collateralFunds[i].collateral = cc;
      collateralFunds[i].assets = fund.assets();
      collateralFunds[i].yieldDistributor = IManagedCollateralCurrency(cc).borrowManager();
    }

    list = ac.roleHolders(AccessFlags.INSURER_POOL_LISTING);

    insurers = new InsurerInfo[](list.length);
    for (uint256 i = list.length; i > 0; ) {
      i--;
      IInsurerPool insurer = IInsurerPool(insurers[i].pool = list[i]);
      insurers[i].collateral = insurer.collateral();
      insurers[i].chartered = insurer.charteredDemand();
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

  function getPremiumFundInfo(address[] calldata premiumFunds) external view returns (PremiumFundInfo[] memory funds) {
    funds = new PremiumFundInfo[](premiumFunds.length);
    for (uint256 i = premiumFunds.length; i > 0; ) {
      i--;
      funds[i] = _getPremiumFundInfo(IPremiumFund(premiumFunds[i]));
    }
  }

  // slither-disable-next-line calls-loop
  function _getPremiumFundInfo(IPremiumFund fund) private view returns (PremiumFundInfo memory info) {
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

  // slither-disable-next-line calls-loop
  function _getDistributorTokenInfo(IPremiumFund fund, address token) private view returns (PremiumTokenInfo memory info) {
    info.token = token;

    address[] memory actuaries = fund.actuariesOfToken(token);

    if (actuaries.length > 0) {
      info.actuaries = new PremiumActuaryInfo[](actuaries.length);

      for (uint256 i = actuaries.length; i > 0; ) {
        i--;
        address[] memory sources = fund.activeSourcesOf(actuaries[i], token);
        info.actuaries[i] = PremiumActuaryInfo({actuary: actuaries[i], activeSources: sources});
      }
    }
  }

  // slither-disable-next-line calls-loop
  function batchBalanceOf(address[] calldata users, address[] calldata tokens) external view returns (uint256[] memory balances) {
    balances = new uint256[](users.length * tokens.length);

    for (uint256 i = 0; i < users.length; i++) {
      for (uint256 j = 0; j < tokens.length; j++) {
        balances[i * tokens.length + j] = IERC20(tokens[j]).balanceOf(users[i]);
      }
    }
  }

  struct TokenDetails {
    string symbol;
    string name;
    uint8 decimals;
  }

  // slither-disable-next-line calls-loop
  function batchTokenDetails(address[] calldata tokens) external view returns (TokenDetails[] memory details) {
    details = new TokenDetails[](tokens.length);

    for (uint256 j = 0; j < tokens.length; j++) {
      IERC20Details token = IERC20Details(tokens[j]);
      details[j] = TokenDetails({symbol: token.symbol(), name: token.name(), decimals: token.decimals()});
    }
  }

  function batchStatusOfInsured(address insured, address[] calldata insurers) external view returns (MemberStatus[] memory) {
    MemberStatus[] memory result = new MemberStatus[](insurers.length);
    for (uint256 i = insurers.length; i > 0; ) {
      i--;
      // slither-disable-next-line calls-loop
      result[i] = IInsurerPool(insurers[i]).statusOf(insured);
    }
    return result;
  }

  function batchBalancesOf(address account, address[] calldata insurers)
    external
    view
    returns (
      uint256[] memory values,
      uint256[] memory balances,
      uint256[] memory swappables
    )
  {
    values = new uint256[](insurers.length);
    balances = new uint256[](insurers.length);
    swappables = new uint256[](insurers.length);
    for (uint256 i = insurers.length; i > 0; ) {
      i--;
      // slither-disable-next-line calls-loop
      (values[i], balances[i], swappables[i]) = IInsurerPool(insurers[i]).balancesOf(account);
    }
  }

  function getInsuredReconcileInfo(address[] calldata insureds)
    external
    view
    returns (
      address[] memory premiumTokens,
      address[][] memory chartered,
      ReceivableByReconcile[][] memory receivables
    )
  {
    premiumTokens = new address[](insureds.length);
    chartered = new address[][](insureds.length);
    receivables = new ReceivableByReconcile[][](insureds.length);

    for (uint256 i = insureds.length; i > 0; ) {
      i--;
      address insured = insureds[i];
      // slither-disable-next-line calls-loop
      premiumTokens[i] = IPremiumSource(insured).premiumToken();

      // slither-disable-next-line calls-loop
      (, chartered[i]) = IInsuredPool(insured).getInsurers();

      address[] memory insurers = chartered[i];
      ReceivableByReconcile[] memory c = receivables[i] = new ReceivableByReconcile[](insurers.length);

      for (uint256 j = insurers.length; j > 0; ) {
        j--;
        // slither-disable-next-line calls-loop
        c[j] = IReconcilableInsuredPool(insured).receivableByReconcileWithInsurer(insurers[j]);
      }
    }
  }

  function getSwapInfo(
    address premiumFund,
    address actuary,
    address[] calldata assets
  ) public view returns (IPremiumFund.AssetBalanceInfo[] memory balances) {
    balances = new IPremiumFund.AssetBalanceInfo[](assets.length);
    for (uint256 i = assets.length; i > 0; ) {
      i--;
      // slither-disable-next-line calls-loop
      balances[i] = IPremiumFund(premiumFund).assetBalance(actuary, assets[i]);
    }
  }

  function syncSwapInfo(
    address premiumFund,
    address actuary,
    address[] calldata assets
  ) external returns (IPremiumFund.AssetBalanceInfo[] memory) {
    IPremiumFund(premiumFund).syncAssets(actuary, 0, assets);
    return getSwapInfo(premiumFund, actuary, assets);
  }

  struct InsuredCoverageInfo {
    uint256 receivableCoverage;
    uint256 demandedCoverage;
    uint256 providedCoverage;
    uint256 rate;
    uint256 accumulated;
    uint256 expectedPrepay;
  }

  function getInsuredCommonInfo(address[] calldata insureds, uint32 timeDelta) external view returns (InsuredCoverageInfo[] memory totals) {
    totals = new InsuredCoverageInfo[](insureds.length);

    for (uint256 i = insureds.length; i > 0; ) {
      i--;

      // slither-disable-next-line calls-loop
      (uint256 receivableCoverage, uint256 demandedCoverage, uint256 providedCoverage, uint256 rate, uint256 accumulated) = InsuredPoolBase(
        insureds[i]
      ).receivableByReconcileWithInsurers(0, 0);

      // slither-disable-next-line calls-loop
      totals[i].expectedPrepay = IPremiumCollector(insureds[i]).expectedPrepayAfter(timeDelta);
      totals[i].receivableCoverage = receivableCoverage;
      totals[i].demandedCoverage = demandedCoverage;
      totals[i].providedCoverage = providedCoverage;
      totals[i].rate = rate;
      totals[i].accumulated = accumulated;
    }
  }
}
