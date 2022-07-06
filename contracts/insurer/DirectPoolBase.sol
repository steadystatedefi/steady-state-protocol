// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/ERC20BalancelessBase.sol';
import '../tools/tokens/ERC1363ReceiverBase.sol';
import '../tools/math/PercentageMath.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/upgradeability/Delegator.sol';
import '../libraries/Balances.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IInsuredPool.sol';
import '../funds/Collateralized.sol';
import './InsurerJoinBase.sol';

/// @title Direct Pool Base
/// @notice Handles capital providing actions involving adding coverage DIRECTLY to an insured
abstract contract DirectPoolBase is
  ICancellableCoverage,
  IPerpetualInsurerPool,
  Collateralized,
  InsurerJoinBase,
  ERC20BalancelessBase,
  ERC1363ReceiverBase
{
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using Balances for Balances.RateAcc;

  address private _insured;

  mapping(address => Balances.RateAcc) private _premiums;
  mapping(address => uint256) private _balances;

  uint256 private _totalBalance;
  uint224 private _inverseExchangeRate;
  uint32 private _cancelledAt;

  function exchangeRate() public view override returns (uint256) {
    return WadRayMath.RAY - _inverseExchangeRate;
  }

  function _onlyActiveInsured() private view {
    require(msg.sender == _insured && _cancelledAt == 0);
  }

  modifier onlyActiveInsured() {
    _onlyActiveInsured();
    _;
  }

  function _onlyInsured() private view {
    require(msg.sender == _insured);
  }

  modifier onlyInsured() {
    _onlyInsured();
    _;
  }

  function charteredDemand() external pure override returns (bool) {
    return false;
  }

  function _beforeBalanceUpdate(address account) private view returns (Balances.RateAcc memory) {
    return _beforeBalanceUpdate(account, uint32(block.timestamp));
  }

  function _beforeBalanceUpdate(address account, uint32 at) private view returns (Balances.RateAcc memory) {
    return _premiums[account].sync(at);
  }

  function cancelCoverage(address insured, uint256 payoutRatio) external override onlyActiveInsured returns (uint256 payoutValue) {
    require(insured == msg.sender);

    uint256 total = _totalBalance.rayMul(exchangeRate());

    if (payoutRatio > 0) {
      payoutValue = total.rayMul(payoutRatio);
      _inverseExchangeRate = uint96(WadRayMath.RAY - (total - payoutValue).rayDiv(total).rayMul(exchangeRate()));
      total -= payoutValue;
    }

    if (total > 0) {
      transferCollateralFrom(msg.sender, address(this), total);
    }

    _cancelledAt = uint32(block.timestamp);
  }

  /// @dev Updates the user's balance based upon the current exchange rate of $CC to $Pool_Coverage
  /// @return excess The amount of coverage that is over the limit
  function internalMintForCoverage(address account, uint256 providedAmount) internal returns (uint256 excess) {
    require(account != address(0));
    require(_cancelledAt == 0);

    (uint256 coverageAmount, uint256 ratePoints) = IInsuredPool(_insured).offerCoverage(providedAmount);
    if (providedAmount > coverageAmount) {
      excess = providedAmount - coverageAmount;
    }

    Balances.RateAcc memory b = _beforeBalanceUpdate(account);
    require((b.rate = uint96(ratePoints + b.rate)) >= ratePoints);
    _premiums[account] = b;

    emit Transfer(address(0), account, coverageAmount);

    coverageAmount = coverageAmount.rayDiv(exchangeRate());
    _balances[account] += coverageAmount;
    _totalBalance += coverageAmount;
  }

  /// @dev Burn all of a user's provided coverage
  /// TODO: transfer event emitted without transferring
  function internalBurnAll(address account) internal returns (uint256 coverageAmount) {
    uint32 cancelledAt = _cancelledAt;
    require(cancelledAt != 0);

    coverageAmount = _balances[account];
    delete _balances[account];
    _totalBalance -= coverageAmount;

    Balances.RateAcc memory b = _beforeBalanceUpdate(account, cancelledAt);
    b.rate = 0;
    _premiums[account] = b;

    coverageAmount = coverageAmount.rayMul(exchangeRate());
    emit Transfer(account, address(0), coverageAmount);

    return coverageAmount;
  }

  function balanceOf(address account) public view override returns (uint256) {
    return uint256(_balances[account]).rayMul(exchangeRate());
  }

  function balancesOf(address account)
    public
    view
    returns (
      uint256 coverageAmount,
      uint256 rate,
      uint256 premium
    )
  {
    coverageAmount = balanceOf(account);
    (rate, premium) = interestOf(account);
  }

  function totalSupply() public view override returns (uint256) {
    return _totalBalance.rayMul(exchangeRate());
  }

  function interestOf(address account) public view override returns (uint256 rate, uint256 accumulated) {
    Balances.RateAcc memory b = _premiums[account];
    uint32 at = _cancelledAt;
    if (at == 0) {
      rate = b.rate;
      at = uint32(block.timestamp);
    }
    accumulated = b.sync(at).accum;
  }

  /// @notice Get the status of the insured account
  /// @param account The account to query
  /// @return status The status of the insured. NotApplicable if the caller is an investor
  function statusOf(address account) external view returns (InsuredStatus status) {
    if ((status = internalGetStatus(account)) == InsuredStatus.Unknown && internalIsInvestor(account)) {
      status = InsuredStatus.NotApplicable;
    }
    return status;
  }

  /// @notice Transfer a balance to a recipient, syncs the balances before performing the transfer
  /// @param sender  The sender
  /// @param recipient The receiver
  /// @param amount  Amount to transfer
  function transferBalance(
    address sender,
    address recipient,
    uint256 amount
  ) internal override {
    amount = amount.rayDiv(exchangeRate());
    uint96 ratePoints;

    Balances.RateAcc memory b;
    {
      b = _beforeBalanceUpdate(sender);

      uint256 bal = _balances[sender];
      ratePoints = uint96((b.rate * (amount + (bal >> 1))) / bal);
      b.rate -= ratePoints;

      _balances[sender] = bal - amount;
      _premiums[sender] = b;
    }

    {
      b = _beforeBalanceUpdate(recipient);
      b.rate += ratePoints;

      _balances[recipient] += amount;
      _premiums[sender] = b;
    }
  }

  function internalPrepareJoin(address) internal pure override returns (bool) {
    return true;
  }

  function internalInitiateJoin(address account) internal override returns (InsuredStatus) {
    address insured = _insured;
    if (insured == address(0)) {
      _insured = account;
    } else if (insured != account) {
      return InsuredStatus.JoinRejected;
    }

    return InsuredStatus.Accepted;
  }

  function internalGetStatus(address account) internal view override returns (InsuredStatus) {
    return _insured == account ? (_cancelledAt == 0 ? InsuredStatus.Accepted : InsuredStatus.Declined) : InsuredStatus.Unknown;
  }

  function internalSetStatus(address account, InsuredStatus s) internal override {
    // TODO check?
  }

  function internalIsInvestor(address account) internal view override returns (bool) {
    address insured = _insured;
    if (insured != address(0)) {
      return insured != account;
    }

    return _balances[account] > 0 || _premiums[account].accum > 0;
  }

  function internalReceiveTransfer(
    address operator,
    address account,
    uint256 amount,
    bytes calldata data
  ) internal override onlyCollateralCurrency {
    require(data.length == 0);
    if (internalGetStatus(operator) == InsuredStatus.Unknown) {
      uint256 excess = internalMintForCoverage(account, amount);
      if (excess > 0) {
        transferCollateral(account, amount);
      }
    } else {
      // return of funds from insured
    }
  }

  function withdrawable(address account) public view override returns (uint256 amount) {
    return _cancelledAt == 0 ? 0 : balanceOf(account);
  }

  function withdrawAll() external override returns (uint256) {
    return _cancelledAt == 0 ? 0 : internalBurnAll(msg.sender);
  }
}
