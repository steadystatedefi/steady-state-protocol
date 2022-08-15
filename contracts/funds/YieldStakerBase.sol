// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../tools/SafeERC20.sol';
import '../tools/math/Math.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/math/PercentageMath.sol';
import '../interfaces/IManagedCollateralCurrency.sol';
import '../interfaces/ICollateralStakeManager.sol';
import '../interfaces/IYieldStakeAsset.sol';
import '../access/AccessHelper.sol';

import '../access/AccessHelper.sol';
import './interfaces/ICollateralFund.sol';
import './Collateralized.sol';

abstract contract YieldStakerBase is ICollateralStakeManager, AccessHelper, Collateralized {
  using SafeERC20 for IERC20;
  using Math for uint256;
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  uint128 private _totalStakedCollateral;
  uint128 private _totalBorrowedCollateral;

  uint16 private constant FLAG_ASSET_PRESENT = 1 << 0;
  uint16 private constant FLAG_ASSET_REMOVED = 1 << 1;
  uint16 private constant FLAG_ASSET_PAUSED = 1 << 2;

  struct AssetBalance {
    uint16 flags;
    uint112 collateralFactor;
    uint128 stakedTokenTotal;
    uint128 totalIntegral;
    uint128 assetIntegral;
  }

  mapping(IYieldStakeAsset => AssetBalance) private _assetBalances;

  struct UserBalance {
    uint128 yieldBalance;
    uint16 assetCount;
  }

  struct UserAssetBalance {
    uint128 assetIntegral;
    uint112 stakedTokenAmount;
    uint16 assetIndex;
  }

  mapping(address => UserBalance) private _userBalances;
  mapping(IYieldStakeAsset => mapping(address => UserAssetBalance)) private _userAssetBalances;
  mapping(address => mapping(uint256 => IYieldStakeAsset)) private _userAssets;

  function internalAddAsset(address asset) internal {
    Value.require(IYieldStakeAsset(asset).collateral() == collateral());

    AssetBalance storage assetBalance = _assetBalances[IYieldStakeAsset(asset)];
    State.require(assetBalance.flags == 0);

    assetBalance.flags = FLAG_ASSET_PRESENT;
  }

  function internalRemoveAsset(address asset) internal {
    AssetBalance storage assetBalance = _assetBalances[IYieldStakeAsset(asset)];
    uint16 flags = assetBalance.flags;
    if (flags & (FLAG_ASSET_PRESENT | FLAG_ASSET_REMOVED) == FLAG_ASSET_PRESENT) {
      _updateAsset(IYieldStakeAsset(asset), 1, 0, true);
      assetBalance.flags = flags | FLAG_ASSET_REMOVED | FLAG_ASSET_PAUSED;
    }
  }

  function internalPauseAsset(address asset, bool paused) internal {
    AssetBalance storage assetBalance = _assetBalances[IYieldStakeAsset(asset)];
    uint16 flags = assetBalance.flags;
    State.require(flags & FLAG_ASSET_PRESENT != 0);
    assetBalance.flags = paused ? flags | FLAG_ASSET_PAUSED : flags & ~uint16(FLAG_ASSET_PAUSED);
  }

  function internalIsAssetPaused(address asset) internal view returns (bool) {
    AssetBalance storage assetBalance = _assetBalances[IYieldStakeAsset(asset)];
    return assetBalance.flags & FLAG_ASSET_PAUSED != 0;
  }

  function _ensureActiveAsset(uint16 assetFlags, bool ignorePause) private pure {
    State.require(
      (assetFlags & (ignorePause ? FLAG_ASSET_PRESENT | FLAG_ASSET_REMOVED : FLAG_ASSET_PRESENT | FLAG_ASSET_REMOVED | FLAG_ASSET_PAUSED) ==
        FLAG_ASSET_PRESENT)
    );
  }

  function _ensureUnpausedAsset(address asset, bool mustBeActive) private view {
    _ensureUnpausedAsset(_assetBalances[IYieldStakeAsset(asset)].flags, mustBeActive);
  }

  function _ensureUnpausedAsset(uint16 assetFlags, bool mustBeActive) private pure {
    State.require(
      (assetFlags & (mustBeActive ? FLAG_ASSET_PRESENT | FLAG_ASSET_REMOVED : FLAG_ASSET_PRESENT | FLAG_ASSET_PAUSED) == FLAG_ASSET_PRESENT)
    );
  }

  modifier onlyUnpausedAsset(address asset, bool active) {
    _ensureUnpausedAsset(asset, active);
    _;
  }

  function stake(
    address asset,
    uint256 amount,
    address to
  ) external onlyUnpausedAsset(asset, true) {
    Value.require(to != address(0));

    if (amount == type(uint256).max) {
      if ((amount = IERC20(asset).balanceOf(msg.sender)) > 0) {
        uint256 max = IERC20(asset).allowance(msg.sender, address(this));
        if (amount > max) {
          amount = max;
        }
      }
    }
    if (amount == 0) {
      return;
    }

    SafeERC20.safeTransferFrom(IERC20(asset), msg.sender, address(this), amount);

    _updateAssetAndUser(IYieldStakeAsset(asset), amount.asUint112(), 0, to);
  }

  function unstake(
    address asset,
    uint256 amount,
    address to
  ) external onlyUnpausedAsset(asset, false) {
    Value.require(to != address(0));

    if (amount == type(uint256).max) {
      amount = _userAssetBalances[IYieldStakeAsset(asset)][msg.sender].stakedTokenAmount;
    }
    if (amount == 0) {
      return;
    }

    _updateAssetAndUser(IYieldStakeAsset(asset), 0, amount.asUint112(), msg.sender);
    SafeERC20.safeTransfer(IERC20(asset), to, amount);
  }

  function syncStakeAsset(address asset) external override onlyUnpausedAsset(asset, true) {
    IYieldStakeAsset a = IYieldStakeAsset(asset);
    _updateAsset(a, a.totalSupply(), a.collateralSupply(), false);
  }

  function syncByStakeAsset(uint256 assetSupply, uint256 collateralSupply) external override {
    IYieldStakeAsset asset = IYieldStakeAsset(msg.sender);
    _ensureActiveAsset(_assetBalances[asset].flags, true);
    _updateAsset(asset, assetSupply, collateralSupply, true);
  }

  function _updateAsset(
    IYieldStakeAsset asset,
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
      uint256 totalStaked = _totalStakedCollateral;
      if (totalStaked != 0) {
        totalIntegral += internalCalcRateIntegral(lastUpdatedAt, at).rayDiv(totalStaked);
      }
    }
  }

  function internalSyncTotal() internal {
    _updateTotal(0);
  }

  function _updateTotal(uint256 extra) private returns (uint256 totalIntegral, uint256 totalStaked) {
    uint32 lastUpdatedAt;
    (totalIntegral, lastUpdatedAt) = internalGetTimeIntegral();

    uint32 at = uint32(block.timestamp);
    if (at != lastUpdatedAt) {
      extra += internalGetRateIntegral(lastUpdatedAt, at);
    } else if (extra == 0) {
      return (totalIntegral, totalStaked);
    }
    if ((totalStaked = _totalStakedCollateral) != 0) {
      totalIntegral += extra.rayDiv(totalStaked);
      internalSetTimeIntegral(totalIntegral, at);
    }
  }

  function _syncAnyAsset(AssetBalance memory assetBalance, uint256 totalIntegral) private pure {
    uint256 d = totalIntegral - assetBalance.totalIntegral;
    if (d != 0) {
      assetBalance.totalIntegral = totalIntegral.asUint128();
      assetBalance.assetIntegral += d.rayMul(assetBalance.collateralFactor).asUint128();
    }
  }

  event AssetUpdated(address indexed asset, uint256 stakedTotal, uint256 collateralFactor);

  function _updateAsset(
    IYieldStakeAsset asset,
    uint256 collateralFactor,
    uint128 incAmount,
    uint128 decAmount,
    bool ignorePause
  ) private returns (uint128) {
    AssetBalance memory assetBalance = _assetBalances[asset];
    _ensureActiveAsset(assetBalance.flags, ignorePause);

    (uint256 totalIntegral, uint256 totalStaked) = _updateTotal(0);

    uint256 prevCollateral = uint256(assetBalance.stakedTokenTotal).rayMul(assetBalance.collateralFactor);

    _syncAnyAsset(assetBalance, totalIntegral);
    assetBalance.collateralFactor = collateralFactor.asUint112();
    assetBalance.stakedTokenTotal = (assetBalance.stakedTokenTotal - decAmount) + incAmount;

    uint256 newCollateral = uint256(assetBalance.stakedTokenTotal).rayMul(collateralFactor);

    emit AssetUpdated(address(asset), assetBalance.stakedTokenTotal, collateralFactor);

    _assetBalances[asset] = assetBalance;

    if (newCollateral != prevCollateral) {
      if (totalStaked == 0) {
        totalStaked = _totalStakedCollateral;
      }
      internalOnStakedCollateralChanged(totalStaked, _totalStakedCollateral = (totalStaked + newCollateral - prevCollateral).asUint128());
    }

    return assetBalance.assetIntegral;
  }

  function internalOnStakedCollateralChanged(uint256 prevStaked, uint256 newStaked) internal virtual {}

  event StakeUpdated(address indexed asset, address indexed account, uint256 staked);

  function _updateAssetAndUser(
    IYieldStakeAsset asset,
    uint112 incAmount,
    uint112 decAmount,
    address account
  ) private {
    uint256 collateralFactor = asset.collateralSupply().rayDiv(asset.totalSupply());
    uint128 assetIntegral = _updateAsset(asset, collateralFactor, incAmount, decAmount, false);

    Value.require(account != address(0));

    UserAssetBalance storage balance = _userAssetBalances[asset][account];

    uint256 d = assetIntegral - balance.assetIntegral;
    uint112 stakedTokenAmount = balance.stakedTokenAmount;

    if (d != 0 && stakedTokenAmount != 0) {
      balance.assetIntegral = assetIntegral;
      _userBalances[account].yieldBalance += d.rayMul(stakedTokenAmount).asUint128();
    }

    mapping(uint256 => IYieldStakeAsset) storage listing = _userAssets[account];

    //    console.log('stakedTokenAmount', stakedTokenAmount, decAmount, incAmount);
    uint256 balanceAfter = (stakedTokenAmount - decAmount) + incAmount;
    if (balanceAfter == 0) {
      if (stakedTokenAmount != 0) {
        // remove asset
        uint16 index = _userBalances[account].assetCount--;
        uint16 assetIndex = balance.assetIndex;
        if (assetIndex != index) {
          State.require(assetIndex < index);
          IYieldStakeAsset a = listing[assetIndex] = listing[index];
          _userAssetBalances[a][account].assetIndex = assetIndex;
        } else {
          delete _userAssetBalances[asset][account];
          delete listing[assetIndex];
        }
      }
    } else if (stakedTokenAmount == 0) {
      // add asset
      uint16 index = ++_userBalances[account].assetCount;
      balance.assetIndex = index;
      _userAssets[account][index] = asset;
    }
    balance.stakedTokenAmount = balanceAfter.asUint112();

    emit StakeUpdated(address(asset), account, balanceAfter);
  }

  function _syncPresentAsset(IYieldStakeAsset asset, uint256 totalIntegral) private view returns (AssetBalance memory assetBalance) {
    assetBalance = _assetBalances[asset];
    State.require(assetBalance.flags & FLAG_ASSET_PRESENT != 0);
    _syncAnyAsset(assetBalance, totalIntegral);
  }

  function balanceOf(address account) external view returns (uint256 yieldBalance) {
    if (account == address(0)) {
      return 0;
    }

    UserBalance storage ub = _userBalances[account];
    mapping(uint256 => IYieldStakeAsset) storage listing = _userAssets[account];

    yieldBalance = ub.yieldBalance;
    uint256 totalIntegral = _syncTotal();

    for (uint256 i = ub.assetCount; i > 0; i--) {
      IYieldStakeAsset asset = listing[i];
      State.require(address(asset) != address(0));

      AssetBalance memory assetBalance = _syncPresentAsset(asset, totalIntegral);

      UserAssetBalance storage balance = _userAssetBalances[asset][account];

      uint256 d = assetBalance.assetIntegral - balance.assetIntegral;
      if (d != 0) {
        uint112 stakedTokenAmount = balance.stakedTokenAmount;
        if (stakedTokenAmount != 0) {
          yieldBalance += d.rayMul(stakedTokenAmount);
        }
      }
    }
  }

  function stakedBalanceOf(address asset, address account) external view returns (uint256) {
    return _userAssetBalances[IYieldStakeAsset(asset)][account].stakedTokenAmount;
  }

  function claimYield(address to) external returns (uint256) {
    address account = msg.sender;
    (uint256 yieldBalance, uint256 i) = _claimCollectedYield(account);

    (uint256 totalIntegral, ) = _updateTotal(0);
    mapping(uint256 => IYieldStakeAsset) storage listing = _userAssets[account];

    for (; i > 0; i--) {
      IYieldStakeAsset asset = listing[i];
      State.require(address(asset) != address(0));
      yieldBalance += _claimYield(asset, account, totalIntegral);
    }

    return _transferYield(account, yieldBalance, to);
  }

  function claimYieldFrom(address to, address[] calldata assets) external returns (uint256) {
    address account = msg.sender;
    (uint256 yieldBalance, ) = _claimCollectedYield(account);

    (uint256 totalIntegral, ) = _updateTotal(0);

    for (uint256 i = assets.length; i > 0; ) {
      i--;
      address asset = assets[i];
      Value.require(asset != address(0));
      yieldBalance += _claimYield(IYieldStakeAsset(asset), account, totalIntegral);
    }

    return _transferYield(account, yieldBalance, to);
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
    IYieldStakeAsset asset,
    address account,
    uint256 totalIntegral
  ) private returns (uint256 yieldBalance) {
    AssetBalance memory assetBalance = _syncPresentAsset(asset, totalIntegral);
    if (assetBalance.flags & FLAG_ASSET_PAUSED != 0) {
      return 0;
    }

    UserAssetBalance storage balance = _userAssetBalances[asset][account];

    uint256 d = assetBalance.assetIntegral - balance.assetIntegral;

    if (d != 0) {
      uint112 stakedTokenAmount = balance.stakedTokenAmount;
      if (stakedTokenAmount != 0) {
        _assetBalances[asset] = assetBalance;
        balance.assetIntegral = assetBalance.assetIntegral;

        yieldBalance = d.rayMul(stakedTokenAmount);
      }
    }
  }

  event YieldClaimed(address indexed account, uint256 amount);

  function _transferYield(
    address account,
    uint256 amount,
    address to
  ) private returns (uint256) {
    if (amount > 0) {
      IManagedCollateralCurrency cc = IManagedCollateralCurrency(collateral());
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
      cc.transferOnBehalf(account, to, amount);
    }

    emit YieldClaimed(account, amount);
    return amount;
  }

  function internalPullYield(uint256 availableYield, uint256 requestedYield) internal virtual returns (bool);

  function totalStakedCollateral() public view returns (uint256) {
    return _totalStakedCollateral;
  }

  function totalBorrowedCollateral() external view returns (uint256) {
    return _totalBorrowedCollateral;
  }

  event CollateralBorrowUpdate(uint256 totalStakedCollateral, uint256 totalBorrowedCollateral);

  function internalApplyBorrow(uint256 value) internal {
    uint256 totalBorrowed = _totalBorrowedCollateral + value;
    uint256 totalStaked = _totalStakedCollateral;

    State.require(totalBorrowed <= totalStaked);

    _totalBorrowedCollateral = totalBorrowed.asUint128();

    emit CollateralBorrowUpdate(totalStaked, totalBorrowed);
  }

  function internalApplyRepay(uint256 value) internal {
    emit CollateralBorrowUpdate(_totalStakedCollateral, _totalBorrowedCollateral = uint128(_totalBorrowedCollateral - value));
  }
}
