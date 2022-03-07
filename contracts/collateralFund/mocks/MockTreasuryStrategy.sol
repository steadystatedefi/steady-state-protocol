// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

//import '../../tools/tokens/IERC20.sol';
//import '../../tools/SafeERC20.sol';
import '../../interfaces/ITreasury.sol';
import './MockStablecoin.sol';

///@dev MockTreasuryStrategy implements a strategy on MockStablecoin. It simply
/// holds the tokens and can mint yield at will.
contract MockTreasuryStrategy is ITreasuryStrategy {
  ///@dev A normal strategy will probably have these variables as a struct in a mapping,
  /// as they may accept multiple underlyings
  uint128 public deposits;

  uint32 private blockTimestampLast;

  //Lifetime amount earned or if negative, lost. This can be negative while the strategy is positive yielding
  int256 private delta;

  //TODO: Currently only store earned / deposits. However, do we want to keep cumulative track of those as well?
  int256 public performanceWADCumulative;

  address private _underlying;
  ITreasury private treasury;

  constructor(address _treasury, address underlying_) {
    treasury = ITreasury(_treasury);
    _underlying = underlying_;
    IERC20(_underlying).approve(_treasury, type(uint256).max);
  }

  function _update(
    uint256 depositsOld,
    int256 deltaOld,
    uint256 depositsNew,
    int256 deltaNew
  ) private {
    require(depositsNew <= uint256(type(uint128).max), 'Overflow');
    int256 depositsWad = int256(depositsOld * 1e18);
    int256 deltaWad = deltaOld * 1e18;
    uint32 blockTimestamp = uint32(block.timestamp % 2**32);
    uint32 timeElapsed;
    unchecked {
      timeElapsed = blockTimestamp - blockTimestampLast;
    }
    if (timeElapsed > 0 && depositsOld != 0 && deltaOld != 0) {
      //WAD division
      performanceWADCumulative += int256(uint256(timeElapsed)) * ((deltaWad * 1e18 + depositsWad / 2) / depositsWad);
    }
    deposits = uint128(depositsNew);
    delta = deltaNew;
    blockTimestampLast = blockTimestamp;
  }

  ///@dev A normal strategy would have to take the tokens out of protocol they are earning yield in
  /// and then send them along.
  function requestReturn(address token, uint128 amount) external override returns (bool) {
    uint256 balance = IERC20(_underlying).balanceOf(address(this));
    if (balance < amount) {
      if (balance == 0) {
        return false;
      }
      amount = uint128(balance);
    }
    treasury.depositFunds(_underlying, amount);
    onWithdraw(amount);

    return true;
  }

  function onWithdraw(uint128 amount) internal {
    _update(deposits, delta, deposits - amount, delta);
  }

  ///@dev Mock how much has been earned
  function MockYield(int128 amount) external {
    if (amount > 0) {
      MockStable(_underlying).mint(address(this), uint128(amount));
    } else {
      MockStable(_underlying).burn(address(this), uint128(amount));
    }

    _update(deposits, delta, deposits, delta + amount);
  }

  function Borrow(uint128 amount) external {
    treasury.borrowFunds(_underlying, amount);
    _update(deposits, delta, deposits + amount, delta);
  }

  function Repay(uint128 amount) external {
    treasury.depositFunds(_underlying, amount);
    onWithdraw(amount);
  }

  function totalEarningsOf(address token) external view override returns (Earning[] memory) {
    Earning[] memory earnings = new Earning[](1);
    uint128 earned = delta > 0 ? uint128(uint256(delta)) : 0;
    earnings[0] = (Earning(_underlying, earned));
    return earnings;
  }

  function totalEarned(address token) external view override returns (uint128 earned) {
    if (delta > 0) {
      earned = uint128(uint256(delta));
    } else {
      earned = 0;
    }
  }

  function totalValue(address token) external view override returns (uint128) {
    return uint128(uint256(int256(int128(deposits)) + delta));
  }

  function cumulativePerformanceOf(address token) external view override returns (int256) {
    return performanceWADCumulative;
  }
}
