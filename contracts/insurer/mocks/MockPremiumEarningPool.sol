// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

//import 'solmate/tokens/ERC20.sol';

import '../../tools/tokens/ERC20DetailsBase.sol';
import '../../libraries/Balances.sol';
import '../../tools/math/WadRayMath.sol';

contract MockPremiumEarningPool is ERC20DetailsBase {
  using WadRayMath for uint256;
  using Balances for Balances.RateAcc;

  struct UserBalance {
    uint128 premiumBase;
    uint128 balance;
  }

  mapping(address => UserBalance) internal _balances;
  mapping(address => uint256) internal _premiums;

  uint256 public totalSupply;

  Balances.RateAcc public _totalRate; //Total accum is in RAY
  uint256 public premiumRate; //CC per 1e18 balance
  uint256 private _inverseExchangeRate;

  constructor(
    string memory _name,
    string memory _symbol,
    uint8 _decimals
  ) ERC20DetailsBase(_name, _symbol, _decimals) {}

  /***** POOL LOGIC *****/

  /// @dev Performed before balance updates. The total rate accum by the pool is updated, and then the user balance is updated
  function _beforeBalanceUpdate(address account)
    private
    returns (UserBalance memory b, Balances.RateAcc memory totals)
  {
    totals = _totalRate.sync(uint32(block.timestamp));
    b = _syncBalance(account, totals);
  }

  /// @dev Updates _premiums with total premium earned by user. Each user's balance is marked by the amount
  ///  of premium collected by the pool at time of update
  function _syncBalance(address account, Balances.RateAcc memory totals) private returns (UserBalance memory b) {
    b = _balances[account];
    if (b.balance > 0) {
      uint256 premiumDiff = totals.accum - b.premiumBase;
      if (premiumDiff > 0) {
        _premiums[account] += premiumDiff.wadMul(b.balance) / (totalSupply / 1e18);
      }
    }
    b.premiumBase = totals.accum;
  }

  function setTotalRate(uint256 rate) external {
    setTotalRate(rate, _totalRate);
  }

  function getTotalRate() external view returns (uint256) {
    return _totalRate.rate;
  }

  function getPremiumStored(address account) external view returns (uint256) {
    return _premiums[account];
  }

  function getTotalAccum() external view returns (uint256) {
    Balances.RateAcc memory totals = _totalRate;
    totals.sync(uint32(block.timestamp));
    return totals.accum;
  }

  function setTotalRate(uint256 rate, Balances.RateAcc memory totals) internal {
    if (totals.rate != rate) {
      _totalRate = totals.setRateAfterSync(rate);
    } else {
      require(totals.updatedAt == block.timestamp);
    }
  }

  ///@dev returns the ($CC coverage, $PC coverage, premium accumulated) of a user
  function balancesOf(address account)
    public
    view
    returns (
      uint256 coverage,
      uint256 scaled,
      uint256 premium
    )
  {
    scaled = _balances[account].balance;
    coverage = scaled.rayMul(exchangeRate());
    (, premium) = interestRate(account);
  }

  function scaledBalanceOf(address account) external view returns (uint256) {
    return _balances[account].balance;
  }

  /// @dev Returns the current rate that this user earns per-block, and the amount of premium accumulated
  function interestRate(address account) public view returns (uint256 rate, uint256 accumulated) {
    Balances.RateAcc memory totals = _totalRate.sync(uint32(block.timestamp));
    UserBalance memory b = _balances[account];

    accumulated = _premiums[account];

    if (b.balance > 0) {
      uint256 premiumDiff = totals.accum - b.premiumBase;
      if (premiumDiff > 0) {
        accumulated += uint256(b.balance).wadMul(premiumDiff) / (totalSupply / 1e18);
        //accumulated += (uint256(b.balance) * premiumDiff) / 1e18;
      }
      return (uint256(b.balance).wadMul(totals.rate) / (totalSupply / 1e18), accumulated);
    }

    return (0, accumulated);
  }

  function exchangeRate() public view returns (uint256) {
    return WadRayMath.RAY - _inverseExchangeRate;
  }

  function setPremiumRate(uint256 x) external {
    premiumRate = x;
  }

  function mint(address account, uint256 amount) external {
    (UserBalance memory b, Balances.RateAcc memory totals) = _beforeBalanceUpdate(account);

    //emit Transfer(address(0), account, amount);
    //uint256 amount = coverageAmount.rayDiv(exchangeRate()) + b.balance;
    amount += b.balance;
    b.premiumBase = totals.accum;
    require(amount == (b.balance = uint128(amount)));
    _balances[account] = b;

    uint256 rate = ((totals.rate) + ((amount * (premiumRate)) / 1e18));
    setTotalRate(rate, totals);
    totalSupply += amount;
  }

  function sync(address account) external {
    _beforeBalanceUpdate(account);
  }

  /***** ERC20 LOGIC *****/

  function balanceOf(address account) public view returns (uint256) {
    return uint256(_balances[account].balance).rayMul(exchangeRate());
  }

  ///@notice Transfer a balance to a recipient, syncs the balances before performing the transfer
  ///@param sender  The sender
  ///@param recipient The receiver
  ///@param amount  Amount to transfer
  function transferBalance(
    address sender,
    address recipient,
    uint256 amount
  ) internal {
    (UserBalance memory b, Balances.RateAcc memory totals) = _beforeBalanceUpdate(sender);

    b.balance = uint128(b.balance - amount);
    _balances[sender] = b;

    b = _syncBalance(recipient, totals);
    amount += b.balance;
    require((b.balance = uint128(amount)) == amount);
    _balances[recipient] = b;
  }

  ///insecure
  function transferFrom(
    address from,
    address to,
    uint256 amount
  ) external returns (bool) {
    transferBalance(from, to, amount);
    return true;
  }

  function transfer(address to, uint256 amount) external returns (bool) {
    transferBalance(msg.sender, to, amount);
    return true;
  }

  // solhint-disable-next-line
  function allowance(address, address) external view returns (uint256) {
    return type(uint256).max;
  }

  // solhint-disable-next-line
  function approve(address, uint256) external returns (bool) {
    return true;
  }
}
