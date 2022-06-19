// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

library Errors {
  string public constant MARKET_PROVIDER_NOT_REGISTERED = '0101'; // Amount must be greater than 0
  string public constant INVALID_MARKET_PROVIDER_ID = '0102';

  string public constant CALLER_NOT_FUND_ADMIN = '0201';
  string public constant CALLER_NOT_REWARD_CONFIG_ADMIN = '0202';
  string public constant CALLER_NOT_EMERGENCY_ADMIN = '0203';
  string public constant CALLER_NOT_SWEEP_ADMIN = '0204';

  string public constant TXT_OWNABLE_CALLER_NOT_OWNER = 'Ownable: caller is not the owner';
  string public constant TXT_CALLER_NOT_PROXY_OWNER = 'ProxyOwner: caller is not the owner';
  string public constant TXT_ACCESS_RESTRICTED = 'RESTRICTED';

  function illegalState(bool ok) internal pure {
    if (!ok) {
      revert IllegalState();
    }
  }

  function illegalValue(bool ok) internal pure {
    if (!ok) {
      revert IllegalValue();
    }
  }

  function _mutable() private returns (bool) {}

  function notImplemented() internal {
    if (!_mutable()) {
      revert NotImplemented();
    }
  }

  error OperationPaused();
  error IllegalState();
  error IllegalValue();
  error NotSupported();
  error NotImplemented();
}

library State {
  function require(bool ok) internal pure {
    if (!ok) {
      revert Errors.IllegalState();
    }
  }
}

library Value {
  function require(bool ok) internal pure {
    if (!ok) {
      revert Errors.IllegalValue();
    }
  }
}
