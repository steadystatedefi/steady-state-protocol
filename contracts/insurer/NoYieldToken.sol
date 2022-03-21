// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '../tools/tokens/ERC1155Addressable.sol';
import '../tools/tokens/ERC20Base.sol';
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
  uint256 public totalStaked;

  //mapping(uint256 => address) public idToUnderlying;

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
    Premium memory p = premiums[pool][user];
    if (p.lastPremiumIndex == 0) {
      p.lastPremiumIndex = index;
      premiums[pool][user] = p;
      return;
    }

    uint256 poolPremiumEarned = index - p.lastPremiumIndex;
    p.earned += (poolPremiumEarned * balanceOf(user, pool)) / multiplier;
    p.lastPremiumIndex = index;

    premiums[pool][user] = p;
  }

  ///@dev Updates the pool's premium balance and then it's balance
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
      //this check means dust will be left if a pool is ending
      updatePoolBalance(p, newBalance);
    }
    pools[id] = p;
    return p.premiumIndex;
  }

  ///@dev Update the pool's premium index and known premium
  function updatePoolPremium(
    PoolState memory p,
    uint256 id,
    uint256 globalPremium
  ) internal {
    //PoolState memory p = pools[id];
    uint256 poolPremium = ((globalPremium - p.lastPremium) * p.balance * multiplier) / totalStaked;
    p.premiumIndex += (poolPremium / totalSupply(id));
    p.lastPremium = globalPremium;
  }

  ///@dev Updates the pool's balance and totalStaked
  function updatePoolBalance(PoolState memory p, uint256 newBalance) internal {
    //uint256 newBalance = balanceOf(pool);
    if (newBalance > p.balance) {
      totalStaked += (newBalance - p.balance);
    } else if (newBalance < p.balance) {
      totalStaked -= (p.balance - newBalance);
    }

    p.balance = newBalance;
  }

  function updateOnRedeem(
    address user,
    uint256 id,
    uint256 amount
  ) internal {
    premiums[id][user].earned -= amount;
    pools[id].lastPremium -= amount;
  }
}

contract NoYieldToken is ERC20Base, StakedPremiumHandler {
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

  //TODO: I think should be reentrant protected
  ///@dev Stake LP tokens into the pool to continue earning premium
  ///@param token   The address of the LP token that is being staked
  ///@param amount  The amount of LP tokens to stake
  function stake(address token, uint256 amount) external {
    address pool = whitelist[token];
    require(pool != address(0));
    uint256 id = _getId(pool);
    mintFor(msg.sender, pool, amount, ''); //TODO: Internal mint will be cheaper

    IERC20(token).transferFrom(msg.sender, address(this), amount);
    uint256 balance = balanceOf(pool);
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

    uint256 index = updatePool(id, acc, balanceOf(pool));
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

  function numToMint(address, uint256 amount) public view override returns (uint256) {
    return amount;
  }
}
