// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import './interfaces/IProtocol.sol';
import './interfaces/IProtocolPayIn.sol';
import './interfaces/IVirtualReserve.sol';
import './PoolToken.sol';

/// @dev CoveragePool contract that keeps track of depositors
/// Ideally, this should eventually be more generic
/// This only supports one bucket, eventually there will be multiple risk buckets
contract CoveragePool {
  address public protocol;
  IProtocolPayIn public protocolInfo;
  IVirtualReserve public reserve;
  address public claimValidator;

  IERC20 public immutable USDX; //TODO: Change name, set to our internal AMM token

  uint256 public maxCoverage;
  uint256 public currentCoverage;
  IERC20 public rewardToken;
  PoolToken public poolToken; //Token that is the representation of a share of this pool.
  uint256 public premiumRate;
  // Over-collateralization allows more funds than maxCoverage. This reduces premium for users,
  // but a payout does not take a user's entire deposit
  bool public allowOvercollateralized;

  uint256 public blockCreated;
  uint256 public blockExpiry;

  constructor(
    address _protocol,
    uint256 _maxCoverage,
    uint256 _prem,
    address _usdx,
    address _reward,
    uint256 _expiry
  ) {
    protocol = _protocol;
    maxCoverage = _maxCoverage;
    premiumRate = _prem;
    USDX = IERC20(_usdx);
    rewardToken = IERC20(_reward);
    blockCreated = block.number;
    blockExpiry = _expiry;
    poolToken = new PoolToken('PoolToken', 'TEST');
  }

  /// ====== PROTOCOL FUNCTIONS ====== ////
  /*
  function isProtocolSolvent() external view returns (bool) {
    TokenAmount[] balances = protocolInfo.balanceOf(protocol);
    for (uint256 i = 0; i < balances.length; i++) {
      if (balances[i].token == rewardToken) {
        if (balances[i].amount > 0) {
          return true;
        }
      }
    }
    return false;
  }
  */

  /// ====== DEPOSITOR FUNCTIONS ====== ///

  /// @dev Deposit is used by users to deposit their USDX into a pool
  /// TODO: This does not allow the leverage required by coverage pools
  function deposit(uint256 amount) external {
    require(USDX.allowance(msg.sender, address(reserve)) > amount, 'Allowance too low');
    require(currentCoverage + amount <= maxCoverage, 'Deposit would go over max coverage');
    reserve.deposit(msg.sender, amount);
    currentCoverage += amount;
    poolToken.mint(msg.sender, amount);
  }

  //TODO: Hook into IProtocolPayIn and use it to calculate user's deposits
}
