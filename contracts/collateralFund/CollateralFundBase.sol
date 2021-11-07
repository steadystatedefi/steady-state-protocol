// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '../dependencies/IERC1363Receiver.sol';
import '../interfaces/ICollateralFund.sol';
import '../interfaces/IInsurerPool.sol';
import '../pricing/interfaces/IPriceOracle.sol';
import '../tools/math/WadRayMath.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

//TODO: is IERC20
abstract contract CollateralFundBase {
  using SafeERC20 for IERC20;
  using WadRayMath for uint256;

  IPriceOracle private oracle;
  mapping(address => uint256) private ccBalance;
  uint256 private _totalSupply;
  uint256 private _investedSupply;

  /// @dev Map of an ERC20 to it's corresponding depositToken (0 address means not included)
  mapping(address => IDepositToken) internal depositTokens;
  address[] internal depositTokenList;

  /// @dev whitelist of *active* Insurer Pools
  mapping(address => bool) internal insurerWhitelist;
  address[] internal insurers;

  //This is a list of all assets that have been accumulated
  address[] private _assets;

  constructor() {}

  function deposit(
    address asset,
    uint256 amount,
    address to,
    uint256 referralCode
  ) external {
    require(address(depositTokens[asset]) != address(0), 'Not accepting this token');
    require(IERC20(asset).balanceOf(msg.sender) >= amount);
    require(IERC20(asset).allowance(msg.sender, address(this)) >= amount);

    ccBalance[to] += amount * _calculateAssetPrice(asset);
    _totalSupply += amount;
    depositTokens[asset].mint(to, amount);
  }

  function withdraw(
    address asset,
    uint256 amount,
    address to
  ) external {
    require(address(depositTokens[asset]) != address(0), 'Not accepting this token');
    require(depositTokens[asset].balanceOf(msg.sender) >= amount);
    (uint256 hf, int256 balance) = this.healthFactorOf(msg.sender);
    require(hf > 1);
    uint256 price = _calculateAssetPrice(asset);
    require(ccBalance[msg.sender] >= price * amount);

    //TODO: MAX_INT check
    require((balance - int256(price * amount) > 0));
    depositTokens[asset].burnFrom(msg.sender, amount);
    ccBalance[msg.sender] -= price * amount;
    _totalSupply -= amount;
    _investedSupply -= amount;

    IERC20(depositTokens[asset].getUnderlying()).transfer(to, amount);
  }

  function invest(address insurer, uint256 amount) external {
    this.transfer(insurer, amount);
    bytes4 retval = IInsurerPool(insurer).onTransferReceived(address(this), msg.sender, amount, bytes(''));
    require(retval == IERC1363Receiver(insurer).onTransferReceived.selector);
    _investedSupply += amount;
  }

  function transfer(address to, uint256 amount) external returns (uint256) {
    require(ccBalance[msg.sender] >= amount);
    if (!insurerWhitelist[msg.sender]) {
      require(insurerWhitelist[to]);
    }
    (uint256 hf, int256 balance) = this.healthFactorOf(msg.sender);
    require(hf > 1);
    //TODO: MAX_INT check
    require(balance - int256(amount) > 0);

    ccBalance[msg.sender] -= amount;
    ccBalance[to] += amount;

    return amount;
  }

  function declineCoverageFrom(address insurer) external {
    IInsurerPool(insurer).onCoverageDeclined(msg.sender);
  }

  function addDepositToken(address asset) external virtual returns (bool);

  function addInsurer(address insurer) external virtual returns (bool);

  /*** EXTERNAL VIEWS ***/

  function balanceOf(address account) external view returns (uint256) {
    return ccBalance[account];
  }

  function totalSupply() external view returns (uint256) {
    return _totalSupply;
  }

  function healthFactorOf(address account) external view returns (uint256 hf, int256 balance) {
    _healthFactor(_assetValue(account), _debtValue(account));
  }

  function investedCollateral() external view returns (uint256) {
    return _investedSupply;
  }

  //TODO: What is performance exactly? How do we calculate this if users are receiving different assets?
  function collateralPerformance() external view returns (uint256 rate, uint256 accumulated) {}

  function getReserveAssets() external view returns (address[] memory assets, address[] memory _depositTokens) {
    return (assets, depositTokenList);
  }

  /*** INTERNAL FUNCTIONS ***/

  function _calculateAssetPrice(address a) internal virtual returns (uint256) {
    return oracle.getAssetPrice(a);
  }

  function _healthFactor(uint256 depositValue, uint256 debtValue) internal pure returns (uint256 hf, int256 balance) {
    require(depositValue < uint256(type(int256).max));
    require(debtValue < uint256(type(int256).max));
    balance = int256(depositValue) - int256(debtValue);

    hf = depositValue.rayDiv(debtValue);
  }

  function _debtValue(address account) internal view returns (uint256 total) {
    for (uint256 i = 0; i < insurers.length; i++) {
      (uint256 rate, ) = IInsurerPool(insurers[i]).exchangeRate();
      total += IInsurerPool(insurers[i]).balanceOf(account).rayMul(rate); //TODO: Is this correct?
    }
  }

  /// @dev Get the value of all the assets this user has deposited
  function _assetValue(address account) internal view returns (uint256 total) {
    // If price oracle is cheap to call, then it may be more efficient to not allocate these arrays and just call oracle on
    // all collateral fund assets
    address[] memory allAssets = new address[](depositTokenList.length);
    uint32 numAssets = 0;
    for (uint256 i = 0; i < depositTokenList.length; i++) {
      if (IDepositToken(depositTokenList[i]).balanceOf(account) > 0) {
        allAssets[numAssets] = depositTokenList[i];
        numAssets++;
      }
    }
    address[] memory assets = new address[](numAssets);
    for (uint256 i = 0; i < numAssets; i++) {
      assets[i] = allAssets[i];
    }

    //TODO: Will/Should rever in getAssetPrice() be caught?
    uint256[] memory prices = oracle.getAssetPrices(assets);
    for (uint256 i = 0; i < numAssets; i++) {
      total += (IERC20(assets[i]).balanceOf(account) * prices[i]);
    }
  }
}
