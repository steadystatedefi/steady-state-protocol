// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.10;

import '../access/AccessHelper.sol';
import '../interfaces/IManagedCollateralCurrency.sol';
import '../currency/YieldingCurrencyBase.sol';

/// @dev ERC20 with functions including: managed and escrow balances, distribution of yield, and some access control (mint/burn/manager roles).
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

  /// @return a contract that controls borrowing of underlying funds from collateral funds attached to this currency.
  function borrowManager() public view returns (address) {
    return _borrowManager;
  }

  event BorrowManagerUpdated(address indexed addr);

  /// @dev Assignes a borrow manager
  function setBorrowManager(address borrowManager_) external onlyAdmin {
    // TODO a separate role?
    Value.require(borrowManager_ != address(0));
    // Slither is not very smart
    // slither-disable-next-line missing-zero-check
    _borrowManager = borrowManager_;

    emit BorrowManagerUpdated(borrowManager_);
  }

  event LiquidityProviderRegistered(address indexed account);

  /// @dev Registers the `account` as a liquidity provider (allows mint/burn). Only LP_DEPLOY can call.
  /// @param account must be an authentic proxy (see ProxyCatalog). Usually it is a collateral fund.
  function registerLiquidityProvider(address account) external aclHas(AccessFlags.LP_DEPLOY) {
    ensureAuthenticProxy(account);
    internalUpdateFlags(account, 0, FLAG_MINT | FLAG_BURN);
    emit LiquidityProviderRegistered(account);
  }

  /// @inheritdoc IManagedCollateralCurrency
  function isLiquidityProvider(address account) public view override returns (bool) {
    return internalGetFlags(account) & FLAG_MINT != 0;
  }

  event InsurerRegistered(address indexed account);

  /// @dev Registers an insurer. It is allowed to create escrows and to receive ERC1363 callbacks on transfers. Only INSURER_ADMIN can call.
  /// @param account must be an authentic proxy (see ProxyCatalog).
  function registerInsurer(address account) external aclHas(AccessFlags.INSURER_ADMIN) {
    ensureAuthenticProxy(account);
    internalUpdateFlags(account, 0, FLAG_TRANSFER_CALLBACK | FLAG_MANAGER);
    emit InsurerRegistered(account);
  }

  /// @inheritdoc IManagedCollateralCurrency
  function isRegistered(address account) external view override returns (bool) {
    return (internalGetFlags(account) & FLAGS_MASK) != 0;
  }

  event Unegistered(address indexed account);

  /// @dev Removes any special roles from the `account`.
  /// @dev Can be called by the `account`, or when registerInsurer() was applied, INSURER_ADMIN role is required, otherwise LP_DEPLOY.
  function unregister(address account) external {
    if (msg.sender != account) {
      uint256 flags = internalGetFlags(account);
      if (flags == 0) {
        Access.require(hasAnyAcl(msg.sender, AccessFlags.INSURER_ADMIN | AccessFlags.LP_DEPLOY));
        return;
      }
      flags = (flags & FLAG_MANAGER != 0 ? AccessFlags.INSURER_ADMIN : 0) | (flags & FLAG_MINT != 0 ? AccessFlags.LP_DEPLOY : 0);
      Value.require(flags != 0);
      Access.require(hasAllAcl(msg.sender, flags));
    }
    internalUnsetFlags(account);
    emit Unegistered(account);
  }

  /// @inheritdoc IManagedCollateralCurrency
  function mint(address account, uint256 amount) external override onlyWithFlags(FLAG_MINT) {
    _mint(account, amount);
  }

  /// @inheritdoc IManagedCollateralCurrency
  function transferOnBehalf(
    address onBehalf,
    address recipient,
    uint256 amount
  ) external override onlyBorrowManager {
    _transferOnBehalf(msg.sender, recipient, amount, onBehalf);
  }

  /// @inheritdoc IManagedCollateralCurrency
  function mintAndTransfer(
    address onBehalf,
    address recipient,
    uint256 mintAmount,
    uint256 balanceAmount
  ) external override onlyWithFlags(FLAG_MINT) {
    _onlyInvestManager(recipient);

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

  /// @inheritdoc IManagedCollateralCurrency
  function burn(address account, uint256 amount) external override onlyWithFlags(FLAG_BURN) {
    _burn(account, amount);
  }

  function _onlyInvestManager(address sender) private view {
    Access.require(internalGetFlags(sender) & FLAG_MANAGER != 0);
  }

  modifier onlyInvestManager() {
    _onlyInvestManager(msg.sender);
    _;
  }

  event SuBalanceOpened(address indexed account, address indexed manager);
  event SuBalanceClosed(address indexed account, address indexed manager, uint256 amount);

  /// @inheritdoc ISubBalance
  function openSubBalance(address account) external override onlyInvestManager {
    internalSubBalance(msg.sender, account, true, 0);
    emit SuBalanceOpened(account, msg.sender);
  }

  /// @inheritdoc ISubBalance
  function closeSubBalance(address account, uint256 transferAmount) external override onlyInvestManager {
    uint256 releaseAmount = internalSubBalance(msg.sender, account, false, transferAmount);
    emit SuBalanceClosed(account, msg.sender, releaseAmount);
  }

  /// @inheritdoc IManagedCollateralCurrency
  function pullYield() external override returns (uint256) {
    return internalPullYield(msg.sender);
  }

  // TODO function stateOf(address account)
}
