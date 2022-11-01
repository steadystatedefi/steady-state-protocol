// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../interfaces/ICollateralized.sol';

/// @dev Premium fund facilitates swapping of insurers' value into insureds' premium tokens.
interface IPremiumFund is ICollateralized {
  /// @dev Pulls the premium token from applicable sources.
  /// @param actuary is an insurer for which this operation will be performed.
  /// @param sourceLimit is a maximum number of sources to be pulled.
  /// @param targetToken is the premium token (asset) to be pulled.
  function syncAsset(
    address actuary,
    uint256 sourceLimit,
    address targetToken
  ) external;

  /// @dev Pulls premium tokens from applicable sources.
  /// @param actuary is an insurer for which this operation will be performed.
  /// @param sourceLimit is a maximum number of sources to be pulled.
  /// @param targetTokens is a list of premium tokens to be pulled.
  /// @return how many tokens were pulled before the limit was reached.
  function syncAssets(
    address actuary,
    uint256 sourceLimit,
    address[] calldata targetTokens
  ) external returns (uint256);

  /// @dev Swaps some value into a premium token. The token must be supplied by at least one insured covered by the insurer.
  /// @param actuary is an insurer which token will be swapped (burnt).
  /// @param account to be charged. Should be the caller or should be approved for swap by the account.
  /// @param recipient to receive the premium token.
  /// @param valueToSwap is a value (not amount) of insurer's token to be swapped into the premium token.
  /// @param targetToken is the premium token to be received.
  /// @param minAmount is the minimum required amount of the premium token, if this cant be satisfied then the account will not be charged.
  /// @return tokenAmount of the premium token transferred.
  function swapAsset(
    address actuary,
    address account,
    address recipient,
    uint256 valueToSwap,
    address targetToken,
    uint256 minAmount
  ) external returns (uint256 tokenAmount);

  struct SwapInstruction {
    /// @dev A value (not amount) of insurer's token to be swapped into the premium token.
    uint256 valueToSwap;
    /// @dev A premium token to be received.
    address targetToken;
    /// @dev The minimum required amount of the premium token, if this cant be satisfied then this instruction will do nothing.
    uint256 minAmount;
    /// @dev A recipient to receive the premium token.
    address recipient;
  }

  /// @dev Swaps some value into a set of premium tokens. Premium tokens must be supplied by insureds covered by the insurer.
  /// @dev This method allows to avoid slippage of the total balance introduced by individual swaps, hance takes a smaller fee.
  /// @param actuary is an insurer which token will be swapped (burnt).
  /// @param account to be charged. Should be the caller or should be approved for swap by the account.
  /// @param instructions of swaps.
  /// @return tokenAmounts of premium tokens transferred.
  function swapAssets(
    address actuary,
    address account,
    SwapInstruction[] calldata instructions
  ) external returns (uint256[] memory tokenAmounts);

  /// @return a list of premium tokens ever known to this fund.
  function knownTokens() external view returns (address[] memory);

  /// @return a list of actuaries (insuers) who has sources (insureds) able to provide this premium token.
  function actuariesOfToken(address token) external view returns (address[] memory);

  /// @return a list of actuaries (insuers) currently accepted by this fund.
  function actuaries() external view returns (address[] memory);

  /// @return a list of active sources (insureds) supplying a premium `token` for the `actuary`.
  function activeSourcesOf(address actuary, address token) external view returns (address[] memory);

  /// @dev Info about availability of a premium token (in exchange for a token of an actuary)
  struct AssetBalanceInfo {
    /// @dev amount of the premium token (asset) available to be swapped for token of the actuary
    uint256 amount;
    /// @dev amount of the premium token (asset) at the starvation point
    uint256 stravation;
    /// @dev weighted base price of the available premium token (asset)
    uint256 price;
    /// @dev fee factor
    uint256 feeFactor;
    /// @dev supply rate of the premium token (CC-value per second, not amount)
    uint256 valueRate;
    /// @dev a timestamp since the valueRate is applied
    uint32 since;
  }

  /// @return details about a premium `token` amounts and balancing parameters for the `actuary`.
  function assetBalance(address actuary, address asset) external view returns (AssetBalanceInfo memory);
}
