// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/ERC1363ReceiverBase.sol';
import './InsurerJoinBase.sol';

abstract contract InsurerPoolBase is InsurerJoinBase, ERC1363ReceiverBase {
  address private _collateral;

  constructor(address collateral_) {
    _collateral = collateral_;
  }

  function collateral() public view override returns (address) {
    return _collateral;
  }

  modifier onlyCollateralFund() {
    require(msg.sender == _collateral);
    _;
  }

  function charteredDemand() public pure virtual override returns (bool);
}
