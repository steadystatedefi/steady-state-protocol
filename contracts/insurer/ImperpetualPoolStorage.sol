// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/ERC20BalancelessBase.sol';
import '../libraries/Balances.sol';
import './WeightedPoolStorage.sol';

abstract contract ImperpetualPoolStorage is WeightedPoolStorage, ERC20BalancelessBase, IExcessHandler {
  using WadRayMath for uint256;

  uint128 private _totalSupply;
  uint256 internal _burntPremium;
  uint256 internal _lostCoverage;
  uint256 internal _drawndownValue;

  function totalSupply() public view override returns (uint256) {
    return _totalSupply;
  }

  function _mint(
    address account,
    uint256 amount256,
    uint256 value
  ) internal {
    uint128 amount = uint128(amount256);

    emit Transfer(address(0), account, amount);
    _totalSupply += amount;
    value;

    amount += _balances[account].balance;
    require(amount == (_balances[account].balance = uint128(amount)));
  }

  function _burn(
    address account,
    uint256 amount256,
    uint256 value
  ) internal {
    uint128 amount = uint128(amount256);
    emit Transfer(account, address(0), amount);
    _balances[account].balance -= amount;
    unchecked {
      // overflow doesnt matter much here
      _balances[account].extra += uint128(value);
    }
    _totalSupply -= amount;
  }
}
