// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/tokens/IERC20.sol';

interface IManagedCollateralCurrency is IERC20 {
  /// @dev Mints the token. Only for registered liquidity providers.
  function mint(address account, uint256 amount) external;

  /// @dev Does an equivalent of mint(onBehalf, mintAmount) followed by a transfer of (mintAmount + balanceAmount) from onBehalf to recipient.
  /// @dev The recipient will receive a callback (ERC1363) like the transfer was made by `onBehalf`.
  /// @dev Only for a liquidity provider.
  /// @param onBehalf is an address to which the `mintAmount` will be minted, and from which a transfer will be made.
  /// @param recipient is an address to receive the transfer. Must be an insurer.
  /// @param mintAmount is an amount to be minted.
  /// @param balanceAmount to be taken from the current balance, can be uint256.max to take whole balance.
  function mintAndTransfer(
    address onBehalf,
    address recipient,
    uint256 mintAmount,
    uint256 balanceAmount
  ) external;

  /// @dev Regular transfer, but the recipient will receive (when allowed) a callback (ERC1363) like the transfer was made by `onBehalf`.
  /// @dev Only for a liquidity provider.
  /// @param onBehalf is an address from which a transfer will be made.
  /// @param recipient is an address to receive the transfer.
  /// @param amount to be transferred.
  function transferOnBehalf(
    address onBehalf,
    address recipient,
    uint256 amount
  ) external;

  /// @dev Burns the token. Only for registered liquidity providers.
  function burn(address account, uint256 amount) external;

  /// @return true when the `account` can mint, i.e. is a liquidity provider / a collateral fund.
  function isLiquidityProvider(address account) external view returns (bool);

  /// @return true when the account was registered either registerInsurer() with or with registerLiquidityProvider()
  function isRegistered(address account) external view returns (bool);

  /// @return a contract that controls borrowing of underlying funds from collateral funds attached to this currency.
  function borrowManager() external view returns (address);

  /// @dev Transfers available yield to the caller.
  /// @return amount of yield added to the caller's account.
  function pullYield() external returns (uint256);
}
