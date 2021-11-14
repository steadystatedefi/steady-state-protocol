// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/IERC1363.sol';
import './ICollateralized.sol';

interface IInsurancePool is ICollateralized, IERC1363Receiver {
  // TODO function poolType()
}
