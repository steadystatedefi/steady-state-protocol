// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/ERC20BalancelessBase.sol';
import '../tools/Errors.sol';
import '../libraries/Balances.sol';
import './WeightedPoolBase.sol';

abstract contract ImperpetualPoolStorage is WeightedPoolBase, ERC20BalancelessBase {
  using Math for uint256;
  using WadRayMath for uint256;

  mapping(address => uint256) internal _insuredBalances; // [insured]

  uint128 private _totalSupply;

  uint128 internal _burntDrawdown;
  uint128 internal _burntPremium;

  /// @dev decreased on losses (e.g. premium underpaid or collateral loss), increased on external value streams, e.g. collateral yield
  int128 internal _valueAdjustment;

  function totalSupply() public view override(IERC20, WeightedPoolBase) returns (uint256) {
    return _totalSupply;
  }

  function _mint(
    address account,
    uint256 amount256,
    uint256 value
  ) internal {
    value;
    uint128 amount = amount256.asUint128();

    emit Transfer(address(0), account, amount);
    _totalSupply += amount;
    _balances[account].balance += amount;
  }

  function _burn(
    address account,
    uint256 amount256,
    uint256 value
  ) internal {
    uint128 amount = amount256.asUint128();

    emit Transfer(account, address(0), amount);
    _balances[account].balance -= amount;
    unchecked {
      // overflow doesnt matter much here
      _balances[account].extra += uint128(value);
    }
    _totalSupply -= amount;
  }
}
