// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../tools/SafeERC20.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/math/PercentageMath.sol';
import '../interfaces/IManagedCollateralCurrency.sol';
import '../interfaces/ICollateralBorrowManager.sol';
import '../access/AccessHelper.sol';
import './interfaces/ICollateralFund.sol';
import './Collateralized.sol';

abstract contract CollateralFundBase is ICollateralFund, AccessHelper {
  using SafeERC20 for IERC20;
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  IManagedCollateralCurrency private immutable _collateral;

  constructor(IAccessController acl, address collateral_) AccessHelper(acl) {
    _collateral = IManagedCollateralCurrency(collateral_);
  }

  struct CollateralAsset {
    uint8 flags; // TODO flags
    uint16 priceTolerance;
    uint64 priceTarget;
    address trusted;
  }

  struct BorrowBalance {
    uint128 amount;
    uint128 value;
  }

  uint8 private constant AF_ADDED = 1 << 7;

  EnumerableSet.AddressSet private _tokens;
  mapping(address => CollateralAsset) private _assets; // [token]
  mapping(address => mapping(address => BorrowBalance)) private _borrowedBalances; // [token][borrower]
  mapping(address => mapping(address => uint256)) private _approvals; // [owner][delegate]

  function _onlyApproved(
    address operator,
    address account,
    uint256 access
  ) private view {
    Access.require(operator == account || isApprovedFor(account, operator, access));
  }

  function _onlySpecial(address account, uint256 access) private view {
    Access.require(isApprovedFor(address(0), account, access));
  }

  modifier onlySpecial(address account, uint256 access) {
    _onlySpecial(account, access);
    _;
  }

  function setApprovalsFor(
    address operator,
    uint256 access,
    bool approved
  ) external override {
    if (approved) {
      _approvals[msg.sender][operator] |= access;
    } else {
      _approvals[msg.sender][operator] &= ~access;
    }
  }

  function collateral() public view override returns (address) {
    return address(_collateral);
  }

  function setAllApprovalsFor(address operator, uint256 access) external override {
    _approvals[msg.sender][operator] = access;
  }

  function getAllApprovalsFor(address account, address operator) public view override returns (uint256) {
    return _approvals[account][operator];
  }

  function isApprovedFor(
    address account,
    address operator,
    uint256 access
  ) public view override returns (bool) {
    return _approvals[account][operator] & access == access;
  }

  function internalSetSpecialApprovals(address operator, uint256 access) internal {
    _approvals[address(0)][operator] = access;
  }

  function internalSetTrusted(address token, address trusted) internal {
    CollateralAsset storage asset = _assets[token];
    State.require(asset.flags & AF_ADDED != 0);
    asset.trusted = trusted;
  }

  function internalSetFlags(address token, uint8 flags) internal {
    CollateralAsset storage asset = _assets[token];
    State.require(asset.flags & AF_ADDED != 0 && _tokens.contains(token));
    asset.flags = AF_ADDED | flags;
  }

  function internalAddAsset(
    address token,
    uint64 priceTarget,
    uint16 priceTolerance,
    address trusted
  ) internal virtual {
    Value.require(token != address(0));
    State.require(_tokens.add(token));

    _assets[token] = CollateralAsset({flags: type(uint8).max, priceTarget: priceTarget, priceTolerance: priceTolerance, trusted: trusted});
  }

  function internalRemoveAsset(address token) internal {
    if (token != address(0) && _tokens.remove(token)) {
      CollateralAsset storage asset = _assets[token];
      asset.flags = AF_ADDED;
    }
  }

  function deposit(
    address account,
    address token,
    uint256 tokenAmount
  ) external override onlySpecial(account, CollateralFundLib.APPROVED_DEPOSIT) {
    uint256 value = _deposit(_ensureApproved(account, token, CollateralFundLib.APPROVED_DEPOSIT), msg.sender, token, tokenAmount);
    _collateral.mint(account, value);
  }

  function invest(
    address account,
    address token,
    uint256 tokenAmount,
    address investTo
  ) external override {
    uint256 value = _deposit(
      _ensureApproved(account, token, CollateralFundLib.APPROVED_DEPOSIT | CollateralFundLib.APPROVED_INVEST),
      msg.sender,
      token,
      tokenAmount
    );
    _collateral.mintAndTransfer(account, investTo, value, 0);
  }

  function investIncludingDeposit(
    address account,
    uint256 depositValue,
    address token,
    uint256 tokenAmount,
    address investTo
  ) external override {
    uint256 value = _deposit(
      _ensureApproved(
        account,
        token,
        tokenAmount > 0 ? CollateralFundLib.APPROVED_DEPOSIT | CollateralFundLib.APPROVED_INVEST : CollateralFundLib.APPROVED_INVEST
      ),
      msg.sender,
      token,
      tokenAmount
    );
    _collateral.mintAndTransfer(account, investTo, value, depositValue);
  }

  function _deposit(
    CollateralAsset storage asset,
    address from,
    address token,
    uint256 amount
  ) private returns (uint256 value) {
    IERC20(token).safeTransferFrom(from, address(this), amount);
    value = amount.wadMul(_safePriceOf(asset, token));
  }

  function _safePriceOf(CollateralAsset storage asset, address token) private view returns (uint256 price) {
    price = internalPriceOf(token);

    uint256 target = asset.priceTarget;
    if ((target > price ? target - price : price - target) > target.percentMul(asset.priceTolerance)) {
      revert Errors.ExcessiveVolatility();
    }
  }

  function internalPriceOf(address token) internal view virtual returns (uint256);

  function withdraw(
    address account,
    address to,
    address token,
    uint256 amount
  ) external override {
    _withdraw(_ensureApproved(account, token, CollateralFundLib.APPROVED_WITHDRAW), account, to, token, amount);
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
      if (amount == type(uint256).max) {
        value = _collateral.balanceOf(from);
        if (value > 0) {
          amount = value.wadDiv(_safePriceOf(asset, token));
        }
      } else {
        value = amount.wadMul(_safePriceOf(asset, token));
      }

      if (value > 0) {
        _collateral.burn(from, value);
        IERC20(token).safeTransfer(to, amount);
      }
    }
  }

  function _ensureApproved(
    address account,
    address token,
    uint8 accessFlags
  ) private view returns (CollateralAsset storage asset) {
    return __ensureApproved(msg.sender, account, token, accessFlags);
  }

  function __ensureApproved(
    address operator,
    address account,
    address token,
    uint8 accessFlags
  ) private view returns (CollateralAsset storage asset) {
    _onlyApproved(operator, account, accessFlags);
    asset = _onlyActiveAsset(token, accessFlags);
  }

  function _onlyActiveAsset(address token, uint8 accessFlags) private view returns (CollateralAsset storage asset) {
    asset = _assets[token];
    uint8 flags = asset.flags;
    State.require(flags & AF_ADDED != 0);
    if (flags & accessFlags != accessFlags) {
      if (_tokens.contains(token)) {
        revert Errors.OperationPaused();
      } else {
        revert Errors.IllegalState();
      }
    }
  }

  function internalIsTrusted(
    CollateralAsset storage asset,
    address operator,
    address token
  ) internal view virtual returns (bool) {
    token;
    return operator == asset.trusted;
  }

  function _ensureTrusted(
    address operator,
    address account,
    address token,
    uint8 accessFlags
  ) private view returns (CollateralAsset storage asset) {
    asset = __ensureApproved(operator, account, token, accessFlags);
    Access.require(internalIsTrusted(asset, msg.sender, token));
  }

  function trustedDeposit(
    address from,
    address account,
    address token,
    uint256 amount
  ) external onlySpecial(account, CollateralFundLib.APPROVED_DEPOSIT) {
    uint256 value = _deposit(_ensureTrusted(from, account, token, CollateralFundLib.APPROVED_DEPOSIT), from, token, amount);
    _collateral.mint(account, value);
  }

  function trustedInvest(
    address from,
    address account,
    uint256 depositValue,
    address token,
    uint256 tokenAmount,
    address investTo
  ) external {
    uint256 value = _deposit(
      _ensureTrusted(
        from,
        account,
        token,
        tokenAmount > 0 ? CollateralFundLib.APPROVED_DEPOSIT | CollateralFundLib.APPROVED_INVEST : CollateralFundLib.APPROVED_INVEST
      ),
      from,
      token,
      tokenAmount
    );
    _collateral.mintAndTransfer(account, investTo, value, depositValue);
  }

  function trustedWithdraw(
    address operator,
    address account,
    address to,
    address token,
    uint256 amount
  ) external {
    _withdraw(_ensureTrusted(operator, account, token, CollateralFundLib.APPROVED_WITHDRAW), account, to, token, amount);
  }

  function setPaused(address token, bool paused) external onlyEmergencyAdmin {
    internalSetFlags(token, paused ? 0 : type(uint8).max);
  }

  function isPaused(address token) public view returns (bool) {
    return _assets[token].flags == type(uint8).max;
  }

  function setTrustedOperator(address token, address trusted) external aclHas(AccessFlags.LP_DEPLOY) {
    internalSetTrusted(token, trusted);
  }

  function setSpecialRoles(address operator, uint256 accessFlags) external aclHas(AccessFlags.LP_ADMIN) {
    internalSetSpecialApprovals(operator, accessFlags);
  }

  function addAsset(
    address token,
    uint64 priceTarget,
    uint16 priceTolerance,
    address trusted
  ) external aclHas(AccessFlags.LP_DEPLOY) {
    internalAddAsset(token, priceTarget, priceTolerance, trusted);
  }

  function removeAsset(address token) external aclHas(AccessFlags.LP_DEPLOY) {
    internalRemoveAsset(token);
  }

  function assets() external view override returns (address[] memory) {
    return _tokens.values();
  }

  function borrow(
    address token,
    uint256 amount,
    address to
  ) external {
    _onlyActiveAsset(token, CollateralFundLib.APPROVED_BORROW);
    Value.require(amount > 0);

    ICollateralBorrowManager bm = ICollateralBorrowManager(IManagedCollateralCurrency(collateral()).borrowManager());
    uint256 value = amount.wadMul(internalPriceOf(token));
    State.require(value > 0);
    State.require(bm.borrowUnderlying(msg.sender, value));

    BorrowBalance storage balance = _borrowedBalances[token][msg.sender];
    require((balance.amount += uint128(amount)) >= amount);
    require((balance.value += uint128(value)) >= value);

    SafeERC20.safeTransfer(IERC20(token), to, amount);
  }

  function repay(address token, uint256 amount) external {
    _onlyActiveAsset(token, CollateralFundLib.APPROVED_BORROW);
    Value.require(amount > 0);

    SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amount);

    BorrowBalance storage balance = _borrowedBalances[token][msg.sender];
    uint256 prevAmount = balance.amount;
    balance.amount = uint128(prevAmount - amount);

    uint256 prevValue = balance.value;
    uint256 value = (prevValue * amount) / prevAmount;
    balance.value = uint128(prevValue - value);

    ICollateralBorrowManager bm = ICollateralBorrowManager(IManagedCollateralCurrency(collateral()).borrowManager());
    State.require(bm.repayUnderlying(msg.sender, value));
  }
}

library CollateralFundLib {
  uint8 internal constant APPROVED_DEPOSIT = 1 << 0;
  uint8 internal constant APPROVED_INVEST = 1 << 1;
  uint8 internal constant APPROVED_WITHDRAW = 1 << 2;
  uint8 internal constant APPROVED_BORROW = 1 << 3;
}
