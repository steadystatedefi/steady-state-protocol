// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../access/AccessHelper.sol';
import '../interfaces/IManagedCollateralCurrency.sol';
import './interfaces/IManagedYieldDistributor.sol';
import './TokenDelegateBase.sol';

contract CollateralCurrency is IManagedCollateralCurrency, AccessHelper, TokenDelegateBase {
  address private _borrowManager;

  uint8 internal constant DECIMALS = 18;

  constructor(
    IAccessController acl,
    string memory name_,
    string memory symbol_
  ) AccessHelper(acl) ERC20Base(name_, symbol_, DECIMALS) {}

  event LiquidityProviderRegistered(address indexed account);

  function registerLiquidityProvider(address account) external aclHas(AccessFlags.LP_DEPLOY) {
    internalSetFlags(account, FLAG_MINT | FLAG_BURN);
    emit LiquidityProviderRegistered(account);
  }

  function isLiquidityProvider(address account) external view override returns (bool) {
    return internalGetFlags(account) & FLAG_MINT != 0;
  }

  event InsurerRegistered(address indexed account);

  function registerInsurer(address account) external aclHas(AccessFlags.INSURER_ADMIN) {
    // TODO protect insurer from withdraw
    internalSetFlags(account, FLAG_TRANSFER_CALLBACK);
    emit InsurerRegistered(account);
    _registerStakeAsset(account, true);
  }

  function _registerStakeAsset(address account, bool register) private {
    address bm = borrowManager();
    if (bm != address(0)) {
      IManagedYieldDistributor(bm).registerStakeAsset(account, register);
    }
  }

  event Unegistered(address indexed account);

  function unregister(address account) external {
    if (msg.sender != account) {
      Access.require(hasAnyAcl(msg.sender, internalGetFlags(account) == FLAG_TRANSFER_CALLBACK ? AccessFlags.INSURER_ADMIN : AccessFlags.LP_DEPLOY));
    }
    internalUnsetFlags(account);
    emit Unegistered(account);

    _registerStakeAsset(account, false);
  }

  function mint(address account, uint256 amount) external override onlyWithFlags(FLAG_MINT) {
    _mint(account, amount);
  }

  function transferOnBehalf(
    address onBehalf,
    address recipient,
    uint256 amount
  ) external override onlyBorrowManager {
    _transferOnBehalf(msg.sender, recipient, amount, onBehalf);
  }

  function mintAndTransfer(
    address onBehalf,
    address recipient,
    uint256 mintAmount,
    uint256 balanceAmount
  ) external override onlyWithFlags(FLAG_MINT) {
    if (balanceAmount == 0) {
      _mintAndTransfer(onBehalf, recipient, mintAmount);
    } else {
      _mint(onBehalf, mintAmount);
      if (balanceAmount == type(uint256).max) {
        balanceAmount = balanceOf(onBehalf);
      } else {
        balanceAmount += mintAmount;
      }
      _transfer(onBehalf, recipient, balanceAmount);
    }
  }

  function burn(address account, uint256 amount) external override onlyWithFlags(FLAG_BURN) {
    _burn(account, amount);
  }

  function _onlyBorrowManager() private view {
    Access.require(msg.sender == borrowManager());
  }

  modifier onlyBorrowManager() {
    _onlyBorrowManager();
    _;
  }

  function borrowManager() public view override returns (address) {
    return _borrowManager;
  }

  event BorrowManagerUpdated(address indexed addr);

  function setBorrowManager(address borrowManager_) external onlyAdmin {
    Value.require(borrowManager_ != address(0));
    // Slither is not very smart
    // slither-disable-next-line missing-zero-check
    _borrowManager = borrowManager_;

    emit BorrowManagerUpdated(borrowManager_);
  }
}
