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
  using EnumerableSet for EnumerableSet.AddressSet;

  IManagedCollateralCurrency private _collateral;

  struct CollateralAsset {
    uint128 totalAmount; // this is tracked separatly, as ERC20.balanceOf can be affected by transfers
    uint128 totalValue;
    uint8 flags; // TODO flags
    address trusted;
  }

  uint8 private constant AF_ADDED = 1 << 0;
  uint8 private constant AF_SUSPENDED = 1 << 1;
  uint8 private constant AF_ALLOW_DEPOSIT = 1 << 2;
  uint8 private constant AF_ALLOW_WITHDRAW = 1 << 3;
  uint8 private constant AF_ALLOW_ALL = AF_ALLOW_DEPOSIT | AF_ALLOW_WITHDRAW;

  EnumerableSet.AddressSet private _tokens;
  mapping(address => CollateralAsset) private _assets; // [token]
  mapping(address => mapping(address => uint256)) private _approvals; // [owner][delegate]

  function _onlyApproved(address account, uint256 access) private view {
    require(msg.sender == account || isApprovedFor(account, msg.sender, access));
  }

  modifier onlyApproved(address account, uint256 access) {
    _onlyApproved(account, access);
    _;
  }

  function _onlySpecial(address account, uint256 access) private view {
    require(isApprovedFor(address(0), account, access));
  }

  modifier onlySpecial(address account, uint256 access) {
    _onlySpecial(account, access);
    _;
  }

  function setApprovalsFor(
    address operator,
    uint256 access,
    bool approved
  ) external {
    if (approved) {
      _approvals[msg.sender][operator] |= access;
    } else {
      _approvals[msg.sender][operator] &= ~access;
    }
  }

  function setApprovalsFor(address operator, uint256 access) external {
    _approvals[msg.sender][operator] = access;
  }

  function getApprovalsFor(address account, address operator) public view returns (uint256) {
    return _approvals[account][operator];
  }

  function isApprovedFor(
    address account,
    address operator,
    uint256 access
  ) public view returns (bool) {
    return _approvals[account][operator] & access == access;
  }

  function internalSetSpecialApprovals(address operator, uint256 access) internal {
    _approvals[address(0)][operator] = access;
  }

  function internalAddAsset(address token) internal {
    require(token != address(0));
    require(_tokens.add(token));

    CollateralAsset storage asset = _assets[token];
    asset.flags = AF_ADDED | AF_ALLOW_ALL;
  }

  function internalRemoveAsset(address token) internal {
    require(token != address(0));
    if (_tokens.remove(token)) {
      CollateralAsset storage asset = _assets[token];
      asset.flags = AF_ADDED;
    }
  }

  function deposit(
    address from,
    address to,
    address token,
    uint256 amount
  ) external onlyApproved(to, CollateralFundLib.APPROVED_DEPOSIT) onlySpecial(to, CollateralFundLib.APPROVED_DEPOSIT) {
    uint256 value = _deposit(_ensureActive(token, AF_ALLOW_DEPOSIT), from, token, amount);
    _collateral.mint(to, value);
  }

  function invest(
    address from,
    address to,
    address token,
    uint256 amount,
    address investTo
  ) external onlyApproved(to, CollateralFundLib.APPROVED_DEPOSIT | CollateralFundLib.APPROVED_INVEST) {
    uint256 value = _deposit(_ensureActive(token, AF_ALLOW_DEPOSIT), from, token, amount);
    _collateral.mintAndTransfer(to, investTo, value);
  }

  // function invest(
  //   address from,
  //   uint256 value,
  //   address investTo
  // ) external onlyApproved(from, CollateralFundLib.APPROVED_INVEST) {
  //   _collateral.transferTo(from, investTo, value);
  // }

  function _deposit(
    CollateralAsset storage asset,
    address from,
    address token,
    uint256 amount
  ) private returns (uint256 value) {
    IERC20(token).safeTransferFrom(from, address(this), amount);
    value = amount.wadMul(priceOf(asset, token));
    require((asset.totalAmount += uint128(amount)) >= amount);
    require((asset.totalValue += uint128(value)) >= value);
  }

  function priceOf(CollateralAsset storage asset, address token) internal view returns (uint256) {
    // TODO
  }

  function withdraw(
    address from,
    address to,
    address token,
    uint256 amount
  ) external onlyApproved(from, CollateralFundLib.APPROVED_WITHDRAW) {
    _withdraw(_ensureActive(token, AF_ALLOW_WITHDRAW), from, to, token, amount);
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
        (amount, x) = _withdrawValue(asset, value = _collateral.balanceOf(from));
        if (x > 0) {
          amount += x.wadDiv(priceOf(asset, token));
        }
      } else {
        (x, value) = _withdrawAmount(asset, amount);
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

  function _withdrawAmount(CollateralAsset storage asset, uint256 amount) internal virtual returns (uint256, uint256 value) {
    uint128 x = asset.totalAmount;
    (asset.totalAmount, asset.totalValue, amount, value) = _withdrawCalc(x, asset.totalValue, amount);
    return (amount, value);
  }

  function _withdrawValue(CollateralAsset storage asset, uint256 value) internal virtual returns (uint256 amount, uint256) {
    uint128 x = asset.totalValue;
    (asset.totalValue, asset.totalAmount, value, amount) = _withdrawCalc(x, asset.totalAmount, value);
    return (amount, value);
  }

  function _withdrawCalc(
    uint128 x0,
    uint128 y0,
    uint256 x
  )
    private
    pure
    returns (
      uint128,
      uint128,
      uint256,
      uint256 y
    )
  {
    if (x0 > x) {
      y = (uint256(y0) * x).divUp(x0);
      unchecked {
        x0 -= uint128(x);
        y0 -= uint128(y);
      }
    } else {
      unchecked {
        x -= x0;
      }
      y = y0;
      (x0, y0) = (0, 0);
    }
    return (x0, y0, x, y);
  }

  function _ensureActive(address token, uint8 moreFlags) private view returns (CollateralAsset storage asset) {
    asset = _assets[token];
    moreFlags |= AF_ADDED;
    require(asset.flags & (AF_SUSPENDED | moreFlags) == moreFlags);
  }

  function internalIsTrusted(
    CollateralAsset storage asset,
    address operator,
    address token
  ) internal view virtual returns (bool) {
    operator;
    return token == asset.trusted;
  }

  function _ensureTrusted(address token, uint8 moreFlags) private view returns (CollateralAsset storage asset) {
    asset = _ensureActive(token, moreFlags);
    require(token != address(0) && internalIsTrusted(asset, msg.sender, token));
  }

  function trustedDeposit(
    address from,
    address to,
    address token,
    uint256 amount
  ) external onlySpecial(to, CollateralFundLib.APPROVED_DEPOSIT) {
    uint256 value = _deposit(_ensureTrusted(token, AF_ALLOW_DEPOSIT), from, token, amount);
    _collateral.mint(to, value);
  }

  function trustedInvest(
    address from,
    address to,
    address token,
    uint256 amount,
    address investTo
  ) external {
    uint256 value = _deposit(_ensureTrusted(token, AF_ALLOW_DEPOSIT), from, token, amount);
    _collateral.mintAndTransfer(to, investTo, value);
  }

  function trustedWithdraw(
    address from,
    address to,
    address token,
    uint256 amount
  ) external {
    _withdraw(_ensureTrusted(token, AF_ALLOW_WITHDRAW), from, to, token, amount);
  }
}

library CollateralFundLib {
  uint8 internal constant APPROVED_DEPOSIT = 1 << 0;
  uint8 internal constant APPROVED_INVEST = 1 << 1;
  uint8 internal constant APPROVED_WITHDRAW = 1 << 2;
}
