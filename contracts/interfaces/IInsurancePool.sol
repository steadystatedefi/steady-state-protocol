// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/IERC1363.sol';

interface IInsurancePool is IERC1363Receiver {
  /// @dev address of the collateral fund and coverage token ($CC)
  function collateral() external view returns (address);

  // TODO function poolType()
}
