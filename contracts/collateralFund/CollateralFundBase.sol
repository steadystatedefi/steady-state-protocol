// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '../interfaces/ICollateralFund.sol';
import '../interfaces/IInsurerPool.sol';
import '../pricing/interfaces/IPriceOracle.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/SafeERC20.sol';
//import '../tools/tokens/ERC20Base.sol';

import './CollateralFundBalances.sol';

abstract contract CollateralFundBase is CollateralFundBalances {
  using SafeERC20 for IERC20;
  using WadRayMath for uint256;

  address private constant CC_ADDRESS = address(0x000000000000000000000000000000000000000C);

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

  /*** FUNCTIONS ***/
  constructor(string memory name) {}

  function deposit(
    address asset,
    uint256 amount,
    address to,
    uint256 referralCode
  ) external {
    require(depositWhitelist[asset], 'Not accepting this token');

    uint256[] memory amounts = new uint256[](2);
    amounts[0] = amount * _calculateAssetPrice(asset);
    amounts[1] = amount;

    address[] memory underlyings = new address[](2);
    underlyings[0] = CC_ADDRESS;
    underlyings[1] = asset;

    mintForBatch(underlyings, amounts, to, '');
    IERC20(asset).transferFrom(msg.sender, address(this), amount);

    emit Deposit(asset, amount);
  }

  function withdraw(
    address asset,
    uint256 amount,
    address to
  ) external {
    require(depositWhitelist[asset], 'Not accepting this token');

    uint256[] memory amounts = new uint256[](2);
    amounts[0] = amount * _calculateAssetPrice(asset);
    amounts[1] = amount;

    address[] memory underlyings = new address[](2);
    underlyings[0] = CC_ADDRESS;
    underlyings[1] = asset;

    //The security of this function relies on _beforeTokenTransfer
    burnForBatch(to, underlyings, amounts);
    IERC20(asset).transfer(to, amount);

    emit Withdraw(asset, amount);
  }

  function invest(address insurer, uint256 amount) external {
    //this.transfer(insurer, amount);
    //bytes4 retval = IInsurerPool(insurer).onTransferReceived(address(this), msg.sender, amount, bytes(''));
    //require(retval == IERC1363Receiver(insurer).onTransferReceived.selector);
    //_investedSupply += amount;
    safeTransferFrom(msg.sender, insurer, _getId(CC_ADDRESS), amount, '');

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

  /*** INTERNAL FUNCTIONS ***/

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

    //Check health factor for transfers and burning
    for (uint256 i = 0; i < ids.length; i++) {
      if (ids[i] == _getId(CC_ADDRESS)) {
        if (!insurerWhitelist[from]) {
          //Buring $CC
          if (to == address(0)) {
            (uint256 hf, int256 balance) = this.healthFactorOf(from);
            require(hf > WadRayMath.ray());
            require(amounts[i] < uint256(type(int256).max));
            require(balance - int256(amounts[i]) > 0);
            continue;
          }
          require(insurerWhitelist[to]);
        }
      } else {
        (uint256 hf, int256 balance) = this.healthFactorOf(from);
        require(hf > WadRayMath.ray());
        address underlying = idToUnderlying[ids[i]];
        require(depositWhitelist[underlying]);

        //TODO: This needs to be re-worked for yield-bearing assets
        require(amounts[i] < uint256(type(int256).max));
        uint256 amount = amounts[i] * _calculateAssetPrice(underlying);
        require(amount < uint256(type(int256).max));
        require(balance - int256(amount) > 0);
      }
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
