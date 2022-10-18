export const ProtocolErrors = {
  OperationPaused: 'OperationPaused()',
  IllegalState: 'IllegalState()',
  Impossible: 'Impossible()',
  IllegalValue: 'IllegalValue()',
  NotSupported: 'NotSupported()',
  NotImplemented: 'NotImplemented()',
  AccessDenied: 'AccessDenied()',
  BalanceOperationRestricted: 'BalanceOperationRestricted()',

  ExpiredPermit: 'ExpiredPermit()',
  WrongPermitSignature: 'WrongPermitSignature()',

  ExcessiveVolatility: 'ExcessiveVolatility()',
  ExcessiveVolatilityLock: 'ExcessiveVolatilityLock(uint256 mask)',

  CallerNotProxyOwner: 'CallerNotProxyOwner()',
  CallerNotEmergencyAdmin: 'CallerNotEmergencyAdmin()',
  CallerNotSweepAdmin: 'CallerNotSweepAdmin()',
  CallerNotOracleAdmin: 'CallerNotOracleAdmin()',

  CollateralTransferFailed: 'CollateralTransferFailed()',

  ContractRequired: 'ContractRequired()',
  ImplementationRequired: 'ImplementationRequired()',

  InitializerBlockedOff: 'InitializerBlockedOff()',
  AlreadyInitialized: 'AlreadyInitialized()',

  UnknownPriceAsset: 'UnknownPriceAsset(address asset)',

  TXT_OWNABLE_CALLER_NOT_OWNER: 'Ownable: caller is not the owner',
  TXT_OWNABLE_CALLER_NOT_PENDING_OWNER: 'SafeOwnable: caller is not the pending owner',
  TXT_OWNABLE_CALLER_NOT_RECOVER_OWNER: 'SafeOwnable: caller can not recover ownership',
  // 'Ownable: caller is not the owner (pending)' : 'Ownable: caller is not the owner'
};
