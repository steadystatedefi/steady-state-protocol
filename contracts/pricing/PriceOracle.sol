// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './interfaces/IManagerPriceOracle.sol';

contract PriceOracle is IManagerPriceOracle {
  // solhint-disable-next-line var-name-mixedcase
  address public immutable override WETH;
  address private _fallback;

  struct Source {
    address source;
    uint224 staticPrice;
    PriceSourceType sourceType;
    uint16 flags;
  }

  mapping(address => Source) private _sources;

  constructor(
    address weth,
    address fallback_,
    address[] memory assets,
    PriceSource[] memory sources
  ) {
    require(weth != address(0), 'UNKNOWN_WETH');
    _fallback = fallback_;
    WETH = weth;
    _sources[weth].staticPrice = 1 ether;

    for (uint256 i = assets.length; i > 0; ) {
      i--;
      _setPriceSource(assets[i], weth, Source(sources[i].source, sources[i].staticPrice, sources[i].sourceType, 0));
    }
  }

  modifier onlyOracleAdmin() {
    _;
  }

  function getAssetPrice(address asset) public view override returns (uint256 v) {
    if ((v = _getAssetPrice(asset)) != 0) {
      return v;
    }
    IFallbackPriceOracle fb;
    if (address(fb = IFallbackPriceOracle(_fallback)) != address(0) && (v = fb.getAssetPrice(asset)) != 0) {
      return v;
    }
    revert('UNKNOWN_PRICE');
  }

  function _getAssetPrice(address asset) private view returns (uint256) {
    Source memory src = _sources[asset];
    if (src.source != address(0)) {
      if (src.sourceType == PriceSourceType.Chainlink) {
        return _getAssetPriceChainlink(src.source);
      } else if (src.sourceType == PriceSourceType.UniV2EthPair) {
        return _getAssetPriceUniV2EthPair(src.source, src.flags);
      }
    }
    return src.staticPrice;
  }

  function _getAssetPriceChainlink(address source) private view returns (uint256) {
    source;
    this;
    return 0;
  }

  function _getAssetPriceUniV2EthPair(address source, uint16 flags) private view returns (uint256) {
    source;
    flags;
    this;
    return 0;
  }

  function getAssetPrices(address[] calldata assets) external view override returns (uint256[] memory result) {
    result = new uint256[](assets.length);
    for (uint256 i = assets.length; i > 0; ) {
      i--;
      result[i] = getAssetPrice(assets[i]);
    }
    return result;
  }

  function getPriceSource(address asset) public view override returns (PriceSource memory) {
    Source storage src = _sources[asset];
    return PriceSource(src.source, src.staticPrice, src.sourceType);
  }

  function getPriceSources(address[] calldata assets) external view override returns (PriceSource[] memory result) {
    result = new PriceSource[](assets.length);
    for (uint256 i = assets.length; i > 0; ) {
      i--;
      result[i] = getPriceSource(assets[i]);
    }
    return result;
  }

  function setPriceSources(address[] calldata assets, PriceSource[] calldata sources) external override onlyOracleAdmin {
    address weth = WETH;
    for (uint256 i = assets.length; i > 0; ) {
      i--;
      _setPriceSource(assets[i], weth, Source(sources[i].source, sources[i].staticPrice, sources[i].sourceType, 0));
    }
  }

  function _setPriceSource(
    address asset,
    address weth,
    Source memory src
  ) private {
    require(asset != weth);
    if (src.sourceType != PriceSourceType.Chainlink) {
      require(src.source != address(0));
      // TODO src.flags =
    }
    _sources[asset] = src;
  }

  function setStaticPrices(address[] calldata assets, uint256[] calldata prices) external override onlyOracleAdmin {
    for (uint256 i = assets.length; i > 0; ) {
      i--;
      require(assets[i] != WETH);
      require(prices[i] <= type(uint224).max);
      _sources[assets[i]].staticPrice = uint224(prices[i]);
    }
  }

  function getFallback() external view override returns (address) {
    return _fallback;
  }

  function setFallback(address fallback_) public override onlyOracleAdmin {
    _fallback = fallback_;
  }
}
