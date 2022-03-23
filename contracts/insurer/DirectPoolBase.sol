// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/ERC20BalancelessBase.sol';
import '../tools/tokens/ERC1363ReceiverBase.sol';
import '../tools/math/PercentageMath.sol';
import '../tools/upgradeability/Delegator.sol';
import '../libraries/Balances.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IInsuredPool.sol';
import './WeightedPoolStorage.sol';
import './WeightedPoolExtension.sol';
import '../insurance/InsurancePoolBase.sol';

// Handles all user-facing actions. Handles adding coverage (not demand) and tracking user tokens
abstract contract DirectPoolBase is IInsurerPoolCore, ERC1363ReceiverBase, InsurancePoolBase, ERC20BalancelessBase {
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
    //    require(internalGetInsuredStatus(msg.sender) == InsuredStatus.Accepted);
  }

  modifier onlyActiveInsured() {
    _onlyActiveInsured();
    _;
  }

  function _onlyInsured() private view {
    //    require(internalGetInsuredStatus(msg.sender) > InsuredStatus.Unknown);
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

  function cancelCoverage(uint256 paidoutCoverage) external onlyActiveInsured {
    require(_cancelledAt == 0);

    uint256 total = _totalBalance.rayMul(exchangeRate());

    if (paidoutCoverage > 0) {
      _inverseExchangeRate = uint96(WadRayMath.RAY - (total - paidoutCoverage).rayDiv(total).rayMul(exchangeRate()));
      total -= paidoutCoverage;
    }

    if (total > 0) {
      transferCollateralFrom(msg.sender, address(this), total);
    }

    _cancelledAt = uint32(block.timestamp);
  }

  function internalApplyCoverage(address account, uint256 coverageAmount) internal returns (uint96 ratePoints) {}

  /// @dev Updates the user's balance based upon the current exchange rate of $CC to $Pool_Coverage
  function internalMintForCoverage(address account, uint256 coverageAmount) internal {
    require(account != address(0));
    require(_cancelledAt == 0);
    uint96 ratePoints = internalApplyCoverage(account, coverageAmount);

    Balances.RateAcc memory b = _beforeBalanceUpdate(account);
    b.rate += ratePoints;
    _premiums[account] = b;

    emit Transfer(address(0), account, coverageAmount);

    coverageAmount = coverageAmount.rayDiv(exchangeRate());
    _balances[account] += coverageAmount;
    _totalBalance += coverageAmount;
  }

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
    (rate, premium) = interestRate(account);
  }

  function totalSupply() public view override returns (uint256) {
    return _totalBalance.rayMul(exchangeRate());
  }

  function interestRate(address account) public view override returns (uint256 rate, uint256 premium) {
    Balances.RateAcc memory b = _premiums[account];
    uint32 at = _cancelledAt;
    if (at == 0) {
      rate = b.rate;
      at = uint32(block.timestamp);
    }
    premium = b.sync(at).accum;
  }

  // function statusOf(address account) external view returns (InsuredStatus status) {
  //   if ((status = internalGetStatus(account)) == InsuredStatus.Unknown && internalIsInvestor(account)) {
  //     status = InsuredStatus.NotApplicable;
  //   }
  //   return status;
  // }

  /// @dev ERC1363-like receiver, invoked by the collateral fund for transfers/investments from user.
  /// mints $IC tokens when $CC is received from a user
  function internalReceiveTransfer(
    address operator,
    address,
    uint256 value,
    bytes calldata data
  ) internal override onlyCollateralCurrency {
    // if (internalIsInvestor(operator)) {
    //   if (value == 0) return;
    //   internalHandleInvestment(operator, value, data);
    // } else {
    //   InsuredStatus status = internalGetStatus(operator);
    //   if (status != InsuredStatus.Unknown) {
    //     // TODO return of funds from insured
    //     Errors.notImplemented();
    //     return;
    //   }
    // }
    // internalHandleInvestment(operator, value, data);
  }

  function internalHandleInvestment(
    address investor,
    uint256 amount,
    bytes memory data
  ) internal virtual {
    if (data.length > 0) {
      abi.decode(data, ());
    }
    internalMintForCoverage(investor, amount);
  }

  ///@notice Transfer a balance to a recipient, syncs the balances before performing the transfer
  ///@param sender  The sender
  ///@param recipient The receiver
  ///@param amount  Amount to transfer
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
      _balances[sender] = bal - amount;
      ratePoints = uint96((b.rate * (amount + (bal >> 1))) / bal);
      _premiums[sender] = b;
    }

    {
      b = _beforeBalanceUpdate(recipient);
      b.rate += ratePoints;
      _balances[recipient] += amount;
      _premiums[sender] = b;
    }
  }
}
