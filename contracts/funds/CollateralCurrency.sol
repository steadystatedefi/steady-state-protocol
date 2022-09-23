// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.10;

import '../access/AccessHelper.sol';
import '../interfaces/IManagedCollateralCurrency.sol';
import '../currency/YieldingCurrencyBase.sol';

contract CollateralCurrency is YieldingCurrencyBase, IManagedCollateralCurrency {
  address private _borrowManager;

  uint8 internal constant DECIMALS = 18;

  constructor(
    IAccessController acl,
    string memory name_,
    string memory symbol_
  ) AccessHelper(acl) ERC20DetailsBase(name_, symbol_, DECIMALS) {}

  function _onlyBorrowManager() private view {
    Access.require(msg.sender == borrowManager());
  }

  modifier onlyBorrowManager() {
    _onlyBorrowManager();
    _;
  }

  function borrowManager() public view returns (address) {
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

  event LiquidityProviderRegistered(address indexed account);

  function registerLiquidityProvider(address account) external aclHas(AccessFlags.LP_DEPLOY) {
    internalUpdateFlags(account, 0, FLAG_MINT | FLAG_BURN);
    emit LiquidityProviderRegistered(account);
  }

  function isLiquidityProvider(address account) public view override returns (bool) {
    return internalGetFlags(account) & FLAG_MINT != 0;
  }

  event InsurerRegistered(address indexed account);

  function registerInsurer(address account) external aclHas(AccessFlags.INSURER_ADMIN) {
    internalUpdateFlags(account, 0, FLAG_TRANSFER_CALLBACK | FLAG_MANAGER);
    emit InsurerRegistered(account);
  }

  function isRegistered(address account) external view override returns (bool) {
    return internalGetFlags(account) != 0;
  }

  event Unegistered(address indexed account);

  function unregister(address account) external {
    if (msg.sender != account) {
      Access.require(hasAnyAcl(msg.sender, internalGetFlags(account) & FLAG_MANAGER != 0 ? AccessFlags.INSURER_ADMIN : AccessFlags.LP_DEPLOY));
    }
    internalUnsetFlags(account);
    emit Unegistered(account);
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

  function _onlyInvestManager() private view {
    Access.require(internalGetFlags(msg.sender) & FLAG_MANAGER != 0);
  }

  modifier onlyInvestManager() {
    _onlyInvestManager();
    _;
  }

  event SuBalanceOpened(address indexed account, address indexed manager);
  event SuBalanceClosed(address indexed account, address indexed manager, uint256 amount);

  function openSubBalance(address account) external onlyInvestManager {
    internalSubBalance(msg.sender, account, true, 0);
    emit SuBalanceOpened(account, msg.sender);
  }

  function closeSubBalance(address account, uint256 transferAmount) external onlyInvestManager {
    uint256 releaseAmount = internalSubBalance(msg.sender, account, false, transferAmount);
    emit SuBalanceClosed(account, msg.sender, releaseAmount);
  }

  // TODO function stateOf(address account)
}
