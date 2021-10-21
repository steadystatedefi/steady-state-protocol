// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

interface IInsurerPool {
  /// @dev address of the collateral fund and coverage token ($CC)
  function collateral() external view returns (address);

  /// @dev size of collateral allocation chunk made by this pool
  function coverageUnitSize() external view returns (uint256);

  /// @dev ERC1363-like receiver, invoked by the collateral fund for transfers/investments from user.
  function onTransferReceived(
    address operator,
    address from,
    uint256 value,
    bytes memory data
  ) external returns (bytes4);

  /// @dev initiates evaluation of the insured pool by this insurer. May involve governance activities etc.
  /// IInsuredPool.joinProcessed will be called after the decision is made.
  function requestJoin(address insured) external;

  /// @dev can only be called by the collateral fund, when
  function onCoverageDeclined(address insured) external;

  /// @dev indicates how the demand from insured pools is handled:
  /// * Chartered demand will be allocated without calling IInsuredPool, coverage units can be partially filled in.
  /// * Non-chartered (potential) demand can only be allocated after calling IInsuredPool.tryAddCoverage first, units can only be allocated in full.
  function charteredDemand() external view returns (bool);

  /// @dev can only be called by an accepted insured pool, adds demand for coverage
  function addCoverageDemand(CoverageUnitBatch[] calldata batches) external;

  /// @dev can only be called by an accepted insured pool, cancels only empty coverage units, returns number of cancelled units
  function cancelCoverageDemand(uint256 unitCount) external returns (uint256 cancelledUnits);

  /// @dev returns coverage info for the insurer
  function getCoverageDemand(address insured) external view returns (DemandedCoverage memory);

  /// @dev when charteredDemand is true and insured has incomplete demand, then this function will transfer $CC collected for the insured
  /// when charteredDemand is false or demand was fulfilled, then there is no need to call this function.
  function receiveDemandedCoverage(address insured)
    external
    view
    returns (uint256 receivedCoverage, DemandedCoverage memory);
}

struct DemandedCoverage {
  uint256 totalDemand; // total demand added by insured to insurer
  uint256 totalCovered; // total coverage allocated by insured to insurer (can not exceed total demand)
  uint256 premiumRate; // total premium rate accumulated accross all units filled-in with coverage
  uint256 premiumAccumulatedRate; // time-cumulated of premiumRate
}

struct CoverageUnitBatch {
  uint256 unitCount; // number of units demanded, size of unit is implicit (by insurer pool)
  uint256 premiumRate; // premiumRate in RAYs for coverage provided for these units, may vary between units
}

interface IInsuredPool {
  /// @dev address of the collateral fund and coverage token ($CC)
  function collateral() external view returns (address);

  /// @dev is called by insurer from or after requestJoin() to inform this insured pool if it was accepted or not
  function joinProcessed(bool accepted) external;

  /// @dev WIP called by insurer pool to cover full units ad-hoc, is used by direct insurer pools to facilitate user's choice
  function tryAddCoverage(uint256 unitCount, DemandedCoverage calldata current) external returns (uint256 addedCount);
}
