// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../InsuredPoolMonoRateBase.sol';

contract MockInsuredPool is InsuredPoolMonoRateBase {
  constructor(
    address collateral_,
    uint256 totalDemand,
    uint64 premiumRate,
    uint128 minPerInsurer,
    address premiumToken_
  ) InsuredPoolMonoRateBase(IAccessController(address(0)), collateral_) {
    _initializeERC20('InsuredPoolToken', '$DC', DECIMALS);
    _initializeCoverageDemand(totalDemand, premiumRate);
    _initializePremiumCollector(premiumToken_, 0, 0);
    internalSetInsuredParams(InsuredParams({minPerInsurer: minPerInsurer}));
    internalSetGovernor(msg.sender);
  }

  function externalGetAccountStatus(address account) external view returns (uint16) {
    return getAccountStatus(account);
  }

  function testCancelCoverageDemand(address insurer, uint64 unitCount) external {
    ICoverageDistributor(insurer).cancelCoverageDemand(address(this), unitCount, 0);
  }

  function internalPriceOf(address) internal pure override returns (uint256) {
    return WadRayMath.WAD;
  }

  function cancelJoin(IJoinable pool) external {
    pool.cancelJoin();
  }
}
