// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../dependencies/openzeppelin/contracts/Address.sol';
import '../dependencies/openzeppelin/contracts/IERC20.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IInsuredPool.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/tokens/ERC1363ReceiverBase.sol';

abstract contract InsuredBalancesBase is ERC1363ReceiverBase {
  using WadRayMath for uint256;

  address private _collateral;

  constructor(address collateral_) {
    _collateral = collateral_;
  }

  function _initialize(address collateral_) internal {
    _collateral = collateral_;
  }

  function collateral() external view returns (address) {
    return _collateral;
  }

  modifier onlyCollateralFund() {
    require(msg.sender == _collateral);
    _;
  }

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
      require(IERC20(_collateral).transfer(from, unusedAmount));
    }
  }

  // TODO unitize?
  struct PremiumBalance {
    uint96 accum;
    uint64 rate;
    uint64 locked;
    uint32 updatedAt;
  }
  mapping(address => PremiumBalance) private _balances;
  mapping(address => mapping(address => uint64)) private _lockedBalances;

  struct TotalBalance {
    uint128 accum;
    uint96 rate;
    uint32 updatedAt;
  }
  TotalBalance private _totals;

  function _invest(
    address investor,
    uint256 amount,
    uint256 minAmount,
    uint256 minPremiumRate,
    address holder
  ) private returns (uint256 unusedAmount, uint256) {
    unusedAmount = amount;
    uint64 premiumRate;
    (amount, premiumRate) = internalInvest(amount, minAmount, minPremiumRate);
    require(amount >= minAmount);
    if (amount == 0) {
      return (unusedAmount, 0);
    }

    require(premiumRate > 0 && premiumRate >= minPremiumRate);

    unusedAmount -= amount;
    {
      TotalBalance memory b = _syncTotalBalance();
      uint256 acc = amount + b.rate;
      require(acc <= type(uint96).max);
      b.rate = uint96(acc);
      _totals = b;
    }

    amount = amount.wadMul(premiumRate);
    if (amount == 0) {
      return (unusedAmount, 0);
    }

    require(amount <= type(uint64).max);
    uint64 mintedAmount = uint64(amount);

    if (holder != address(0)) {
      _lockedBalances[holder][investor] += mintedAmount;
      _balances[investor].locked += mintedAmount;
    } else {
      PremiumBalance memory b = _syncBalance(investor);
      b.rate += mintedAmount;
      _balances[investor] = b;
    }

    return (unusedAmount, mintedAmount);
  }

  function _syncBalance(address account) private view returns (PremiumBalance memory b) {
    b = _balances[account];
    if (b.rate > 0) {
      uint256 amount = internalRateAdjustment(b.rate, b.updatedAt) + b.accum;
      require(amount <= type(uint96).max);
      b.accum = uint96(amount);
    }
    b.updatedAt = uint32(block.timestamp);
    return b;
  }

  function _syncTotalBalance() private view returns (TotalBalance memory b) {
    b = _totals;
    if (b.rate > 0) {
      uint256 amount = internalRateAdjustment(b.rate, b.updatedAt) + b.accum;
      require(amount <= type(uint96).max);
      b.accum = uint96(amount);
    }
    b.updatedAt = uint32(block.timestamp);
    return b;
  }

  function internalRateAdjustment(uint256 rate, uint32 updatedAt) internal view virtual returns (uint256) {
    return (block.timestamp - updatedAt) * rate;
  }

  function internalInvest(
    uint256 amount,
    uint256 minAmount,
    uint256 minPremiumRate
  ) internal virtual returns (uint256 availableAmount, uint64 premiumRate);

  function balanceOf(address account) public view returns (uint256) {
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
    PremiumBalance memory b = _syncBalance(account);
    return (b.rate, b.locked, b.accum);
  }

  function holdedBalanceOf(address account, address holder) public view returns (uint256) {
    return _lockedBalances[holder][account];
  }

  function totalSupply() public view returns (uint256) {
    return _totals.rate;
  }

  function totalPremium() public view returns (uint256 rate, uint256 demand) {
    TotalBalance memory b = _syncTotalBalance();
    return (b.rate, b.accum);
  }

  // TODO function internalReconcile() internal {}

  function internalAddHolder(address account) internal {
    require(Address.isContract(account));
    uint32 updatedAt = _balances[account].updatedAt;
    if (updatedAt == type(uint32).max) return;

    require(updatedAt == 0);
    _balances[account] = PremiumBalance(0, 0, 0, type(uint32).max);
  }

  function isHolder(address account) internal view returns (bool) {
    return _balances[account].updatedAt == type(uint32).max;
  }

  function isHolder(PremiumBalance memory b) private pure returns (bool) {
    return b.updatedAt == type(uint32).max;
  }

  function internalTransfer(
    address from,
    address to,
    uint256 amount
  ) internal {
    PremiumBalance memory b = _syncBalance(from);
    if (isHolder(b)) {
      require(msg.sender == from);
      _lockedBalances[from][to] = uint64(uint256(_lockedBalances[from][to]) - amount);
    } else {
      b.rate = uint64(uint256(b.rate) - amount);
      _balances[from] = b;
    }

    b = _syncBalance(to);
    if (isHolder(b)) {
      amount += _lockedBalances[to][from];
      require(amount <= type(uint64).max);
      _lockedBalances[to][from] = uint64(amount);
    } else {
      amount += b.rate;
      require(amount <= type(uint64).max);
      b.rate = uint64(amount);
      _balances[to] = b;
    }
  }
}
