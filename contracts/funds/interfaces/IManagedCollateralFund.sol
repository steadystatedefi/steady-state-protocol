// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './ICollateralFund.sol';

interface IManagedCollateralFund is ICollateralFund {
  /// @dev Sets `token` as `paused`. Operations with a paused token will revert.
  function setPaused(address token, bool paused) external;

  /// @return true when the `token` is paused.
  function isPaused(address token) external view returns (bool);

  /// @dev Assignes a `trustee` of the `token`. The `trustee` will be allowed to call trustedSomething() methods for the `token`.
  function setTrustedOperator(address token, address trustee) external;

  /// @dev Replaces all special approvals granted to `operator`
  /// @param operator to be get updated approvals
  /// @param accessFlags is a bitmask of approvals to be granted, prevously granted approvals will be revoked. See CollateralFundLib.
  function setSpecialRoles(address operator, uint256 accessFlags) external;

  /// @dev Registers a `token` as an underlying asset for this fund.
  /// @param token is an underlying asset to be added
  /// @param trustee for the asset
  function addAsset(address token, address trustee) external;

  /// @dev Unregisters the `token` as an underlying asset for this fund.
  /// @param token is an underlying asset to be removed
  function removeAsset(address token) external;

  /// @dev Resets price guard tripped by an asset price breaching its safe price range.
  /// @dev When the price guard is tripped, operations are NOT allowed for any of assets.
  function resetPriceGuard() external;

  /// @dev Same as ICollateralFund.deposit(), but allows an intermediary trusted contract.
  /// @dev Will revert when sender is not a trustee assigned for the `token`.
  /// @param operator is a sender of the call received by the trustee.
  function trustedDeposit(
    address operator,
    address account,
    address token,
    uint256 tokenAmount
  ) external returns (uint256);

  /// @dev Same as ICollateralFund.investIncludingDeposit(), but allows an intermediary trusted contract.
  /// @dev Will revert when sender is not a trustee assigned for the `token`.
  /// @param operator is a sender of the call received by the trustee.
  function trustedInvest(
    address operator,
    address account,
    uint256 depositValue,
    address token,
    uint256 tokenAmount,
    address investTo
  ) external returns (uint256);

  /// @dev Same as ICollateralFund.withdraw(), but allows an intermediary trusted contract.
  /// @dev Will revert when sender is not a trustee assigned for the `token`.
  /// @param operator is a sender of the call received by the trustee.
  function trustedWithdraw(
    address operator,
    address account,
    address to,
    address token,
    uint256 tokenAmount
  ) external returns (uint256);
}
