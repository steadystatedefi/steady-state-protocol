// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../tools/SafeERC20.sol';
import '../tools/math/Math.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/math/PercentageMath.sol';
import '../interfaces/IManagedCollateralCurrency.sol';
import '../access/AccessHelper.sol';

import '../access/AccessHelper.sol';
import './interfaces/ICollateralFund.sol';
import './Collateralized.sol';

abstract contract YieldStakerBase is AccessHelper, Collateralized {
  using SafeERC20 for IERC20;
  using Math for uint256;
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  EnumerableSet.AddressSet private _actuaries;

  uint128 private _timeIntegral;
  uint32 private _lastUpdatedAt;
  uint96 private _totalYieldRate;

  uint256 private _totalStakedCollateral;
  // uint256 private _totalInvestedCollateral;

  struct AssetBalance {
    uint16 flags;
    uint112 collateralFactor;
    uint128 balanceToken;
    uint128 totalIntegral;
    uint128 assetIntegral;
  }

  mapping(ICollateralizedAsset => AssetBalance) private _assetBalances;

  struct UserBalance {
    uint256 yieldBalance;
  }

  struct UserAssetBalance {
    uint128 assetIntegral;
    uint112 balanceToken;
    uint16 assetIndex;
  }

  mapping(address => UserBalance) private _userBalances;
  mapping(ICollateralizedAsset => mapping(address => UserAssetBalance)) private _userAssetBalances;
  mapping(address => mapping(uint16 => ICollateralizedAsset)) private _userAssets;

  function registerAsset(address asset) external onlyCollateralCurrency {}

  function _ensureActiveAsset(address asset) private {
    // _ensureActiveAsset(_assetBalances[ICollateralizedAsset(asset)].flags, false);
  }

  function _ensureActiveAsset(uint16 assetFlags, bool ignorePause) private {}

  function stake(
    address asset,
    uint256 amount,
    address to
  ) external {
    if (amount == type(uint256).max) {
      amount = ICollateralizedAsset(asset).balanceOf(msg.sender);
    }
    if (amount == 0) {
      _ensureActiveAsset(asset);
      return;
    }

    SafeERC20.safeTransferFrom(ICollateralizedAsset(asset), msg.sender, address(this), amount);

    _updateAssetAndUser(ICollateralizedAsset(asset), amount.asUint112(), 0, to);
  }

  function unstake(
    address asset,
    uint256 amount,
    address to
  ) external {
    if (amount == type(uint256).max) {
      amount = _userAssetBalances[ICollateralizedAsset(asset)][msg.sender].balanceToken;
    }
    if (amount == 0) {
      Value.require(to != address(0));
      _ensureActiveAsset(asset);
      return;
    }

    _updateAssetAndUser(ICollateralizedAsset(asset), 0, amount.asUint112(), msg.sender);
    SafeERC20.safeTransfer(ICollateralizedAsset(asset), to, amount);
  }

  function syncAsset(address a) external {
    ICollateralizedAsset asset = ICollateralizedAsset(a);
    _syncAsset(asset, asset.totalSupply(), asset.collateralSupply(), false);
  }

  function syncByAsset(uint256 assetSupply, uint256 collateralSupply) external {
    _syncAsset(ICollateralizedAsset(msg.sender), assetSupply, collateralSupply, true);
  }

  function _syncAsset(
    ICollateralizedAsset asset,
    uint256 assetSupply,
    uint256 collateralSupply,
    bool ignorePause
  ) private {
    uint256 collateralFactor = collateralSupply.rayDiv(assetSupply);
    if (_assetBalances[asset].collateralFactor == collateralFactor) {
      return;
    }

    _syncAsset(asset, collateralFactor, 0, 0, ignorePause);
  }

  function _syncAsset(
    ICollateralizedAsset asset,
    uint256 collateralFactor,
    uint128 incAmount,
    uint128 decAmount,
    bool ignorePause
  ) private returns (uint128) {
    AssetBalance memory assetBalance = _assetBalances[asset];
    _ensureActiveAsset(assetBalance.flags, ignorePause);

    uint256 prevCollateral = uint256(assetBalance.balanceToken).rayMul(assetBalance.collateralFactor);

    uint256 totalIntegral = _timeIntegral;
    uint256 totalCollateralBalance;
    {
      uint256 timeDelta = uint32(block.timestamp) - _lastUpdatedAt;
      if (timeDelta != 0) {
        totalIntegral = totalIntegral + (_totalYieldRate * timeDelta).rayDiv(totalCollateralBalance = _totalStakedCollateral);

        _timeIntegral = totalIntegral.asUint128();
        _lastUpdatedAt = uint32(block.timestamp);
      }
    }

    {
      uint256 d = totalIntegral - assetBalance.totalIntegral;
      if (d != 0) {
        assetBalance.totalIntegral = totalIntegral.asUint128();
        assetBalance.assetIntegral += d.rayMul(assetBalance.collateralFactor).asUint128();
      }
    }

    assetBalance.collateralFactor = collateralFactor.asUint112();
    assetBalance.balanceToken = assetBalance.balanceToken + incAmount - decAmount;

    _assetBalances[asset] = assetBalance;

    uint256 newCollateral = uint256(assetBalance.balanceToken).rayMul(collateralFactor);

    if (newCollateral != prevCollateral) {
      if (totalCollateralBalance == 0) {
        totalCollateralBalance = _totalStakedCollateral;
      }
      internalOnStakedCollateralChanged(
        totalCollateralBalance,
        _totalStakedCollateral = totalCollateralBalance.addDelta(newCollateral, prevCollateral)
      );
    }

    return assetBalance.assetIntegral;
  }

  function internalOnStakedCollateralChanged(uint256 prevStaked, uint256 newStaked) internal virtual {}

  function _updateAssetAndUser(
    ICollateralizedAsset asset,
    uint112 incAmount,
    uint112 decAmount,
    address account
  ) private {
    uint256 collateralFactor = asset.collateralSupply().rayDiv(asset.totalSupply());
    uint128 assetIntegral = _syncAsset(asset, collateralFactor, incAmount, decAmount, false);

    Value.require(account != address(0));

    UserAssetBalance storage balance = _userAssetBalances[asset][account];

    uint256 d = assetIntegral - balance.assetIntegral;
    uint112 balanceToken = balance.balanceToken;

    if (d != 0) {
      balance.assetIntegral = assetIntegral;
      if (balanceToken != 0) {
        _userBalances[account].yieldBalance += d.rayMul(balanceToken);
      }
    }

    internalTrackUserAssets(asset, account, balanceToken, balance.balanceToken = (balanceToken - decAmount) + incAmount);
  }

  function internalTrackUserAssets(
    ICollateralizedAsset asset,
    address account,
    uint256 balanceBefore,
    uint256 balanceAfter
  ) internal virtual {}

  function balanceOf(address account) external view returns (uint256) {
    return _userBalances[account].yieldBalance;
  }

  function stakeOf(address asset, address account) external view returns (uint256) {
    return _userAssetBalances[ICollateralizedAsset(asset)][account].balanceToken;
  }

  function claimYield(address account, address[] calldata assets) external view returns (uint256) {}

  modifier onlyYieldAccountant() {
    _;
  }

  function addYield(
    address token,
    uint256 amount,
    uint256 anticipatedRate,
    uint32 anticipatedTill
  ) external onlyYieldAccountant {
    // Value.require(_delegates[token] == address(0));
    // SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amount);
    // uint256 totalReportedBalance = _totalReportedBalance;
    // if (totalReportedBalance > 0) {
    //   CalcWeightedRateLib.TotalState memory totalRate = _totalRate;
    //   for (uint256 i = _actuaries.length();i > 0;) {
    //     i--;
    //     _addAssetYield(_actuaries.at(i), totalRate, totalReportedBalance, token, amount, anticipatedRate);
    //   }
    // } else {
    //   // remember yield
    // }
  }

  // function reportCollateralBalance(uint256 balance) external override {
  //   Access.require(_actuaries.contains(msg.sender));
  //   _reportCollateralBalance(msg.sender, balance);
  // }

  // function _reportCollateralBalance(address asset, uint256 balance) private {
  //   uint256 prevBalance = _assetBalances[asset];
  //   if (balance != prevBalance) {
  //     _assetBalances[asset] = balance;

  //     uint256 totalBalance = _totalReportedBalance;
  //     _totalRate.syncTotalState(totalBalance, uint32(block.timestamp));
  //     _totalReportedBalance = totalBalance.addDelta(balance, prevBalance);
  //   }
  // }

  // function getYieldBalance() external view override returns (uint256 yieldBalance, uint256 yieldRate) {

  // }
}

interface ICollateralizedAsset is ICollateralized, IERC20 {
  function collateralSupply() external returns (uint256);
}
