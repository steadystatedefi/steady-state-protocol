// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/math/WadRayMath.sol';
import '../interfaces/IInsurerPool.sol';
import '../insurance/InsurancePoolBase.sol';

import 'hardhat/console.sol';

// mints fix-yeild non-transferrable token
abstract contract DirectInsurerPool is InsurancePoolBase {
  using WadRayMath for uint256;

  uint256 private immutable _yeildRate;

  constructor(uint256 yeildRate) {
    require(yeildRate > 0);
    _yeildRate = yeildRate;
  }

  struct InsuredEntry {
    uint8 index;
    uint32 version;
    uint32 discontinuedAt;
    uint112 totalCoverage;
  }

  mapping(address => InsuredEntry) private _insureds;
  uint256 private _stopMask;
  uint256 private _insuredCount;

  struct InsuredVersion {
    uint64 scale;
    uint32 since;
  }
  mapping(uint16 => InsuredVersion[]) private _versions;

  mapping(address => uint256) private _investMasks;
  struct InvestorEntry {
    uint96 amount;
    uint120 accPremium;
    uint32 lastUpdatedAt;
  }
  mapping(address => InvestorEntry) private _investors;
  struct Investment {
    uint112 amount;
    // version
    uint112 totalCoverage;
  }
  mapping(address => mapping(uint16 => Investment)) private _investments;

  // function internalSlashCoverage

  // function internalAddCoverage(address investor, address insured, uint128 amount, uint128 minPremiumRate) internal
  //   returns (uint256 remainingAmount, uint256 mintedAmount)
  // {
  //   InsuredEntry memory entry = _insureds[insured];
  //   InvestorEntry memory invest = _investors[investor];

  //   if (invest.amount == 0) {
  //     uint256 mask = uint256(1)<<(entry.index - 1);
  //     _investMasks[investor] |= mask;
  //   }

  //   // uint256 premiumRate;
  //   // (remainingAmount, premiumRate) = IInsuredPool(insured).addDirectCoverage(amount, minPremiumRate);
  //   // amount -= uint128(remainingAmount);
  //   // mintedAmount = premiumRate * amount / _yeildRate;

  //   // invest.amount += uint128(mintedAmount);
  //   // _investments[investor][entry.index].amount += uint128(mintedAmount);

  // }
}
