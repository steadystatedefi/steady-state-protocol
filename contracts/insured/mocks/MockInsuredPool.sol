// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../InsuredPoolBase.sol';

contract MockInsuredPool is InsuredPoolBase {
  constructor(
    address collateral_,
    uint256 totalDemand,
    uint64 premiumRate,
    uint128 minPerInsurer,
    uint8 decimals
  ) ERC20DetailsBase('InsuredPoolToken', '$DC', decimals) Collateralized(collateral_) InsuredPoolBase(totalDemand, premiumRate) {
    internalSetInsuredParams(InsuredParams({minPerInsurer: minPerInsurer}));
  }

  function externalGetAccountStatus(address account) external view returns (uint16) {
    return getAccountStatus(account);
  }

  function testCancelCoverageDemand(address insurer, uint64 unitCount) external {
    ICoverageDistributor(insurer).cancelCoverageDemand(address(this), unitCount, 0);
  }
}
