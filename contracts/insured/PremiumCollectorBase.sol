// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../tools/SafeERC20.sol';
import '../tools/Errors.sol';
import '../tools/tokens/ERC20BalancelessBase.sol';
import '../libraries/Balances.sol';
import '../tools/tokens/IERC20.sol';
import '../interfaces/IPremiumCalculator.sol';
import '../interfaces/IInsurancePool.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IInsuredPool.sol';
import '../interfaces/IProtocol.sol';
import '../tools/math/WadRayMath.sol';
import '../insurance/InsurancePoolBase.sol';

import 'hardhat/console.sol';

struct TokenAmount {
  address token;
  uint256 amount;
}

abstract contract PremiumCollectorBase {
  using WadRayMath for uint256;
  using SafeERC20 for IERC20;

  IERC20 private _payoutToken;
  uint256 private _payoutTokenValue;

  modifier onlyAdmin() virtual {
    // TODO
    _;
  }

  function _onlyProtocolOrRole(ProtocolAccessFlags role) private view {
    // require(msg.sender == protocol || IProtocol(protocol).hasRole(msg.sender, uint256(1) << uint8(role)));
  }

  modifier onlyProtocolOrRole(ProtocolAccessFlags role) {
    _onlyProtocolOrRole(role);
    _;
  }

  modifier onlyDispenserOf(address insurer) {
    // require(insurer.premiumDispenser() == msg.sender);
    _;
  }

  function refillPayoutToken(
    address insurer,
    uint256 minValue,
    uint256 maxValue
  ) external onlyDispenserOf(insurer) returns (uint256 tokenAmount) {
    // decide on value
    // calc tokenAmount
    // reduce premium balance of the insurer by value
    // approve sender for the tokenAmount
  }

  function deposit(uint256 amount) external onlyProtocolOrRole(ProtocolAccessFlags.Deposit) {
    _deposit(amount, amount.rayMul(internalValueRate()));
  }

  function internalValueRate() internal view virtual returns (uint256);

  function _deposit(uint256 amount, uint256 value) private {
    require(amount > 0);
    _payoutToken.safeTransferFrom(msg.sender, address(this), amount);
    _payoutTokenValue += value;
  }

  // TODO alternativePayment
  // TODO sweeper

  //   /// @dev adds tokens to protocol's deposits. Protocol can only supply an agreed set of tokens, e.g. protocol's token & USDx
  //   /// @dev only users allowed by IProtocol.hasRole(DEPOSIT) can do this
  //   function deposit(TokenAmount[] calldata amounts)
  //     external
  // //    onlyProtocolOrRole(protocol, ProtocolAccessFlags.Deposit)
  //   {
  //     for (uint256 i = amounts.length; i > 0; ) {
  //       i--;
  //       address token = amounts[i].token;
  //       TokenBalance storage b = _balances[token];
  //       require(b.timestamp != 0); // Protocol-token combination was not registred

  //       uint256 amount = amounts[i].amount;
  //       if (amount == 0) continue;
  //       IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

  //       amount += b.balance;
  //       require((b.balance = uint112(amount)) == amount);
  //       b.timestamp = uint32(block.timestamp);
  //     }
  //   }

  // /// @dev returns amounts that were not yet consumed/locked by the stream of premium
  function remainingDeposit() public view returns (uint256 amount) {
    amount = _payoutToken.balanceOf(address(this));
    if (amount > 0) {
      // amount += paidOutAmount;
      uint256 locked = internalGetLockedAmount();
      return amount > locked ? amount - locked : 0;
    }
    // return _balanceOf(protocol, 0);
  }

  function internalGetLockedAmount() internal view virtual returns (uint256);

  function internalOwnedLockedAmount() internal view virtual returns (uint256);

  // // /// @dev returns amounts expected to be consumed/locked by the stream of premium at atTimestamp in the future and starting from now
  // function expectedPay(address protocol, uint256 atTimestamp) external view returns (TokenAmount[] memory) {
  //   require(atTimestamp >= block.timestamp);
  //   require(atTimestamp == uint32(atTimestamp));
  //   return _balanceOf(protocol, uint32(atTimestamp));
  // }

  // function expectedPayAfter(address protocol, uint32 timeDelta) external view returns (TokenAmount[] memory) {
  //   return _balanceOf(protocol, uint32(block.timestamp) + timeDelta);
  // }

  /// @dev withdraws tokens from protocol's deposits.
  /// @dev only users allowed by IProtocol.hasRole(WITHDRAW) can do this
  function withdraw(
    uint256 amount,
    address to,
    bool forceReconcile
  ) external onlyProtocolOrRole(ProtocolAccessFlags.Withdraw) {
    amount;
    forceReconcile;
    Errors.notImplemented();
  }
}
