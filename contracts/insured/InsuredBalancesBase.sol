// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';
import '../tools/tokens/ERC20BalancelessBase.sol';
import '../libraries/Balances.sol';
import '../tools/tokens/IERC20.sol';
import '../interfaces/IInsurancePool.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IInsuredPool.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/tokens/ERC1363ReceiverBase.sol';
import '../insurance/InsurancePoolBase.sol';

abstract contract InsuredBalancesBase is InsurancePoolBase, ERC1363ReceiverBase, ERC20BalancelessBase
{
  using WadRayMath for uint256;
  using Balances for Balances.RateAcc;
  using Balances for Balances.RateAccWithUint16;

  function internalReceiveTransfer(
    address operator,
    address from,
    uint256 value,
    bytes calldata data
  ) internal override onlyCollateralFund {
    uint256 unusedAmount;

    if (data.length == 0) {
      (unusedAmount, ) = _invest(operator, value, 1, 0, address(0));
    } else if (abi.decode(data[:4], (bytes4)) == DInsuredPoolTransfer.addCoverage.selector) {
      (address account, uint256 minAmount, uint256 minPremiumRate, address insurerPool) = abi.decode(
        data[4:],
        (address, uint256, uint256, address)
      );

      uint256 mintedAmount;
      (unusedAmount, mintedAmount) = _invest(account, value, minAmount, minPremiumRate, insurerPool);

      if (mintedAmount > 0 && insurerPool != address(0)) {
        require(
          IERC1363Receiver(insurerPool).onTransferReceived(operator, from, mintedAmount, '') ==
            IERC1363Receiver.onTransferReceived.selector
        );
      }
    } else {
      revert();
    }

    if (unusedAmount > 0) {
      require(unusedAmount <= value);
      // return the unused portion
      // safeTransfer is not needed here as _collateral is a trusted contract.
      require(IERC20(collateral()).transfer(from, unusedAmount));
    }
  }

  mapping(address => Balances.RateAccWithUint16) private _balances;

  struct LockedAccountBalance {
    uint88 locked;
  }
  mapping(address => LockedAccountBalance) private _locks;
  mapping(address => mapping(address => uint88)) private _lockedBalances;

  Balances.RateAcc private _totals;

  function _invest(
    address investor,
    uint256 amount,
    uint256 minAmount,
    uint256 minPremiumRate,
    address holder
  ) private returns (uint256 unusedAmount, uint256) {
    unusedAmount = amount;
    uint64 premiumRate;
    (amount, premiumRate) = internalHandleDirectInvestment(amount, minAmount, minPremiumRate);
    if (amount == 0) {
      return (unusedAmount, 0);
    }
    require(amount >= minAmount);
    require(premiumRate > 0 && premiumRate >= minPremiumRate);

    amount = amount.wadMul(premiumRate);
    if (amount == 0) {
      return (unusedAmount, 0);
    }
    unusedAmount -= amount;

    internalMint(investor, amount, holder);
    return (unusedAmount, amount);
  }

  function internalMint(
    address account,
    uint256 amount,
    address holder
  ) internal virtual {
    require(amount <= type(uint88).max);
    uint88 mintedAmount = uint88(amount);

    if (holder != address(0)) {
      require(internalIsAllowedHolder(_balances[holder].extra));
      _lockedBalances[holder][account] += mintedAmount;
      _locks[account].locked += mintedAmount;
    } else {
      Balances.RateAccWithUint16 memory b = _syncBalance(account);
      b.rate += mintedAmount;
      _balances[account] = b;
    }

    // TODO adjust rate when payments stopped
    _totals = _totals.incRate(uint32(block.timestamp), amount);
  }

  function internalIsAllowedHolder(uint16 status) internal view virtual returns (bool);

  function _syncBalance(address account) private view returns (Balances.RateAccWithUint16 memory b) {
    // TODO adjust rate when payments stopped
    return _balances[account].sync(uint32(block.timestamp));
  }

  function internalHandleDirectInvestment(
    uint256 amount,
    uint256 minAmount,
    uint256 minPremiumRate
  ) internal virtual returns (uint256 availableAmount, uint64 premiumRate);

  function balanceOf(address account) public view override returns (uint256) {
    return _balances[account].rate;
  }

  function balancesOf(address account)
    public
    view
    returns (
      uint256 available,
      uint256 locked,
      uint256 premium
    )
  {
    Balances.RateAccWithUint16 memory b = _syncBalance(account);
    return (b.rate, _locks[account].locked, b.accum);
  }

  function holdedBalanceOf(address account, address holder) public view returns (uint256) {
    return _lockedBalances[holder][account];
  }

  function totalSupply() public view override returns (uint256) {
    return _totals.rate;
  }

  function totalPremium() public view returns (uint256 rate, uint256 demand) {
    Balances.RateAcc memory b = _totals.sync(uint32(block.timestamp));
    return (b.rate, b.accum);
  }

  // TODO function internalReconcile() internal {}

  function internalSetServiceAccountStatus(address account, uint16 status) internal virtual {
    require(status > 0);
    Balances.RateAccWithUint16 memory b = _balances[account];
    if (b.extra == 0) {
      require(Address.isContract(account));
    }

    _balances[account].extra = status;
  }

  function getAccountStatus(address account) internal view virtual returns (uint16) {
    return _balances[account].extra;
  }

  function isHolder(Balances.RateAccWithUint16 memory b) private pure returns (bool) {
    return b.extra > 0;
  }

  function internalTransfer(
    address from,
    address to,
    uint256 amount
  ) internal {
    Balances.RateAccWithUint16 memory b = _syncBalance(from);
    if (isHolder(b) && msg.sender == from) {
      // can only be done by a direct call of a holder
      _lockedBalances[from][to] = uint88(_lockedBalances[from][to] - amount);
    } else {
      b.rate = uint88(b.rate - amount);
      _balances[from] = b;
    }

    b = _syncBalance(to);
    if (isHolder(b)) {
      require(internalIsAllowedHolder(b.extra));

      amount += _lockedBalances[to][from];
      require(amount == (_lockedBalances[to][from] = uint88(amount)));
    } else {
      amount += b.rate;
      require(amount == (b.rate = uint88(amount)));
      _balances[to] = b;
    }
  }

    function transferBalance(
    address sender,
    address recipient,
    uint256 amount
  ) internal override {

  }
}
