// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './InsuredBalancesBase.sol';

abstract contract InsuredCharterBase is InsuredBalancesBase {
  IInsurerPool[] private _chartereds;
}
