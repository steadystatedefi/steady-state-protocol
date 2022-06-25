// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../tools/SafeOwnable.sol';
import '../tools/SafeERC20.sol';
import '../tools/math/WadRayMath.sol';
import '../interfaces/IManagedCollateralCurrency.sol';

contract CollateralFundBase {
  using SafeERC20 for IERC20;
  using WadRayMath for uint256;

  IManagedCollateralCurrency private _collateral;

  struct CollateralAsset {
    address priceSource;
    bool active; // TODO flags
    uint256 lendedBalance;
    address trustedWrapper;
  }

  mapping(address => CollateralAsset) private _assets; // [token]
  mapping(address => mapping(address => uint256)) private _approvals; // [owner][delegate]

  modifier onlyApproved(address account, uint256 access) {
    require(msg.sender == account || _approvals[account][msg.sender] & access == access);
    _;
  }

  uint8 private constant APPROVED_DEPOSIT = 1 << 0;
  uint8 private constant APPROVED_INVEST = 1 << 1;
  uint8 private constant APPROVED_WITHDRAW = 1 << 2;
  uint8 private constant APPROVED_TRANSFER = 1 << 3;

  function deposit(
    address from,
    address to,
    address token,
    uint256 amount
  ) external onlyApproved(to, APPROVED_DEPOSIT) {
    uint256 value = _deposit(_ensureActive(token), from, to, token, amount);
    _collateral.mint(to, value);
  }

  function invest(
    address from,
    address to,
    address token,
    uint256 amount,
    address investTo
  ) external onlyApproved(to, APPROVED_DEPOSIT | APPROVED_TRANSFER) {
    uint256 value = _deposit(_ensureActive(token), from, to, token, amount);
    _collateral.mintAndTransfer(to, investTo, value);
  }

  function _deposit(
    CollateralAsset storage asset,
    address from,
    address to,
    address token,
    uint256 amount
  ) private returns (uint256 value) {
    IERC20(token).safeTransferFrom(from, address(this), amount);
    value = amount.wadMul(priceOf(asset, token));
    internalDeposit(to, token, amount, value);
  }

  function internalDeposit(
    address to,
    address token,
    uint256 amount,
    uint256 value
  ) internal virtual {}

  function priceOf(CollateralAsset storage asset, address token) internal view returns (uint256) {
    // TODO
  }

  function withdraw(
    address from,
    address to,
    address token,
    uint256 amount
  ) external onlyApproved(from, APPROVED_WITHDRAW) {
    _withdraw(_ensureActive(token), from, to, token, amount);
  }

  function _withdraw(
    CollateralAsset storage asset,
    address from,
    address to,
    address token,
    uint256 amount
  ) private {
    if (amount > 0) {
      uint256 value;
      uint256 x;
      if (amount == type(uint256).max) {
        (amount, x) = internalWithdrawValue(token, from, value = _collateral.balanceOf(from));
        if (x > 0) {
          amount += x.wadDiv(priceOf(asset, token));
        }
      } else {
        (x, value) = internalWithdrawAmount(token, from, amount);
        if (x > 0) {
          value += x.wadMul(priceOf(asset, token));
        }
      }

      if (value > 0) {
        _collateral.burn(from, value);
        IERC20(token).safeTransfer(to, amount);
      }
    }
  }

  function internalWithdrawAmount(
    address token,
    address from,
    uint256 amount
  ) internal virtual returns (uint256, uint256 value) {
    token;
    from;
    return (amount, value);
  }

  function internalWithdrawValue(
    address token,
    address from,
    uint256 value
  ) internal virtual returns (uint256 amount, uint256) {
    token;
    from;
    return (amount, value);
  }

  function _ensureActive(address token) private view returns (CollateralAsset storage asset) {
    asset = _assets[token];
    require(asset.active); // require active and not suspended
  }

  function _ensureTrusted(address token) private view returns (CollateralAsset storage asset) {
    asset = _ensureActive(token);
    require(asset.trustedWrapper == msg.sender);
  }

  function trustedDeposit(
    address from,
    address to,
    address token,
    uint256 amount
  ) external {
    uint256 value = _deposit(_ensureTrusted(token), from, to, token, amount);
    _collateral.mint(to, value);
  }

  function trustedInvest(
    address from,
    address to,
    address token,
    uint256 amount,
    address investTo
  ) external {
    uint256 value = _deposit(_ensureTrusted(token), from, to, token, amount);
    _collateral.mintAndTransfer(to, investTo, value);
  }

  function trustedWithdraw(
    address from,
    address to,
    address token,
    uint256 amount
  ) external {
    _withdraw(_ensureTrusted(token), from, to, token, amount);
  }
}
