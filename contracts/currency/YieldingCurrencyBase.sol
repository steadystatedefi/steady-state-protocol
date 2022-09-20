// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.10;

import '../tools/math/WadRayMath.sol';
import '../tools/tokens/ERC20MintableBalancelessBase.sol';
import '../tools/tokens/IERC1363.sol';
import '../access/AccessHelper.sol';
import './InvestmentCurrencyBase.sol';
import './YieldingBase.sol';

abstract contract YieldingCurrencyBase is AccessHelper, InvestmentCurrencyBase, YieldingBase {
  using Math for uint256;
  using WadRayMath for uint256;
  using InvestAccount for InvestAccount.Balance;

  address private _borrowManager;

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

  function totalAndManagedSupply() public view override(InvestmentCurrencyBase, YieldingBase) returns (uint256, uint256) {
    return super.totalAndManagedSupply();
  }

  function internalGetBalance(address account) internal view override(InvestmentCurrencyBase, YieldingBase) returns (InvestAccount.Balance) {
    return super.internalGetBalance(account);
  }

  function internalBeforeManagedBalanceUpdate(address account, InvestAccount.Balance accBalance)
    internal
    override(InvestmentCurrencyBase, YieldingBase)
  {
    return super.internalBeforeManagedBalanceUpdate(account, accBalance);
  }

  function incrementBalance(address account, uint256 amount) internal override {
    super.incrementBalance(account, amount);

    if (account == address(this) && amount != 0) {
      // this is yield mint
      internalAddYield(amount);
    }
  }

  function pullYield() external returns (uint256) {
    return internalPullYield(msg.sender);
  }

  event AccountMarked(address indexed account);
  event AccountUnmarked(address indexed account, uint256 amount);

  function markRestricted(address account) external {
    internalSubBalance(account, true, 0);
    emit AccountMarked(account);
  }

  function unmarkRestricted(address account, uint256 releaseAmount) external {
    internalSubBalance(account, false, releaseAmount);
    emit AccountUnmarked(account, releaseAmount);
  }

  // TODO function stateOf(address account)
}
