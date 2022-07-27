// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../tools/SafeERC20.sol';
import '../tools/math/Math.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/math/PercentageMath.sol';
import '../interfaces/IManagedCollateralCurrency.sol';
import '../interfaces/ICollateralBorrowManager.sol';
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

  uint128 private _totalStakedCollateral;
  uint128 private _totalBorrowedCollateral;

  struct AssetBalance {
    uint16 flags;
    uint112 collateralFactor;
    uint128 balanceToken;
    uint128 totalIntegral;
    uint128 assetIntegral;
  }

  mapping(ICollateralizedAsset => AssetBalance) private _assetBalances;

  struct UserBalance {
    uint128 yieldBalance;
    uint16 assetCount;
  }

  struct UserAssetBalance {
    uint128 assetIntegral;
    uint112 balanceToken;
    uint16 assetIndex;
  }

  mapping(address => UserBalance) private _userBalances;
  mapping(ICollateralizedAsset => mapping(address => UserAssetBalance)) private _userAssetBalances;
  mapping(address => mapping(uint256 => ICollateralizedAsset)) private _userAssets;

  function registerAsset(address asset) external onlyCollateralCurrency {
    // TODO
  }

  function _ensureActiveAsset(address asset) private view {
    // _ensureActiveAsset(_assetBalances[ICollateralizedAsset(asset)].flags, false);
  }

  function _ensureActiveAsset(uint16 assetFlags, bool ignorePause) private view {
    // TODO State.require(assetFlags)
  }

  function stake(
    address asset,
    uint256 amount,
    address to
  ) external {
    Value.require(to != address(0));

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
    Value.require(to != address(0));

    if (amount == type(uint256).max) {
      amount = _userAssetBalances[ICollateralizedAsset(asset)][msg.sender].balanceToken;
    }
    if (amount == 0) {
      _ensureActiveAsset(asset);
      return;
    }

    _updateAssetAndUser(ICollateralizedAsset(asset), 0, amount.asUint112(), msg.sender);
    SafeERC20.safeTransfer(ICollateralizedAsset(asset), to, amount);
  }

  function syncAsset(address a) external {
    ICollateralizedAsset asset = ICollateralizedAsset(a);
    _updateAsset(asset, asset.totalSupply(), asset.collateralSupply(), false);
  }

  function syncByAsset(uint256 assetSupply, uint256 collateralSupply) external {
    _updateAsset(ICollateralizedAsset(msg.sender), assetSupply, collateralSupply, true);
  }

  function _updateAsset(
    ICollateralizedAsset asset,
    uint256 assetSupply,
    uint256 collateralSupply,
    bool ignorePause
  ) private {
    uint256 collateralFactor = collateralSupply.rayDiv(assetSupply);
    if (_assetBalances[asset].collateralFactor == collateralFactor) {
      return;
    }

    _updateAsset(asset, collateralFactor, 0, 0, ignorePause);
  }

  function internalGetTimeIntegral() internal view virtual returns (uint256 totalIntegral, uint32 lastUpdatedAt);

  function internalSetTimeIntegral(uint256 totalIntegral, uint32 lastUpdatedAt) internal virtual;

  function internalGetRateIntegral(uint32 from, uint32 till) internal virtual returns (uint256);

  function internalCalcRateIntegral(uint32 from, uint32 till) internal view virtual returns (uint256);

  function internalAddYieldExcess(uint256 value) internal virtual {
    _updateTotal(value);
  }

  function _syncTotal() private view returns (uint256 totalIntegral) {
    uint32 lastUpdatedAt;
    (totalIntegral, lastUpdatedAt) = internalGetTimeIntegral();

    uint32 at = uint32(block.timestamp);
    if (at != lastUpdatedAt) {
      totalIntegral += internalCalcRateIntegral(lastUpdatedAt, at).rayDiv(_totalStakedCollateral);
    }
  }

  function _updateTotal(uint256 extra) private returns (uint256 totalIntegral, uint256 totalStaked) {
    uint32 lastUpdatedAt;
    (totalIntegral, lastUpdatedAt) = internalGetTimeIntegral();

    uint32 at = uint32(block.timestamp);
    if (at != lastUpdatedAt) {
      totalIntegral += (extra + internalGetRateIntegral(lastUpdatedAt, at)).rayDiv(totalStaked = _totalStakedCollateral);
      internalSetTimeIntegral(totalIntegral, uint32(block.timestamp));
    }
  }

  function _syncAsset(
    AssetBalance memory assetBalance,
    bool ignorePause,
    uint256 totalIntegral
  ) private view {
    _ensureActiveAsset(assetBalance.flags, ignorePause);

    uint256 d = totalIntegral - assetBalance.totalIntegral;
    if (d != 0) {
      assetBalance.totalIntegral = totalIntegral.asUint128();
      assetBalance.assetIntegral += d.rayMul(assetBalance.collateralFactor).asUint128();
    }
  }

  function _syncAsset(
    ICollateralizedAsset asset,
    bool ignorePause,
    uint256 totalIntegral
  ) private view returns (AssetBalance memory assetBalance) {
    assetBalance = _assetBalances[asset];
    _syncAsset(assetBalance, ignorePause, totalIntegral);
  }

  function _updateAsset(
    ICollateralizedAsset asset,
    uint256 collateralFactor,
    uint128 incAmount,
    uint128 decAmount,
    bool ignorePause
  ) private returns (uint128) {
    AssetBalance memory assetBalance = _assetBalances[asset];

    (uint256 totalIntegral, uint256 totalStaked) = _updateTotal(0);

    uint256 prevCollateral = uint256(assetBalance.balanceToken).rayMul(assetBalance.collateralFactor);

    _syncAsset(assetBalance, ignorePause, totalIntegral);
    assetBalance.collateralFactor = collateralFactor.asUint112();
    assetBalance.balanceToken = (assetBalance.balanceToken - decAmount) + incAmount;

    uint256 newCollateral = uint256(assetBalance.balanceToken).rayMul(collateralFactor);

    _assetBalances[asset] = assetBalance;

    if (newCollateral != prevCollateral) {
      if (totalStaked == 0) {
        totalStaked = _totalStakedCollateral;
      }
      internalOnStakedCollateralChanged(totalStaked, _totalStakedCollateral = totalStaked.addDelta(newCollateral, prevCollateral).asUint128());
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
    uint128 assetIntegral = _updateAsset(asset, collateralFactor, incAmount, decAmount, false);

    Value.require(account != address(0));

    UserAssetBalance storage balance = _userAssetBalances[asset][account];

    uint256 d = assetIntegral - balance.assetIntegral;
    uint112 balanceToken = balance.balanceToken;

    if (d != 0 && balanceToken != 0) {
      balance.assetIntegral = assetIntegral;
      _userBalances[account].yieldBalance += d.rayMul(balanceToken).asUint128();
    }

    mapping(uint256 => ICollateralizedAsset) storage listing = _userAssets[account];

    uint256 balanceAfter = (balanceToken - decAmount) + incAmount;
    if (balanceAfter == 0) {
      if (balanceToken != 0) {
        // remove asset
        uint16 index = _userBalances[account].assetCount--;
        uint16 assetIndex = balance.assetIndex;
        if (assetIndex != index) {
          State.require(assetIndex < index);
          ICollateralizedAsset a = listing[assetIndex] = listing[index];
          _userAssetBalances[a][account].assetIndex = assetIndex;
        } else {
          delete _userAssetBalances[asset][account];
          delete listing[assetIndex];
        }
      }
    } else if (balanceToken == 0) {
      // add asset
      uint16 index = ++_userBalances[account].assetCount;
      balance.assetIndex = index;
      _userAssets[account][index] = asset;
    }
    balance.balanceToken = balanceAfter.asUint112();
  }

  function balanceOf(address account) external view returns (uint256 yieldBalance) {
    if (account == address(0)) {
      return 0;
    }

    UserBalance storage ub = _userBalances[account];
    mapping(uint256 => ICollateralizedAsset) storage listing = _userAssets[account];

    yieldBalance = ub.yieldBalance;
    uint256 totalIntegral = _syncTotal();

    for (uint256 i = ub.assetCount; i > 0; i--) {
      ICollateralizedAsset asset = listing[i];
      State.require(address(asset) != address(0));

      AssetBalance memory assetBalance = _syncAsset(asset, true, totalIntegral);

      UserAssetBalance storage balance = _userAssetBalances[asset][account];

      uint256 d = assetBalance.assetIntegral - balance.assetIntegral;
      if (d != 0) {
        uint112 balanceToken = balance.balanceToken;
        if (balanceToken != 0) {
          yieldBalance += d.rayMul(balanceToken);
        }
      }
    }
  }

  function stakedBalanceOf(address account, address asset) external view returns (uint256) {
    return _userAssetBalances[ICollateralizedAsset(asset)][account].balanceToken;
  }

  function claimYield(address to) external returns (uint256) {
    address account = msg.sender;
    (uint256 yieldBalance, uint256 i) = _claimCollectedYield(account);

    (uint256 totalIntegral, ) = _updateTotal(0);
    mapping(uint256 => ICollateralizedAsset) storage listing = _userAssets[account];

    for (; i > 0; i--) {
      ICollateralizedAsset asset = listing[i];
      State.require(address(asset) != address(0));
      yieldBalance += _claimYield(asset, account, totalIntegral);
    }

    return _mintYield(account, yieldBalance, to);
  }

  function claimYieldFrom(address to, address[] calldata assets) external returns (uint256) {
    address account = msg.sender;
    (uint256 yieldBalance, ) = _claimCollectedYield(account);

    (uint256 totalIntegral, ) = _updateTotal(0);

    for (uint256 i = assets.length; i > 0; ) {
      i--;
      address asset = assets[i];
      Value.require(asset != address(0));
      yieldBalance += _claimYield(ICollateralizedAsset(asset), account, totalIntegral);
    }

    return _mintYield(account, yieldBalance, to);
  }

  function _claimCollectedYield(address account) private returns (uint256 yieldBalance, uint16) {
    Value.require(account != address(0));

    UserBalance storage ub = _userBalances[account];
    yieldBalance = ub.yieldBalance;
    if (yieldBalance > 0) {
      _userBalances[account].yieldBalance = 0;
    }
    return (yieldBalance, ub.assetCount);
  }

  function _claimYield(
    ICollateralizedAsset asset,
    address account,
    uint256 totalIntegral
  ) private returns (uint256 yieldBalance) {
    AssetBalance memory assetBalance = _syncAsset(asset, false, totalIntegral);
    UserAssetBalance storage balance = _userAssetBalances[asset][account];

    uint256 d = assetBalance.assetIntegral - balance.assetIntegral;

    if (d != 0) {
      uint112 balanceToken = balance.balanceToken;
      if (balanceToken != 0) {
        _assetBalances[asset] = assetBalance;
        balance.assetIntegral = assetBalance.assetIntegral;

        yieldBalance = d.rayMul(balanceToken);
      }
    }
  }

  function _mintYield(
    address account,
    uint256 amount,
    address to
  ) private returns (uint256) {
    if (amount > 0) {
      IERC20 cc = IERC20(collateral());
      uint256 availableYield = cc.balanceOf(address(this));
      if (availableYield < amount) {
        if (internalPullYield(availableYield, amount)) {
          availableYield = cc.balanceOf(address(this));
        }
        if (availableYield < amount) {
          _userBalances[account].yieldBalance += (amount - availableYield).asUint128();
          amount = availableYield;
        }
        if (amount == 0) {
          return 0;
        }
      }
      cc.safeTransfer(address(to), amount);
    }
    return amount;
  }

  function internalPullYield(uint256 availableYield, uint256 requestedYield) internal virtual returns (bool);

  function totalStakedCollateral() public view returns (uint256) {
    return _totalStakedCollateral;
  }

  function totalBorrowedCollateral() external view returns (uint256) {
    return _totalBorrowedCollateral;
  }

  function internalApplyBorrow(uint256 value) internal {
    uint256 totalBorrowed = _totalBorrowedCollateral + value;
    State.require(totalBorrowed <= _totalStakedCollateral);
    _totalBorrowedCollateral = totalBorrowed.asUint128();
  }

  function internalApplyRepay(uint256 value) internal {
    _totalBorrowedCollateral = uint128(_totalBorrowedCollateral - value);
  }
}

interface ICollateralizedAsset is ICollateralized, IERC20 {
  function collateralSupply() external returns (uint256);
}
