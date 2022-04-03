// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '../tools/tokens/ERC20Base.sol';
import '../tools/SafeOwnable.sol';
import '../interfaces/IInsurerPool.sol';

contract TradeableToken is ERC20Base, SafeOwnable {
  struct PoolInfo {
    //bool initialized;   //Can't rely on lastIndex as this token can be made before capital is in an index pool
    // Must store the contract that handles distributing rewards to users
    // For example, a curve pool holds the NYT tokens, so a contract must either monitor the
    // curve pool or stake LP tokens.
    address stakingContract;
    uint256 lastIndex;
    uint256 earned;
    uint256 balance; //This should be accurate as its updated on _beforeTransfer
  }

  mapping(address => PoolInfo) private pools; //Pools are the STAKING CONTRACT for a protocol
  //mapping(address => address) private whitelist; //Pool (holding the NYT tokens) => Staking contract

  IInsurerPool public underlying;
  uint256 private index;
  uint256 private lastPremium;
  uint256 public totalStaked;

  uint256 private constant multiplier = 10**20;

  constructor(
    string memory name,
    string memory symbol,
    uint8 decimals,
    address _underlying
  ) ERC20Base(name, symbol, decimals) {
    underlying = IInsurerPool(_underlying);
  }

  function wrap(uint256 amount) external {
    _mint(msg.sender, amount);
    underlying.transferFrom(msg.sender, address(this), amount);
  }

  function unwrap(uint256 amount) external {
    _burn(msg.sender, amount);
    underlying.transfer(msg.sender, amount);
  }

  function claimPremium(address pool, address to) external {
    PoolInfo memory p = pools[pool];
    require(msg.sender == p.stakingContract);
  }

  ///@notice Add a pool to track premium owned by it
  ///@param pool The pool that actually HOLDS the NYT tokens (curve pool, aave pool)
  ///@param stakingContract The contract that handles logic for distributing to users
  function addToWhitelist(address pool, address stakingContract) external onlyOwner {
    //Prevent overwriting pools, need to check that all LP unstaked or have a withdraw period
    PoolInfo memory p = pools[pool];
    require(p.stakingContract == address(0));
    p.stakingContract = stakingContract;

    updateGlobal();
    updatePoolEarned(p, index);
    updatePoolBalance(p, ERC20BalanceBase.balanceOf(pool));
    pools[pool] = p;
  }

  function updateGlobal() internal {
    uint256 currentPremium;
    (, currentPremium) = underlying.interestRate(address(this));
    if (totalStaked == 0) {
      //TODO: Make a claimable field, so that before staking contracts are whitelisted
      // someone can just claim all the yield that no one has a right to
      return;
    }
    index += ((currentPremium - lastPremium) * multiplier) / totalStaked;
    lastPremium = currentPremium;
  }

  ///@dev Update's the pool's balance and totalStaked amount
  function updatePoolBalance(PoolInfo memory p, uint256 newBalance) internal {
    if (newBalance > p.balance) {
      totalStaked += (newBalance - p.balance);
    } else if (newBalance < p.balance) {
      totalStaked -= (p.balance - newBalance);
    }
    p.balance = newBalance;
  }

  ///@dev Updates the pool's earned premium
  function updatePoolEarned(PoolInfo memory p, uint256 ind) internal view {
    if (p.lastIndex == 0) {
      p.lastIndex = ind;
      return;
    }

    uint256 price = ind - p.lastIndex;
    p.earned += (price * p.balance) / multiplier;
    p.lastIndex = ind;
  }

  function getPoolEarned(address pool) external view returns (uint256) {
    PoolInfo memory p = pools[pool];
    if (p.stakingContract == address(0)) {
      return 0;
    }

    uint256 acc;
    uint256 ind = index;
    (, acc) = underlying.interestRate(address(this));
    ind += ((acc - lastPremium) * multiplier) / totalStaked;

    updatePoolEarned(p, ind);
    return p.earned;
  }

  function updatePoolOnTransfer(
    address pool,
    uint256 amount,
    bool from,
    bool stakeUpdate
  ) internal {
    PoolInfo memory p = pools[pool];
    updatePoolEarned(p, index);
    uint256 newBalance = from ? p.balance - amount : p.balance + amount;
    if (stakeUpdate) {
      updatePoolBalance(p, newBalance);
    } else {
      p.balance = newBalance;
    }

    pools[pool] = p;
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal override {
    bool fromOn = !(from == address(0));
    bool toOn = !(to == address(0));
    bool both = !(fromOn && toOn); //If this is true then staked amount won't change
    if (fromOn || toOn) {
      updateGlobal();
      if (fromOn) {
        updatePoolOnTransfer(from, amount, true, both);
      }
      if (toOn) {
        updatePoolOnTransfer(to, amount, false, both);
      }
    }
  }
}
