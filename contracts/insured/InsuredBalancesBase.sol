// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';
import '../tools/tokens/IERC20.sol';
import '../interfaces/IInsurancePool.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IInsuredPool.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/tokens/ERC1363ReceiverBase.sol';

abstract contract InsuredBalancesBase is IInsurancePool, ERC1363ReceiverBase {
  using WadRayMath for uint256;

  address private _collateral;

  constructor(address collateral_) {
    _collateral = collateral_;
  }

  function _initialize(address collateral_) internal {
    _collateral = collateral_;
  }

  function collateral() public view override returns (address) {
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
    uint112 accum;
    uint80 rate;
    uint32 updatedAt;
    uint16 status;
    //    uint16 reserved0;
  }
  mapping(address => PremiumBalance) private _balances;

  struct LockedAccountBalance {
    uint80 locked;
  }
  mapping(address => LockedAccountBalance) private _locks;
  mapping(address => mapping(address => uint80)) private _lockedBalances;

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

    require(amount <= type(uint80).max);
    uint80 mintedAmount = uint80(amount);

    if (holder != address(0)) {
      require(internalIsAllowedHolder(_balances[holder].status));
      _lockedBalances[holder][investor] += mintedAmount;
      _locks[investor].locked += mintedAmount;
    } else {
      PremiumBalance memory b = _syncBalance(investor);
      b.rate += mintedAmount;
      _balances[investor] = b;
    }

    return (unusedAmount, mintedAmount);
  }

  function internalIsAllowedHolder(uint16 status) internal view virtual returns (bool);

  function _syncBalance(address account) private view returns (PremiumBalance memory b) {
    b = _balances[account];
    if (b.rate > 0) {
      uint256 amount = internalRateAdjustment(b.rate, b.updatedAt) + b.accum;
      require(amount <= type(uint112).max);
      b.accum = uint112(amount);
    }
    b.updatedAt = uint32(block.timestamp);
    return b;
  }

  function _syncTotalBalance() private view returns (TotalBalance memory b) {
    b = _totals;
    if (b.rate > 0) {
      uint256 amount = internalRateAdjustment(b.rate, b.updatedAt) + b.accum;
      require(amount <= type(uint128).max);
      b.accum = uint128(amount);
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
    return (b.rate, _locks[account].locked, b.accum);
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

  function internalSetServiceAccountStatus(address account, uint16 status) internal virtual {
    require(status > 0);
    PremiumBalance memory b = _balances[account];
    if (b.status == 0) {
      require(b.updatedAt == 0);
      require(Address.isContract(account));
    }

    _balances[account].status = status;
  }

  function getAccountStatus(address account) internal view virtual returns (uint16) {
    return _balances[account].status;
  }

  function isHolder(PremiumBalance memory b) private pure returns (bool) {
    return b.status > 0;
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
      require(internalIsAllowedHolder(b.status));

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
