// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '../interfaces/ICollateralFund.sol';
import '../interfaces/IInsurerPool.sol';
import '../pricing/interfaces/IPriceOracle.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/SafeERC20.sol';
import '../tools/tokens/ERC20Base.sol';

//import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

abstract contract CollateralFundBase is ERC20Base {
  using SafeERC20 for IERC20;
  using WadRayMath for uint256;

  /*** EVENTS ***/
  event Deposit(address _asset, uint256 _amt);
  event Withdraw(address _asset, uint256 _amt);
  event Invest(address _insurer, uint256 _amt);

  /*** VARIABLES ***/
  IPriceOracle private oracle;
  uint256 private _investedSupply;

  /// @dev Map of an ERC20 to it's corresponding depositToken (0 address means not included)
  mapping(address => IDepositToken) internal depositTokens;

  /// @dev list of the ERC20s that are accepted
  address[] internal depositTokenList;

  /// @dev whitelist of *active* Insurer Pools
  mapping(address => bool) internal insurerWhitelist;
  address[] internal insurers;

  //This is a list of all assets that have been accumulated
  address[] private _assets;

  /*** FUNCTIONS ***/
  constructor(string memory name, string memory symbol) ERC20Base(name, symbol, 18) {}

  function deposit(
    address asset,
    uint256 amount,
    address to,
    uint256 referralCode
  ) external {
    require(address(depositTokens[asset]) != address(0), 'Not accepting this token');
    require(IERC20(asset).balanceOf(msg.sender) >= amount, 'Balance low');
    require(IERC20(asset).allowance(msg.sender, address(this)) >= amount, 'No allowance');

    _mint(to, amount * _calculateAssetPrice(asset));
    depositTokens[asset].mint(to, amount);
    IERC20(asset).transferFrom(msg.sender, address(this), amount);

    emit Deposit(asset, amount);
  }

  function withdraw(
    address asset,
    uint256 amount,
    address to
  ) external {
    require(address(depositTokens[asset]) != address(0), 'Not accepting this token');
    require(depositTokens[asset].balanceOf(msg.sender) >= amount);
    //Is it satisfactory to rely on the _beforeTokenTransfer of depositToken?
    //require(ccBalance[msg.sender] >= price * amount);
    require(balanceOf(msg.sender) >= amount * _calculateAssetPrice(asset));

    depositTokens[asset].burnFrom(msg.sender, amount);
    _burn(msg.sender, amount * _calculateAssetPrice(asset));
    IERC20(asset).transfer(to, amount);

    emit Withdraw(asset, amount);
  }

  function invest(address insurer, uint256 amount) external {
    this.transfer(insurer, amount);
    bytes4 retval = IInsurerPool(insurer).onTransferReceived(address(this), msg.sender, amount, bytes(''));
    require(retval == IERC1363Receiver(insurer).onTransferReceived.selector);
    _investedSupply += amount;

    emit Invest(insurer, amount);
  }

  function declineCoverageFrom(address insurer) external {
    IInsurerPool(insurer).onCoverageDeclined(msg.sender);
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

  //TODO: What is performance exactly? How do we calculate this if users are receiving different assets?
  function collateralPerformance() external view returns (uint256 rate, uint256 accumulated) {}

  function getReserveAssets() external view returns (address[] memory assets, address[] memory _depositTokens) {
    return (assets, depositTokenList);
  }

  function getDepositTokens() external view returns (address[] memory) {
    return depositTokenList;
  }

  function getDepositTokenOf(address a) external view returns (address) {
    return address(depositTokens[a]);
  }

  /*** INTERNAL FUNCTIONS ***/

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal view override {
    if (from == address(0) || to == address(0)) {
      //minting or burning
      return;
    } else {
      if (!insurerWhitelist[from]) {
        require(insurerWhitelist[to]);
      }
    }
    (uint256 hf, int256 balance) = this.healthFactorOf(from);
    require(hf > WadRayMath.ray());
    require(amount < uint256(type(int256).max));
    require(balance - int256(amount) > 0, 'Would cause negative balance');
  }

  function _calculateAssetPrice(address a) internal virtual returns (uint256) {
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
    // If price oracle is cheap to call, then it may be more efficient to not allocate these arrays and just call oracle on
    // all collateral fund assets
    address[] memory allAssets = new address[](depositTokenList.length);
    uint32 numAssets = 0;
    for (uint256 i = 0; i < depositTokenList.length; i++) {
      if (depositTokens[depositTokenList[i]].balanceOf(account) > 0) {
        allAssets[numAssets] = depositTokenList[i];
        numAssets++;
      }
    }
    address[] memory assets = new address[](numAssets);
    for (uint256 i = 0; i < numAssets; i++) {
      assets[i] = allAssets[i];
    }

    //TODO: Will/Should rever in getAssetPrice() be caught?
    //TODO: !!!TEMPORARY QUICK FIX FOR STABLECOIN TESTING!!!
    /*
    uint256[] memory prices = oracle.getAssetPrices(assets);
    for (uint256 i = 0; i < numAssets; i++) {
      total += (IERC20(assets[i]).balanceOf(account) * prices[i]);
    }
    */
    for (uint256 i = 0; i < numAssets; i++) {
      total += (depositTokens[assets[i]].balanceOf(account) * 1);
    }
  }
}