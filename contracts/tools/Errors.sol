// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

library Errors {
  string public constant TXT_CALLER_NOT_PROXY_OWNER = 'ProxyOwner: caller is not the owner';

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

  function accessDenied(bool ok) internal pure {
    if (!ok) {
      revert AccessDenied();
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
  error AccessDenied();

  error ExcessiveVolatility();

  error CalllerNotEmergencyAdmin();
  error CalllerNotSweepAdmin();
}

library State {
  function require(bool ok) internal pure {
    Errors.illegalState(ok);
  }
}

library Value {
  function require(bool ok) internal pure {
    Errors.illegalValue(ok);
  }
}

library Access {
  function require(bool ok) internal pure {
    Errors.accessDenied(ok);
  }
}
