// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../tools/tokens/IERC20.sol';
import './IERC20Details.sol';

interface IERC20Detailed is IERC20, IERC20Details {}
