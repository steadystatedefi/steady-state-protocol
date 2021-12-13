// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';
import '../tools/tokens/ERC20BalancelessBase.sol';
import '../libraries/Balances.sol';
import '../tools/tokens/IERC20.sol';
import '../interfaces/IPremiumCalculator.sol';
import '../interfaces/IInsurancePool.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IInsuredPool.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/tokens/ERC1363ReceiverBase.sol';
import '../insurance/InsurancePoolBase.sol';

import 'hardhat/console.sol';

// Calculates retroactive premium paid by Insured to Insurer over-time.
// Insured pool tokens = investment * premium rate (e.g $1000 @ 5% premium = 50 tokens)
abstract contract InsuredBalancesBase is
  InsurancePoolBase,
  ERC1363ReceiverBase,
  ERC20BalancelessBase,
  IInsuredEvents,
  IPremiumCalculator
{
  using WadRayMath for uint256;
  using Balances for Balances.RateAcc;
  using Balances for Balances.RateAccWithUint16;

  mapping(address => Balances.RateAccWithUint16) private _balances;

  struct HoldedBalance {
    uint88 balance;
  }
  mapping(address => HoldedBalance) private _holds;
  mapping(address => mapping(address => uint88)) private _lockedBalances;

  Balances.RateAcc private _totals;

  function getSig(bytes calldata data) private pure returns (bytes4 sig) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      calldatacopy(0, data.offset, 4)
      sig := mload(0)
      // sig := mload(add(_data, 32))
    }
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
    } else {
      bytes4 selector = getSig(data[:4]);
      if (selector == DInsuredPoolTransfer.addCoverageByInvestor.selector) {
        unusedAmount = _addCoverageByInvestor(operator, from, value, data[4:]);
      } else if (selector == DInsuredPoolTransfer.addCoverageByInsurer.selector) {
        abi.decode(data[4:], ());
        require(operator == from && internalIsAllowedAsHolder(_balances[operator].extra));
        // do nothing
      } else {
        revert('unsupported call data');
      }
    }

    if (unusedAmount > 0) {
      require(unusedAmount <= value);
      // return the unused portion
      transferCollateral(from, unusedAmount);
    }
  }

  function _addCoverageByInvestor(
    address operator,
    address from,
    uint256 amount,
    bytes calldata data
  ) private returns (uint256) {
    (address account, uint256 minAmount, uint256 minPremiumRate, address insurerPool) = abi.decode(
      data,
      (address, uint256, uint256, address)
    );
    (uint256 unusedAmount, uint256 mintedAmount) = _invest(account, amount, minAmount, minPremiumRate, insurerPool);

    if (mintedAmount > 0 && insurerPool != address(0)) {
      require(
        IERC1363Receiver(insurerPool).onTransferReceived(operator, from, mintedAmount, '') ==
          IERC1363Receiver.onTransferReceived.selector
      );
    }

    return unusedAmount;
  }

  ///@dev Invests into the insured for the investor, and it must invest >= minAmount at a rate >= minPremiumRate
  ///@return unusedAmount Amount of unused coverage
  ///@return amount of coverage provided
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

    unusedAmount -= amount;

    internalMintForCoverage(investor, amount, premiumRate, holder);
    return (unusedAmount, amount);
  }

  ///@dev Mint the correct amount of tokens for the account (investor)
  function internalMintForCoverage(
    address account,
    uint256 rateAmount,
    uint256 premiumRate,
    address holder
  ) internal virtual {
    rateAmount = rateAmount.wadMul(premiumRate);
    require(rateAmount <= type(uint88).max);

    emit Transfer(address(0), account, rateAmount);

    Balances.RateAccWithUint16 memory b;
    if (holder != address(0)) {
      b = _syncBalance(holder);
      require(internalIsAllowedAsHolder(b.extra));

      _lockedBalances[holder][account] += uint88(rateAmount);
      _holds[account].balance += uint88(rateAmount);

      emit Transfer(account, holder, rateAmount);
      emit TransferToHold(account, holder, rateAmount);
      account = holder;
    } else {
      b = _syncBalance(account);
    }

    b.rate += uint88(rateAmount);
    _balances[account] = b;

    Balances.RateAcc memory totals = internalSyncTotals();
    require((totals.rate = uint96(rateAmount += totals.rate)) == rateAmount);
    //totals.rate = uint96(rateAmount += totals.rate);
    _totals = totals;
  }

  function transferBalanceAndEmit(
    address sender,
    address recipient,
    uint256 amount
  ) internal override {
    if (sender != recipient) {
      transferBalance(sender, recipient, amount);
    }
    // NB! Transfer event will be emitted from transferBalance to ensure proper sequence
    // emit Transfer(sender, recipient, amount);
  }

  function transferBalance(
    address sender,
    address recipient,
    uint256 amount
  ) internal override {
    require(amount <= type(uint88).max);

    bool fromHold;
    Balances.RateAccWithUint16 memory b = _syncBalance(sender);
    if (isHolder(b) && msg.sender == sender) {
      // can only be done by a direct call of a holder
      _lockedBalances[sender][recipient] = uint88(_lockedBalances[sender][recipient] - amount);
      _holds[recipient].balance -= uint88(amount);

      emit TransferFromHold(sender, recipient, amount);
      fromHold = true;
    }
    b.rate = uint88(b.rate - amount);
    _balances[sender] = b;

    b = _syncBalance(recipient);
    b.rate += uint88(amount);

    emit Transfer(sender, recipient, amount);
    if (isHolder(b)) {
      require(internalIsAllowedAsHolder(b.extra));
      require(!fromHold); // need to know what is the actual account

      _lockedBalances[recipient][sender] += uint88(amount);
      _holds[sender].balance += uint88(amount);

      emit TransferToHold(sender, recipient, amount);
    }
    _balances[recipient] = b;
  }

  function internalIsAllowedAsHolder(uint16 status) internal view virtual returns (bool);

  function _syncBalance(address account) private view returns (Balances.RateAccWithUint16 memory) {
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
      uint256 holded,
      uint256 premium
    )
  {
    Balances.RateAccWithUint16 memory b = _syncBalance(account);
    return (b.rate, _holds[account].balance, b.accum);
  }

  function holdedBalanceOf(address account, address holder) public view returns (uint256) {
    return _lockedBalances[holder][account];
  }

  function totalSupply() public view override returns (uint256) {
    return _totals.rate;
  }

  function totalPremium() public view override returns (uint256 rate, uint256 accumulated) {
    Balances.RateAcc memory totals = internalSyncTotals();
    return (totals.rate, totals.accum);
  }

  function internalSetServiceAccountStatus(address account, uint16 status) internal virtual {
    require(status > 0);
    if (_balances[account].extra != 0) {} else {
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

  ///@dev Reconcile the amount of collected premium and current premium rate with the Insurer
  ///@param updateRate whether the total rate of this Insured pool should be updated
  function internalReconcileWithInsurer(IInsurerPoolDemand insurer, bool updateRate)
    internal
    returns (uint256 receivedCoverage, DemandedCoverage memory coverage)
  {
    Balances.RateAccWithUint16 memory b = _syncBalance(address(insurer));
    require(internalIsAllowedAsHolder(b.extra));

    (receivedCoverage, coverage) = insurer.receiveDemandedCoverage(address(this));
    // console.log('internalReconcileWithInsurer', address(this), coverage.totalPremium, coverage.premiumRate);

    uint256 diff;
    Balances.RateAcc memory totals;
    if (b.accum != coverage.totalPremium) {
      totals = internalSyncTotals();
      if (b.accum < coverage.totalPremium) {
        // technical underpayment
        diff = coverage.totalPremium - b.accum;
        require((totals.accum = uint128(diff += totals.accum)) == diff);
        revert('technical underpayment'); // TODO this should not happen now, but remove it later
      } else {
        totals.accum -= uint128(diff = b.accum - coverage.totalPremium); //TODO (Tyler)
      }

      b.accum = uint120(coverage.totalPremium);
    }

    if (coverage.premiumRate != b.rate && (coverage.premiumRate > b.rate || updateRate)) {
      if (diff == 0) {
        totals = internalSyncTotals();
        diff = 1;
      }
      uint88 prevRate = b.rate;
      require((b.rate = uint88(coverage.premiumRate)) == coverage.premiumRate);
      if (prevRate > b.rate) {
        totals.rate -= prevRate - b.rate;
      } else {
        totals.rate += b.rate - prevRate;
      }
    }

    if (diff > 0) {
      _totals = totals;
      _balances[address(insurer)] = b;
    }
  }

  function internalSyncTotals() internal view returns (Balances.RateAcc memory) {
    return _totals.sync(uint32(block.timestamp));
  }

  function internalReconcileWithInsurerView(IInsurerPoolDemand insurer, Balances.RateAcc memory totals)
    internal
    view
    returns (
      uint256 receivedCoverage,
      DemandedCoverage memory coverage,
      Balances.RateAccWithUint16 memory b
    )
  {
    b = _syncBalance(address(insurer));
    require(internalIsAllowedAsHolder(b.extra));

    (receivedCoverage, coverage) = insurer.receivableDemandedCoverage(address(this));
    require(b.updatedAt >= coverage.premiumUpdatedAt);

    uint256 diff;
    if (b.accum != coverage.totalPremium) {
      if (b.accum < coverage.totalPremium) {
        // technical underpayment
        diff = coverage.totalPremium - b.accum;
        require((totals.accum = uint128(diff += totals.accum)) == diff);
        revert('technical underpayment'); // TODO this should not happen now, but remove it later
      } else {
        diff = b.accum - coverage.totalPremium;
        totals.accum -= uint128(diff);
      }

      b.accum = uint120(coverage.totalPremium);
    }

    if (coverage.premiumRate != b.rate && (coverage.premiumRate > b.rate)) {
      require((b.rate = uint88(coverage.premiumRate)) == coverage.premiumRate);
    }
  }
}
