// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './WeightedPoolExtension.sol';
import './PerpetualPoolBase.sol';

/// @dev NB! MUST HAVE NO STORAGE
contract PerpetualPoolExtension is WeightedPoolExtension {
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using Balances for Balances.RateAcc;

  constructor(
    IAccessController acl,
    uint256 unitSize,
    address collateral_
  ) WeightedPoolConfig(acl, unitSize, collateral_) {}

  function internalTransferCancelledCoverage(
    address insured,
    uint256 payoutValue,
    uint256 advanceValue,
    uint256 recoveredValue,
    uint256 premiumDebt
  ) internal override returns (uint256) {
    uint256 deficitValue;
    uint256 toPay = payoutValue;
    unchecked {
      if (toPay >= advanceValue) {
        toPay -= advanceValue;
        advanceValue = 0;
      } else {
        deficitValue = (advanceValue -= toPay);
        toPay = 0;
      }

      if (toPay >= premiumDebt) {
        toPay -= premiumDebt;
      } else {
        deficitValue += (premiumDebt - toPay);
      }
    }

    uint256 collateralAsPremium;

    if (deficitValue > 0) {
      // toPay is zero
      toPay = transferAvailableCollateralFrom(insured, address(this), deficitValue);
      if (toPay > advanceValue) {
        unchecked {
          collateralAsPremium = toPay - advanceValue;
        }
        toPay = advanceValue;
      }
      recoveredValue += toPay;
    } else if (toPay > 0) {
      transferCollateral(insured, toPay);
    }

    // this call is to consider / reinvest the released funds
    PerpetualPoolBase(address(this)).updateCoverageOnCancel(payoutValue + premiumDebt, recoveredValue, collateralAsPremium);
    // ^^ avoids code to be duplicated within WeightedPoolExtension to reduce contract size

    return payoutValue;
  }

  function internalTransferDemandedCoverage(
    address insured,
    uint256 receivedCoverage,
    DemandedCoverage memory
  ) internal override returns (uint256) {
    if (receivedCoverage > 0) {
      transferCollateral(insured, receivedCoverage);
    }
    return receivedCoverage;
  }
}
