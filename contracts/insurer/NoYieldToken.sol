// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '../tools/tokens/ERC1155Addressable.sol';
import '../tools/tokens/ERC20Base.sol';
import '../tools/SafeOwnable.sol';
import '../interfaces/IInsurerPool.sol';

abstract contract StakedPremiumHandler is ERC1155Addressable {
  struct Premium {
    uint256 earned;
    uint256 lastPremiumIndex;
  }

  struct PoolState {
    uint256 balance;
    uint256 premiumIndex;
    uint256 lastPremium;
  }

  ///[pool id][user]
  mapping(uint256 => mapping(address => Premium)) private premiums;
  mapping(uint256 => PoolState) private pools;

  // This variable tracks the number of underlying tokens that all pools are worth.
  uint256 public totalStaked;

  uint256 private constant multiplier = 10**20;

  ///@dev Update the user's earned premium
  ///@param user  User to update
  ///@param pool  ID of the premium-earning pool
  ///@param index The Pool's current index (NOT the global index)
  function updateUser(
    address user,
    uint256 pool,
    uint256 index
  ) internal {
    Premium memory p = updateUserPremium(user, pool, index);
    premiums[pool][user] = p;
  }

  function updateUserPremium(
    address user,
    uint256 pool,
    uint256 index
  ) public view returns (Premium memory p) {
    p = premiums[pool][user];
    if (p.lastPremiumIndex == 0) {
      p.lastPremiumIndex = index;
      return p;
    }

    uint256 poolPremiumEarned = index - p.lastPremiumIndex;
    p.earned += (poolPremiumEarned * balanceOf[user][pool]) / multiplier;
    p.lastPremiumIndex = index;
  }

  ///@dev Updates the pool's premium index and balance. Only updates the variables if >0
  ///@param id            The ERC1155 ID of this pool
  ///@param globalPremium The new premium balance for this entire contract
  ///@param newBalance    The new number of underlying tokens this pool's deposits represent
  ///@return The pool's new index;
  function updatePool(
    uint256 id,
    uint256 globalPremium,
    uint256 newBalance
  ) internal returns (uint256) {
    PoolState memory p = pools[id];
    if (globalPremium > 0) {
      updatePoolPremium(p, id, globalPremium);
    }
    if (newBalance > 0) {
      updatePoolBalance(p, newBalance);
    }
    pools[id] = p;
    return p.premiumIndex;
  }

  function updatePoolPremium(
    PoolState memory p,
    uint256 id,
    uint256 globalPremium
  ) internal view {
    //TODO: Don't like this
    if (totalStaked == 0) {
      p.lastPremium = globalPremium;
      return;
    }
    uint256 poolPremium = ((globalPremium - p.lastPremium) * p.balance * multiplier) / totalStaked;
    uint256 supply = totalSupply(id);
    if (supply != 0) {
      p.premiumIndex += (poolPremium / supply);
    }
    p.lastPremium = globalPremium;
  }

  function updatePoolBalance(PoolState memory p, uint256 newBalance) internal {
    if (newBalance > p.balance) {
      totalStaked += (newBalance - p.balance);
    } else if (newBalance < p.balance) {
      totalStaked -= (p.balance - newBalance);
    }
    p.balance = newBalance;
  }

  ///@dev Reduces amount of premium of the user and the pool
  function updateOnRedeem(
    address user,
    uint256 id,
    uint256 amount
  ) internal {
    premiums[id][user].earned -= amount;
    pools[id].lastPremium -= amount;
  }

  function uri(uint256 id) public view override returns (string memory) {
    return '';
  }

  function getPremiumEarned(
    address user,
    uint256 id,
    uint256 globalPremium
  ) internal view returns (uint256) {
    PoolState memory p = pools[id];
    updatePoolPremium(p, id, globalPremium);
    Premium memory prem = updateUserPremium(user, id, p.premiumIndex);
    return prem.earned;
  }

  function getPoolPremium(address pool) external view returns (uint256) {
    PoolState memory p = pools[_getId(pool)];
    return (p.premiumIndex * p.balance) / multiplier;
  }
}

contract NoYieldToken is ERC20Base, StakedPremiumHandler, SafeOwnable {
  IInsurerPool public underlying;

  ///@dev map(token => pool) these both can be the same (e.g Uniswap). Token is the LP token
  mapping(address => address) private whitelist;

  constructor(
    string memory name_,
    string memory symbol_,
    uint8 decimals_,
    address underlying_
  ) ERC20Base(name_, symbol_, decimals_) {
    underlying = IInsurerPool(underlying_);
  }

  function wrap(uint256 amount) external {
    _mint(msg.sender, amount);
    underlying.transferFrom(msg.sender, address(this), amount);
  }

  function unwrap(uint256 amount) external {
    _burn(msg.sender, amount);
    underlying.transfer(msg.sender, amount);
  }

  function addToWhitelist(address token, address pool) external onlyOwner {
    //Prevent overwriting pools, need to check that all LP unstaked or have a withdraw period
    require(whitelist[token] == address(0));
    whitelist[token] = pool;
    (, uint256 acc) = underlying.interestRate(address(this));
    updatePool(_getId(token), acc, ERC20BalanceBase.balanceOf(pool));
  }

  //TODO: I think should be reentrant protected
  ///@dev Stake LP tokens into the pool to continue earning premium
  ///@param token   The address of the LP token that is being staked
  ///@param amount  The amount of LP tokens to stake
  function stake(address token, uint256 amount) external {
    address pool = whitelist[token];
    require(pool != address(0), 'Not accepting this LP');
    uint256 id = _getId(pool);
    mintFor(msg.sender, pool, amount, ''); //TODO: Internal mint will be cheaper

    IERC20(token).transferFrom(msg.sender, address(this), amount);
    uint256 balance = ERC20BalanceBase.balanceOf(pool);
    updatePool(id, 0, balance);
  }

  ///@dev Unstake LP tokens out of the pool
  ///@param token   The address of the LP token that is being unstaked
  ///@param amount  The amount of LP tokens to unstake
  function unstake(address token, uint256 amount) external {
    address pool = whitelist[token];
    require(pool != address(0));
    uint256 id = _getId(pool);
    (, uint256 acc) = underlying.interestRate(address(this));

    IERC20(pool).transfer(msg.sender, amount);

    uint256 index = updatePool(id, acc, ERC20BalanceBase.balanceOf(pool));
    updateUser(msg.sender, id, index);
    burnFor(msg.sender, pool, amount);
  }

  function redeemPremium(
    address user,
    uint256 id,
    uint256 amount,
    uint256 globalPremium
  ) internal {
    //TODO: Should this function only ever redeem all premium instead of only some?
    updatePool(id, globalPremium, 0);
    updateOnRedeem(user, id, amount);

    //TODO: !! Premium transfer
  }

  function _beforeTokenTransfer(
    address operator,
    address from,
    address to,
    uint256[] memory ids,
    uint256[] memory amounts,
    bytes memory data
  ) internal override {
    bool fromOn = (from == address(0));
    bool toOn = (to == address(0));

    uint256 index;
    uint256 acc;
    for (uint256 i; i < ids.length; i++) {
      //Don't like calling this here, but data is untrusted...need to think of cheaper way
      (, acc) = underlying.interestRate(address(this));
      index = updatePool(ids[i], acc, 0);
      if (fromOn) updateUser(from, ids[i], index);
      if (toOn) updateUser(to, ids[i], index);
    }
  }

  function earned(address user, address pool) external view returns (uint256) {
    uint256 acc;
    uint256 index;
    (, acc) = underlying.interestRate(address(this));
    return getPremiumEarned(user, _getId(pool), acc);
  }

  function numToMint(address, uint256 amount) public view override returns (uint256) {
    return amount;
  }
}
