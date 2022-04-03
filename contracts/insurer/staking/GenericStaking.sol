// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '../../tools/tokens/ERC20Base.sol';
import '../TradeableToken.sol';

///@dev A generic staking contract that distributed rewards based on a user's
///     proportion of the staked assets.
///     For these staking contracts, only need to concern ourselves with the token address
///     as the TradeableToken contract handles translation from token to pool (I think)
contract GenericStaking is ERC20Base {
  struct UserInfo {
    uint256 lastIndex;
    uint256 earned;
  }

  mapping(address => UserInfo) private users;

  address public ipToken; //The tradeable index pool token
  address public underlying; //In Uniswap's case, the LP and pool are at the same address

  uint256 private index;
  uint256 public lastPremium;

  uint256 private constant multiplier = 10**20;

  constructor(
    string memory name_,
    string memory symbol_,
    uint8 decimals_,
    address indexpool_,
    address underlying_
  ) ERC20Base(name_, symbol_, decimals_) {
    ipToken = indexpool_;
    underlying = underlying_;
  }

  ///@notice Deposit your underlying tokens
  function stake(uint256 amount) external {
    _mint(msg.sender, amount);
    IERC20(underlying).transferFrom(msg.sender, address(this), amount);
  }

  function unstake(uint256 amount) external {
    _burn(msg.sender, amount);
    IERC20(underlying).transfer(msg.sender, amount);
  }

  //TODO: We may want to claim this premium for the treasury instead
  function claim(uint256 amount) external {
    updateGlobal();
    updateUser(msg.sender, index);
    //Do transfer
    //lastPremium -= amount;
  }

  ///@notice This function can be called when no one is staked in this pool, but it's
  /// earning premium.
  function claimUnclaimed() external {
    require(totalSupply() == 0);
    updateGlobal();
    users[msg.sender].earned += lastPremium;
  }

  function updateGlobal() internal {
    uint256 currentPremium;
    uint256 supply;
    currentPremium = TradeableToken(ipToken).getPoolEarned(underlying);
    supply = totalSupply();
    if (supply == 0) {
      supply = 1;
    }
    index += ((currentPremium - lastPremium) * multiplier) / supply;
    lastPremium = currentPremium;
  }

  function viewUpdateUser(
    UserInfo memory u,
    uint256 balance,
    uint256 ind
  ) internal pure {
    if (u.lastIndex != 0) {
      uint256 price = ind - u.lastIndex;
      u.earned += (price * balance) / multiplier;
    }
    u.lastIndex = ind;
  }

  function updateUser(address user, uint256 ind) internal {
    UserInfo memory u = users[user];
    viewUpdateUser(u, balanceOf(user), ind);
    users[user] = u;
  }

  function earned(address user) external view returns (uint256) {
    uint256 currentPremium = TradeableToken(ipToken).getPoolEarned(underlying);
    uint256 ind = index;
    ind += ((currentPremium - lastPremium) * multiplier) / totalSupply();

    UserInfo memory u = users[user];
    viewUpdateUser(u, balanceOf(user), ind);
    return u.earned;
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256
  ) internal override {
    updateGlobal();
    uint256 ind = index;
    if (from != address(0)) {
      updateUser(from, ind);
    }
    if (to != address(0)) {
      updateUser(to, ind);
    }
  }
}
