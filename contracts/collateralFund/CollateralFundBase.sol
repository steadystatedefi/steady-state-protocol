// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '../interfaces/ICollateralFund.sol';
import '../interfaces/IInsurerPool.sol';
import '../pricing/interfaces/IPriceOracle.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/SafeERC20.sol';

import './CollateralFundBalances.sol';
import './CollateralFundInvesting.sol';
import './CoverageCurrency.sol';

///@dev CollateralFundBase contains logic on minting/burning/transferring $CC/dTokens
abstract contract CollateralFundBase is CollateralFundBalances, CollateralFundInvesting, CoverageCurrency {
  using SafeERC20 for IERC20;
  using WadRayMath for uint256;

  /*** EVENTS ***/
  event Deposit(address _asset, uint256 _amt);
  event Withdraw(address _asset, uint256 _amt);
  event Invest(address _insurer, uint256 _amt);

  /*** VARIABLES ***/
  IPriceOracle private oracle;
  uint256 private _investedSupply;

  /// @dev Actively accepted collateral deposits
  mapping(address => bool) internal depositWhitelist;

  /// @dev list of the ERC20s that have ever been accepted
  address[] internal depositList;

  /// @dev whitelist of *active* Insurer Pools
  mapping(address => bool) internal insurerWhitelist;
  address[] internal insurers;

  //This is a list of all assets that have been accumulated
  address[] private _assets;

  //TODO: Prevent double storage w/ dTokens?
  struct TokenBalance {
    uint128 ccIn;
    uint128 ccOut;
    uint128 x;
  }

  struct Account {
    mapping(address => TokenBalance) deposits;
    address[] assetsHeld;
    bool isAutomated; //Normal users are NOT
  }

  mapping(address => Account) internal accounts;

  /*** FUNCTIONS ***/
  constructor(string memory name) {}

  ///@dev Deposit into the collateral fund and invest into the given insurer
  function depositAndInvest(
    address asset,
    uint256 amount,
    uint256 referralCode,
    address insurer
  ) external {
    this.deposit(asset, amount, msg.sender, referralCode);
    _invest(insurer, amount, '');
  }

  ///@dev Deposit the asset into the collateral fund and mint the corresponding $CC
  function deposit(
    address asset,
    uint256 amount,
    address to,
    uint256 referralCode
  ) external {
    require(depositWhitelist[asset], 'Not accepting this token');

    if (allowance(to, address(this)) == 0) {
      _approve(to, address(this), type(uint256).max);
    }

    uint256 ccAmt = amount * _calculateAssetPrice(asset);
    mintFor(to, asset, amount, '');
    _mint(to, ccAmt);
    require(ccAmt < uint256(type(uint128).max));
    if (accounts[to].deposits[asset].x == 0) {
      //Perhaps x should have a min value of 1 so that duplicates don't populate array
      accounts[to].assetsHeld.push(asset);
    }

    accounts[to].deposits[asset].ccIn += uint128(ccAmt);
    accounts[to].deposits[asset].x += uint128(amount);
    IERC20(asset).transferFrom(msg.sender, address(this), amount);
    assetBalances[asset].balance += uint128(amount);

    emit Deposit(asset, amount);
  }

  ///@dev Withdraw the given asset from the collateral fund and burn the corresponding $CC
  function withdraw(
    address asset,
    uint256 amount,
    address to
  ) external {
    require(depositWhitelist[asset], 'Not accepting this token');
    require(amount < uint256(type(uint128).max));

    Account storage a = accounts[msg.sender];
    TokenBalance storage tb = a.deposits[asset];
    uint256 ccAmt = (uint256(tb.ccIn) * amount) / uint256(tb.x);

    require(ccAmt < uint256(type(uint128).max));
    require(tb.ccIn - tb.ccOut > ccAmt);
    require((tb.ccIn -= uint128(ccAmt)) >= tb.ccOut);

    tb.x -= uint128(amount);
    burnFor(msg.sender, asset, amount);
    _burn(msg.sender, ccAmt);
    IERC20(asset).transfer(to, amount);
    assetBalances[asset].balance -= uint128(amount);

    emit Withdraw(asset, amount);
  }

  ///@dev Send the $CC to the insurer
  function invest(address insurer, uint256 amount) external {
    _invest(insurer, amount, '');
  }

  function investWithParams(
    address insurer,
    uint256 amount,
    bytes calldata params
  ) external {
    _invest(insurer, amount, params);
  }

  ///@dev Sendings the amount of $CC and calls ERC1363 onTransferReceived
  function _invest(
    address insurer,
    uint256 amount,
    bytes memory params
  ) internal {
    require(amount < uint256(type(uint128).max));
    this.transferFrom(msg.sender, insurer, amount);
    require(addCCOut(msg.sender, uint128(amount)));

    _investedSupply += amount;
    emit Invest(insurer, amount);
  }

  ///@dev Increments the CC out of a user. Simply does so in order of assets deposited
  function addCCOut(address user, uint128 amount) internal returns (bool) {
    Account storage a = accounts[user];
    for (uint256 i = 0; i < a.assetsHeld.length; i++) {
      TokenBalance storage tb = a.deposits[a.assetsHeld[i]];
      uint128 diff = tb.ccIn - tb.ccOut;
      if (diff > amount) {
        tb.ccOut += amount;
        return true;
      } else if (diff > 0) {
        tb.ccOut += diff;
        amount -= diff;
      }
    }

    return false;
  }

  function declineCoverageFrom(address insurer) external {
    IInsurerPool(insurer).onCoverageDeclined(msg.sender);
    transferFrom(msg.sender, insurer, balanceOf(msg.sender));
  }

  function addDepositToken(address asset) external virtual returns (bool);

  function addInsurer(address insurer) external virtual returns (bool);

  /*** EXTERNAL VIEWS ***/

  function healthFactorOf(address account) external view returns (uint256 hf, int256 balance) {
    //TODO: Debt is RAY, asset is NOT
    return _healthFactor(_assetValue(account), _debtValue(account));
  }

  function investedCollateral() external view returns (uint256) {
    return _investedSupply;
  }

  function collateralPerformance() external view returns (uint256 rate, uint256 accumulated) {}

  function getReserveAssets() external view returns (address[] memory assets, address[] memory acceptedTokens) {
    return (assets, depositList);
  }

  function getDepositsAccepted() external view returns (address[] memory) {
    return depositList;
  }

  function getDepositTokenIds() external view returns (uint256[] memory ids) {
    for (uint256 i = 0; i < depositList.length; i++) {
      ids[i] = _getId(depositList[i]);
    }
  }

  function isInsurer(address insurer) external view returns (bool) {
    return insurerWhitelist[insurer];
  }

  /*** INTERNAL FUNCTIONS ***/

  ///@dev Logic for $CC
  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal override {
    //minting
    if (from == address(0)) {
      return;
    }
    //burning
    if (to == address(0)) {
      (uint256 hf, int256 balance) = this.healthFactorOf(from);
      require(hf > WadRayMath.ray());
      require(amount < uint256(type(int256).max));
      require(balance - int256(amount) > 0, 'Balance would be negative');
      return;
    }
    if (!insurerWhitelist[from]) {
      require(insurerWhitelist[to], 'Not on the insurer whitelist');
    }
  }

  function _afterTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal override {
    if (insurerWhitelist[to] || accounts[to].isAutomated) {
      bytes4 retval = IInsurerPool(to).onTransferReceived(address(this), msg.sender, amount, '');
      require(retval == IERC1363Receiver(to).onTransferReceived.selector);
    }
  }

  ///@dev Logic for dTokens
  function _beforeTokenTransfer(
    address operator,
    address from,
    address to,
    uint256[] memory ids,
    uint256[] memory amounts,
    bytes memory data
  ) internal override {
    //minting
    if (from == address(0)) {
      return;
    }

    (uint256 hf, int256 balance) = this.healthFactorOf(from);
    require(hf > WadRayMath.ray());

    for (uint256 i = 0; i < ids.length; i++) {
      address underlying = idToUnderlying[ids[i]];
      require(depositWhitelist[underlying]);

      //TODO: This needs to be re-worked for yield-bearing assets
      require(amounts[i] < uint256(type(int256).max));
      uint256 amount = amounts[i] * _calculateAssetPrice(underlying);
      require(amount < uint256(type(int256).max));
      balance -= int256(amount);
      require(balance > 0);
    }

    return;
  }

  function _calculateAssetPrice(address a) internal view virtual returns (uint256) {
    return oracle.getAssetPrice(a);
  }

  function _healthFactor(uint256 depositValue, uint256 debtValue) internal pure returns (uint256 hf, int256 balance) {
    require(depositValue < uint256(type(int256).max));
    require(debtValue < uint256(type(int256).max));
    balance = int256(depositValue) - int256(debtValue);

    if (debtValue == 0) {
      debtValue = 1;
    }
    hf = depositValue.rayDiv(debtValue);
  }

  function _debtValue(address account) internal view returns (uint256 total) {
    for (uint256 i = 0; i < insurers.length; i++) {
      uint256 rate = IInsurerPool(insurers[i]).exchangeRate();
      total += IInsurerPool(insurers[i]).balanceOf(account).rayMul(rate); //TODO: Is this correct?
    }
  }

  /// @dev Get the value of all the assets this user has deposited
  function _assetValue(address account) internal view returns (uint256 total) {
    for (uint256 i = 0; i < depositList.length; i++) {
      if (balanceOf(account, _getId(depositList[i])) > 0) {
        total += balanceOf(account, _getId(depositList[i])) * _calculateAssetPrice(depositList[i]);
      }
    }

    //If more efficient, later on use the oracle.getAssetPrices() function to make a single call
  }
}
