// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../interfaces/ICollateralized.sol';

interface ICollateralFund is ICollateralized {
  /// @dev Sets or unsets approvals granted by msg.sender to `operator`
  /// @param operator to be get granted or revoked approvals
  /// @param access is a bitmask of approvals to be granted or revoked. See CollateralFundLib.
  /// @param approved is true to grant approvals, false to revoke
  function setApprovalsFor(
    address operator,
    uint256 access,
    bool approved
  ) external;

  /// @dev Replaces all approvals granted by msg.sender to `operator`
  /// @param operator to be get updated approvals
  /// @param access is a bitmask of approvals to be granted, prevously granted approvals will be revoked. See CollateralFundLib.
  function setAllApprovalsFor(address operator, uint256 access) external;

  /// @return approvals granted by `account` to `operator`
  function getAllApprovalsFor(address account, address operator) external view returns (uint256);

  /// @return true when all approvals defined by `access` are granted by `account` to `operator`
  function isApprovedFor(
    address account,
    address operator,
    uint256 access
  ) external view returns (bool);

  /// @dev Deposits `tokenAmount` of `token` and tranfers the resulting amount of the collateral currency to the `account`.
  /// @dev Use of this method may lead to arbitrage of assets thorugh the fund, hence this method is NOT allowed by default.
  /// @dev To enable this method, the `account` must be granted APPROVED_DEPOSIT as special permission.
  /// @dev The sender must == `account` or must have APPROVED_DEPOSIT granted by the `account`.
  /// @param account will receive collateral.
  /// @param token to be deposited. Must be accepted by the fund.
  /// @param tokenAmount to be deposited.
  /// @return amount of collateral currency transferred to the `account`. Zero when the operation was not applied.
  function deposit(
    address account,
    address token,
    uint256 tokenAmount
  ) external returns (uint256);

  /// @dev Deposits `tokenAmount` of `token` on behalf of the `account`, then invests the resulting collateral into `investTo` (insurer).
  /// @dev The sender must == `account` or must have APPROVED_INVEST and APPROVED_DEPOSIT granted by the `account`.
  /// @param account will receive a token from the `investTo`.
  /// @param token to be deposited. Must be accepted by the fund.
  /// @param tokenAmount to be deposited and invested.
  /// @param investTo will receive collateral as investment. This can only be an insurer.
  /// @return amount of collateral currency transferred to `investTo` on behalf of the `account`. Zero when the operation was not applied.
  function invest(
    address account,
    address token,
    uint256 tokenAmount,
    address investTo
  ) external returns (uint256);

  /// @dev Deposits `tokenAmount` of `token` on behalf of the `account`, then invests the new collateral + `depositValue` into `investTo` (insurer).
  /// @dev The sender must == `account` or must have APPROVED_INVEST and (when tokenAmount > 0) APPROVED_DEPOSIT granted by the `account`.
  /// @param account will receive a token from the `investTo`.
  /// @param depositValue to be invested from the current balance of `account`.
  /// @param token to be deposited. Must be accepted by the fund.
  /// @param tokenAmount to be deposited and invested.
  /// @param investTo will receive collateral as investment. This can only be an insurer.
  /// @return amount of collateral currency transferred to `investTo` on behalf of the `account`. Zero when the operation was not applied.
  function investIncludingDeposit(
    address account,
    uint256 depositValue,
    address token,
    uint256 tokenAmount,
    address investTo
  ) external returns (uint256);

  /// @dev Withdraws `tokenAmount` of `token` by burning relevant amount of the collateral currency from the `account`.
  /// @dev The sender must == `account` or must have APPROVED_WITHDRAW granted by the `account`.
  /// @param account will be charged for the requested token amount.
  /// @param to will receive the requested token amount.
  /// @param token to be withdrawn. Must be accepted by the fund.
  /// @param tokenAmount to be withdrawn.
  /// @return amount of collateral currency burnt from the `account`. Zero when the operation was not applied.
  function withdraw(
    address account,
    address to,
    address token,
    uint256 tokenAmount
  ) external returns (uint256);

  /// @return a list of assets accepted by this fund.
  function assets() external view returns (address[] memory);
}
