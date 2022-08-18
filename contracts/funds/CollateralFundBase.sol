// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../tools/SafeERC20.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/math/PercentageMath.sol';
import '../interfaces/IManagedCollateralCurrency.sol';
import '../interfaces/ICollateralStakeManager.sol';
import '../pricing/PricingHelper.sol';
import '../access/AccessHelper.sol';
import './interfaces/ICollateralFund.sol';
import './Collateralized.sol';

// TODO:TEST tests for zero return on price lockup

abstract contract CollateralFundBase is ICollateralFund, AccessHelper, PricingHelper {
  using SafeERC20 for IERC20;
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  IManagedCollateralCurrency private immutable _collateral;
  uint256 private immutable _sourceFuses;

  constructor(
    IAccessController acl,
    address collateral_,
    uint256 sourceFuses
  ) AccessHelper(acl) PricingHelper(_getPricerByAcl(acl)) {
    _collateral = IManagedCollateralCurrency(collateral_);
    _sourceFuses = sourceFuses;
  }

  struct CollateralAsset {
    uint8 assetFlags;
    address trustee;
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

  function remoteAcl() internal view override(AccessHelper, PricingHelper) returns (IAccessController pricer) {
    return AccessHelper.remoteAcl();
  }

  event ApprovalFor(address indexed owner, address indexed operator, uint256 approved);

  function setApprovalsFor(
    address operator,
    uint256 access,
    bool approved
  ) external override {
    uint256 flags;
    if (approved) {
      flags = (_approvals[msg.sender][operator] |= access);
    } else {
      flags = (_approvals[msg.sender][operator] &= ~access);
    }
    emit ApprovalFor(msg.sender, operator, flags);
  }

  function collateral() public view override returns (address) {
    return address(_collateral);
  }

  function setAllApprovalsFor(address operator, uint256 access) external override {
    _approvals[msg.sender][operator] = access;
    emit ApprovalFor(msg.sender, operator, access);
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

  event SpecialApprovalFor(address indexed operator, uint256 approved);

  function internalSetSpecialApprovals(address operator, uint256 access) internal {
    _approvals[address(0)][operator] = access;
    emit SpecialApprovalFor(operator, access);
  }

  event TrusteeUpdated(address indexed token, address indexed trustedOperator);

  function internalSetTrustee(address token, address trustee) internal {
    CollateralAsset storage asset = _assets[token];
    State.require(asset.assetFlags & AF_ADDED != 0);
    asset.trustee = trustee;
    emit TrusteeUpdated(token, trustee);
  }

  function internalSetFlags(address token, uint8 flags) internal {
    CollateralAsset storage asset = _assets[token];
    State.require(asset.assetFlags & AF_ADDED != 0 && _tokens.contains(token));
    asset.assetFlags = AF_ADDED | flags;
  }

  event AssetAdded(address indexed token);
  event AssetRemoved(address indexed token);

  function internalAddAsset(address token, address trustee) internal virtual {
    Value.require(token != address(0));
    State.require(_tokens.add(token));

    _assets[token] = CollateralAsset({assetFlags: type(uint8).max, trustee: trustee});
    _attachSource(token, true);

    emit AssetAdded(token);
    if (trustee != address(0)) {
      emit TrusteeUpdated(token, trustee);
    }
  }

  function internalRemoveAsset(address token) internal {
    if (token != address(0) && _tokens.remove(token)) {
      CollateralAsset storage asset = _assets[token];
      asset.assetFlags = AF_ADDED;
      _attachSource(token, false);

      emit AssetRemoved(token);
    }
  }

  function _attachSource(address token, bool set) private {
    IManagedPriceRouter pricer = getPricer();
    if (address(pricer) != address(0)) {
      pricer.attachSource(token, set);
    }
  }

  function deposit(
    address account,
    address token,
    uint256 tokenAmount
  ) external override returns (uint256) {
    _ensureApproved(account, token, CollateralFundLib.APPROVED_DEPOSIT);
    return _depositAndMint(msg.sender, account, token, tokenAmount);
  }

  function invest(
    address account,
    address token,
    uint256 tokenAmount,
    address investTo
  ) external override returns (uint256) {
    _ensureApproved(account, token, CollateralFundLib.APPROVED_DEPOSIT | CollateralFundLib.APPROVED_INVEST);
    return _depositAndInvest(msg.sender, account, 0, token, tokenAmount, investTo);
  }

  function investIncludingDeposit(
    address account,
    uint256 depositValue,
    address token,
    uint256 tokenAmount,
    address investTo
  ) external override returns (uint256) {
    _ensureApproved(
      account,
      token,
      tokenAmount > 0 ? CollateralFundLib.APPROVED_DEPOSIT | CollateralFundLib.APPROVED_INVEST : CollateralFundLib.APPROVED_INVEST
    );
    return _depositAndInvest(msg.sender, account, depositValue, token, tokenAmount, investTo);
  }

  function internalPriceOf(address token) internal virtual returns (uint256) {
    return getPricer().pullAssetPrice(token, _sourceFuses);
  }

  function withdraw(
    address account,
    address to,
    address token,
    uint256 amount
  ) external override returns (uint256) {
    _ensureApproved(account, token, CollateralFundLib.APPROVED_WITHDRAW);
    return _withdraw(account, to, token, amount);
  }

  event AssetWithdrawn(address indexed token, address indexed account, uint256 amount, uint256 value);

  function _withdraw(
    address from,
    address to,
    address token,
    uint256 amount
  ) private returns (uint256) {
    if (amount > 0) {
      uint256 value;
      if (amount == type(uint256).max) {
        value = _collateral.balanceOf(from);
        if (value > 0) {
          uint256 price = internalPriceOf(token);
          if (price != 0) {
            amount = value.wadDiv(price);
          } else {
            value = 0;
          }
        }
      } else {
        value = amount.wadMul(internalPriceOf(token));
      }

      if (value > 0) {
        _collateral.burn(from, value);
        IERC20(token).safeTransfer(to, amount);

        emit AssetWithdrawn(token, from, amount, value);
        return amount;
      }
    }

    return 0;
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
    uint8 flags = asset.assetFlags;
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
    return operator == asset.trustee;
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

  event AssetDeposited(address indexed token, address indexed account, uint256 amount, uint256 value);

  function __deposit(
    address from,
    address token,
    uint256 amount
  ) private returns (uint256 value, bool ok) {
    uint256 price = internalPriceOf(token);
    if (price != 0) {
      IERC20(token).safeTransferFrom(from, address(this), amount);
      value = amount.wadMul(price);
      ok = true;
    }
  }

  function _depositAndMint(
    address operator,
    address account,
    address token,
    uint256 tokenAmount
  ) private onlySpecial(account, CollateralFundLib.APPROVED_DEPOSIT) returns (uint256) {
    (uint256 value, bool ok) = __deposit(operator, token, tokenAmount);
    if (ok) {
      emit AssetDeposited(token, account, tokenAmount, value);
      _collateral.mint(account, value);
      return value;
    }
    return 0;
  }

  function _depositAndInvest(
    address operator,
    address account,
    uint256 depositValue,
    address token,
    uint256 tokenAmount,
    address investTo
  ) private returns (uint256) {
    (uint256 value, bool ok) = __deposit(operator, token, tokenAmount);
    if (ok) {
      emit AssetDeposited(token, account, tokenAmount, value);
      _collateral.mintAndTransfer(account, investTo, value, depositValue);
      return value + depositValue;
    }
    return 0;
  }

  function trustedDeposit(
    address operator,
    address account,
    address token,
    uint256 amount
  ) external returns (uint256) {
    _ensureTrusted(operator, account, token, CollateralFundLib.APPROVED_DEPOSIT);
    return _depositAndMint(operator, account, token, amount);
  }

  function trustedInvest(
    address operator,
    address account,
    uint256 depositValue,
    address token,
    uint256 tokenAmount,
    address investTo
  ) external returns (uint256) {
    _ensureTrusted(
      operator,
      account,
      token,
      tokenAmount > 0 ? CollateralFundLib.APPROVED_DEPOSIT | CollateralFundLib.APPROVED_INVEST : CollateralFundLib.APPROVED_INVEST
    );

    return _depositAndInvest(operator, account, depositValue, token, tokenAmount, investTo);
  }

  function trustedWithdraw(
    address operator,
    address account,
    address to,
    address token,
    uint256 amount
  ) external returns (uint256) {
    _ensureTrusted(operator, account, token, CollateralFundLib.APPROVED_WITHDRAW);
    return _withdraw(account, to, token, amount);
  }

  event AssetPaused(address indexed token, bool paused);

  function setPaused(address token, bool paused) external onlyEmergencyAdmin {
    internalSetFlags(token, paused ? 0 : type(uint8).max);
    emit AssetPaused(token, paused);
  }

  function isPaused(address token) public view returns (bool) {
    return _assets[token].assetFlags == type(uint8).max;
  }

  function setTrustedOperator(address token, address trustee) external aclHas(AccessFlags.LP_DEPLOY) {
    internalSetTrustee(token, trustee);
  }

  function setSpecialRoles(address operator, uint256 accessFlags) external aclHas(AccessFlags.LP_ADMIN) {
    internalSetSpecialApprovals(operator, accessFlags);
  }

  function _attachToken(address token, bool attach) private {
    IManagedPriceRouter pricer = getPricer();
    if (address(pricer) != address(0)) {
      pricer.attachSource(token, attach);
    }
  }

  function addAsset(address token, address trusted) external aclHas(AccessFlags.LP_DEPLOY) {
    internalAddAsset(token, trusted);
    _attachToken(token, true);
  }

  function removeAsset(address token) external aclHas(AccessFlags.LP_DEPLOY) {
    internalRemoveAsset(token);
    _attachToken(token, false);
  }

  function assets() external view override returns (address[] memory) {
    return _tokens.values();
  }

  event AssetBorrowed(address indexed token, uint256 amount, address to);
  event AssetReplenished(address indexed token, uint256 amount);

  function borrow(
    address token,
    uint256 amount,
    address to
  ) external {
    _onlyActiveAsset(token, CollateralFundLib.APPROVED_BORROW);
    Value.require(amount > 0);

    ICollateralStakeManager bm = ICollateralStakeManager(IManagedCollateralCurrency(collateral()).borrowManager());
    uint256 value = amount.wadMul(internalPriceOf(token));
    State.require(value > 0);
    State.require(bm.verifyBorrowUnderlying(msg.sender, value));

    BorrowBalance storage balance = _borrowedBalances[token][msg.sender];
    require((balance.amount += uint128(amount)) >= amount);
    require((balance.value += uint128(value)) >= value);

    SafeERC20.safeTransfer(IERC20(token), to, amount);

    emit AssetBorrowed(token, amount, to);
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

    ICollateralStakeManager bm = ICollateralStakeManager(IManagedCollateralCurrency(collateral()).borrowManager());
    State.require(bm.verifyRepayUnderlying(msg.sender, value));

    emit AssetReplenished(token, amount);
  }

  function resetPriceGuard() external aclHasAny(AccessFlags.LP_ADMIN) {
    getPricer().resetSourceGroup();
  }
}

library CollateralFundLib {
  uint8 internal constant APPROVED_DEPOSIT = 1 << 0;
  uint8 internal constant APPROVED_INVEST = 1 << 1;
  uint8 internal constant APPROVED_WITHDRAW = 1 << 2;
  uint8 internal constant APPROVED_BORROW = 1 << 3;
}
