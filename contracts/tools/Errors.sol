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
  error Impossible();
  error IllegalValue();
  error NotSupported();
  error NotImplemented();
  error AccessDenied();

  error ExpiredPermit();
  error WrongPermitSignature();

  error ExcessiveVolatility();
  error ExcessiveVolatilityLock(uint256 mask);

  error CalllerNotEmergencyAdmin();
  error CalllerNotSweepAdmin();
  error CalllerNotOracleAdmin();

  error CollateralTransferFailed();

  error UnknownPriceAsset(address asset);
}

library Sanity {
  // slither-disable-next-line shadowing-builtin
  function require(bool ok) internal pure {
    // This code should be commented out on release
    if (!ok) {
      revert Errors.Impossible();
    }
  }
}

library State {
  // slither-disable-next-line shadowing-builtin
  function require(bool ok) internal pure {
    if (!ok) {
      revert Errors.IllegalState();
    }
  }
}

library Value {
  // slither-disable-next-line shadowing-builtin
  function require(bool ok) internal pure {
    if (!ok) {
      revert Errors.IllegalValue();
    }
  }
}

library Access {
  // slither-disable-next-line shadowing-builtin
  function require(bool ok) internal pure {
    if (!ok) {
      revert Errors.AccessDenied();
    }
  }
}
