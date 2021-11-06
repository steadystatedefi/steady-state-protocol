// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../dependencies/openzeppelin/contracts/Address.sol';
import '../dependencies/openzeppelin/contracts/IERC20.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/tokens/ERC1363ReceiverBase.sol';
import '../interfaces/IInsuredPool.sol';

abstract contract InsuredPoolBase is IInsuredPool {}
