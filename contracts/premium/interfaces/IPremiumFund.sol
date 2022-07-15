// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../interfaces/ICollateralized.sol';

interface IPremiumFund is ICollateralized {
  // function priceOf(address token) external view returns (uint256);

  function syncAsset(
    address actuary,
    uint256 sourceLimit,
    address targetToken
  ) external;

  function syncAssets(
    address actuary,
    uint256 sourceLimit,
    address[] calldata targetTokens
  ) external returns (uint256);

  function swapAsset(
    address actuary,
    address account,
    address recipient,
    uint256 valueToSwap,
    address targetToken,
    uint256 minAmount
  ) external returns (uint256 tokenAmount);

  struct SwapInstruction {
    uint256 valueToSwap;
    address targetToken;
    uint256 minAmount;
    address recipient;
  }

  function swapAssets(
    address actuary,
    address account,
    address defaultRecepient,
    SwapInstruction[] calldata instructions
  ) external returns (uint256[] memory tokenAmounts);

  function knownTokens() external view returns (address[] memory);

  function actuariesOfToken(address token) external view returns (address[] memory);

  function actuaries() external view returns (address[] memory);

  function activeSourcesOf(address actuary, address token) external view returns (address[] memory);
}
