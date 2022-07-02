// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/Errors.sol';
import '../interfaces/IProxyFactory.sol';
import '../access/AccessHelper.sol';

abstract contract GovernedHelper is AccessHelper {
  function governor() public view virtual returns (address);

  function _onlyGovernorOr(uint256 flags) private view {
    require(_isAllowed(flags) || hasAnyAcl(msg.sender, flags));
  }

  function _onlyGovernor() private view {
    require(_isAllowed(0));
  }

  function _isAllowed(uint256 flags) private view returns (bool) {
    address g = governor();
    return g == msg.sender || isAllowedByGovernor(msg.sender, flags);
  }

  function isAllowedByGovernor(address account, uint256 flags) internal view virtual returns (bool) {}

  modifier onlyGovernorOr(uint256 flags) {
    _onlyGovernorOr(flags);
    _;
  }

  modifier onlyGovernor() {
    _onlyGovernor();
    _;
  }
}
