// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';
import '../tools/SafeERC20.sol';
import '../tools/Errors.sol';
import '../tools/tokens/ERC20BalancelessBase.sol';
import '../libraries/Balances.sol';
import '../tools/tokens/IERC20.sol';
import '../interfaces/IPremiumCalculator.sol';
import '../interfaces/IInsurancePool.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IInsuredPool.sol';
import '../interfaces/IProtocol.sol';
import '../tools/math/WadRayMath.sol';
import '../tools/tokens/ERC1363ReceiverBase.sol';
import '../insurance/InsurancePoolBase.sol';

struct TokenAmount {
  address token;
  uint256 amount;
}

contract PremiumCollector {
  using WadRayMath for uint256;
  using SafeERC20 for IERC20;

  mapping(address => mapping(address => address[])) private _pools; // [protocol][token]
  mapping(address => address[]) private _protocolTokens; // [protocol]
  mapping(address => address) private _poolTokens; // [insuredPool]

  enum TokenCalcMode {
    RayMul,
    External
  }

  struct TokenProfile {
    TokenCalcMode mode;
    uint160 payload;
  }
  mapping(address => mapping(address => TokenProfile)) private _tokenCalcs; // [collateral][token]

  struct TokenBalance {
    uint112 balance;
    uint112 deductable;
    uint32 timestamp;
  }
  mapping(address => mapping(address => TokenBalance)) private _balances; // [protocol][token]

  modifier onlyAdmin() virtual {
    // TODO
    _;
  }

  function registerProtocolTokens(
    address protocol,
    address[] calldata insuredPools,
    address[] calldata tokens
  ) external onlyAdmin {
    require(protocol != address(0));
    require(tokens.length == insuredPools.length);

    for (uint256 i = tokens.length; i > 0; ) {
      i--;
      address token = _poolTokens[insuredPools[i]];
      if (token != address(0)) {
        require(token == tokens[i]);
        continue;
      }
      require((token = tokens[i]) != address(0));

      address collateral = IPremiumCalculator(insuredPools[i]).collateral();
      require(collateral != address(0));
      require(_tokenCalcs[collateral][token].payload != 0); // unknown calculator

      address[] storage pools = _pools[protocol][token];
      if (pools.length == 0) {
        _protocolTokens[protocol].push(token);
      }
      pools.push(insuredPools[i]);
      _poolTokens[insuredPools[i]] = token;

      TokenBalance storage b = _balances[protocol][token];
      if (b.timestamp == 0) {
        b.timestamp = uint32(block.timestamp);
      }
    }
  }

  function setPremiumCalculator(
    address token,
    address[] calldata collaterals,
    address[] calldata calcs
  ) external onlyAdmin {
    require(token != address(0));
    require(collaterals.length == calcs.length);

    for (uint256 i = collaterals.length; i > 0; ) {
      i--;
      require(collaterals[i] != address(0));
      require(calcs[i] != address(0));
      _tokenCalcs[collaterals[i]][token] = TokenProfile(TokenCalcMode.External, uint160(calcs[i]));
    }
  }

  function setPremiumScale(
    address token,
    address[] calldata collaterals,
    uint256[] calldata scales
  ) external onlyAdmin {
    require(token != address(0));
    require(collaterals.length == scales.length);

    for (uint256 i = collaterals.length; i > 0; ) {
      i--;
      require(collaterals[i] != address(0));
      require(scales[i] > 0 && scales[i] <= type(uint160).max);
      _tokenCalcs[collaterals[i]][token] = TokenProfile(TokenCalcMode.RayMul, uint160(scales[i]));
    }
  }

  function _onlyProtocolOrRole(address protocol, ProtocolAccessFlags role) private view {
    require(msg.sender == protocol || IProtocol(protocol).hasRole(msg.sender, uint256(1) << uint8(role)));
  }

  modifier onlyProtocolOrRole(address protocol, ProtocolAccessFlags role) {
    _onlyProtocolOrRole(protocol, role);
    _;
  }

  /// @dev adds tokens to protocol's deposits. Protocol can only supply an agreed set of tokens, e.g. protocol's token & USDx
  /// @dev only users allowed by IProtocol.hasRole(DEPOSIT) can do this
  function deposit(address protocol, TokenAmount[] calldata amounts)
    external
    onlyProtocolOrRole(protocol, ProtocolAccessFlags.Deposit)
  {
    for (uint256 i = amounts.length; i > 0; ) {
      i--;
      address token = amounts[i].token;
      TokenBalance storage b = _balances[protocol][token];
      require(b.timestamp != 0); // Protocol-token combinations was not registred

      uint256 amount = amounts[i].amount;
      if (amount == 0) continue;
      IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

      require((b.balance = uint112(amount += b.balance)) == amount);
      b.timestamp = uint32(block.timestamp);
    }
  }

  /// @dev returns amounts that were not yet consumed/locked by the stream of premium
  function balanceOf(address protocol) external view returns (TokenAmount[] memory list) {
    return _balanceOf(protocol, 0);
  }

  function _balanceOf(address protocol, uint32 at) private view returns (TokenAmount[] memory list) {
    address[] storage tokens = _protocolTokens[protocol];
    uint256 i = tokens.length;

    list = new TokenAmount[](i);
    for (; i > 0; ) {
      i--;
      address token = tokens[i];
      TokenBalance memory b = _balances[protocol][token];
      uint256 expectedBalance = _balanceOf(token, b.deductable, at, _pools[protocol][token]);
      list[i] = TokenAmount(
        token,
        at > 0 ? expectedBalance : (expectedBalance >= b.balance ? 0 : b.balance - expectedBalance)
      );
    }
  }

  function _balanceOf(
    address token,
    uint256 deductable,
    uint32 at,
    address[] storage insuredPools
  ) private view returns (uint256 amount) {
    address collateral;
    uint256 collected;
    uint256 i = insuredPools.length;
    for (; i > 0; ) {
      i--;
      IPremiumCalculator calc = IPremiumCalculator(insuredPools[i]);
      (uint256 rate, uint256 demand) = calc.totalPremium();
      if (at > 0) {
        demand = rate * (at - block.timestamp);
      } else if (deductable >= demand) {
        deductable -= demand;
        continue;
      } else {
        (demand, deductable) = (demand - deductable, 0);
      }

      address c = calc.collateral();
      if (c != collateral || i == 0) {
        if (collected > 0) {
          amount += _convertPremiumToToken(collateral, collected, token);
        }
        (collateral, collected) = (c, demand);
      } else {
        collected += demand;
      }
    }
  }

  function _convertPremiumToToken(
    address collateral,
    uint256 amount,
    address token
  ) private view returns (uint256) {
    TokenProfile memory p = _tokenCalcs[collateral][token];
    if (p.mode == TokenCalcMode.External) {
      return ITokenPremiumCalculator(address(p.payload)).convertPremium(collateral, amount, token);
    } else {
      require(p.payload != 0);
      require(p.mode == TokenCalcMode.RayMul);
      return amount.rayMul(p.payload);
    }
  }

  // /// @dev returns amounts expected to be consumed/locked by the stream of premium at atTimestamp in the future and starting from now
  function expectedPay(address protocol, uint256 atTimestamp) external view returns (TokenAmount[] memory) {
    require(atTimestamp >= block.timestamp);
    require(atTimestamp == uint32(atTimestamp));
    return _balanceOf(protocol, uint32(atTimestamp));
  }

  function expectedPayAfter(address protocol, uint32 timeDelta) external view returns (TokenAmount[] memory) {
    return _balanceOf(protocol, uint32(block.timestamp) + timeDelta);
  }

  /// @dev withdraws tokens from protocol's deposits.
  /// @dev only users allowed by IProtocol.hasRole(WITHDRAW) can do this
  function withdraw(
    address protocol,
    TokenAmount[] calldata amounts,
    bool forceReconsile
  ) external onlyProtocolOrRole(protocol, ProtocolAccessFlags.Withdraw) {
    amounts;
    forceReconsile;
    Errors.notImplemented();
  }
}
