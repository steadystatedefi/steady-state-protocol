import { ProtocolErrors } from '../contract-errors';
import { Factories } from '../contract-types';
import { NamedAttachable, NamedDeployable } from '../factory-wrapper';

export type FunctionAccessExceptions = { [key: string]: string | true | { args: unknown[]; reason?: string } };
export type ContractAccessExceptions = {
  implOverride?: FunctionAccessExceptions;
  functions: FunctionAccessExceptions;
  reasons?: string[];
  delegatedContracts?: NamedAttachable[];
};

const catalog: Map<string, ContractAccessExceptions> = new Map();

export const getContractAccessExceptions = (name: string): ContractAccessExceptions =>
  catalog.get(name) as ContractAccessExceptions;

function add(f: NamedDeployable, x: ContractAccessExceptions): void {
  const n = f.name();
  if (!n) {
    throw new Error('Unnamed factory');
  }
  if (catalog.has(n)) {
    throw new Error(`Duplicate: ${n}`);
  }

  catalog.set(n, x);
}

add(Factories.AccessController, {
  functions: {
    acceptOwnershipTransfer: ProtocolErrors.TXT_OWNABLE_CALLER_NOT_PENDING_OWNER,
    recoverOwnership: ProtocolErrors.TXT_OWNABLE_CALLER_NOT_RECOVER_OWNER,
    renounceTemporaryAdmin: true,
  },
});

const ERC20: ContractAccessExceptions = {
  functions: {
    approve: true,
    decreaseAllowance: true,
    increaseAllowance: true,
    useAllowance: true,
    transfer: true,
    transferFrom: true,
    permit: true,
  },
};

add(Factories.CollateralCurrencyV1, {
  functions: {
    ...ERC20.functions,

    pullYield: true,
    initializeCollateralCurrency: ProtocolErrors.AlreadyInitialized,
  },

  implOverride: {
    initializeCollateralCurrency: ProtocolErrors.InitializerBlockedOff,
  },
});

add(Factories.ProxyCatalog, {
  functions: {
    createCustomProxy: true,
  },
});

add(Factories.FrontHelper, {
  functions: {
    syncSwapInfo: true,
  },
});

add(Factories.ApprovalCatalogV1, {
  functions: {
    submitApplication: true,
    submitApplicationWithImpl: true,
    resubmitApplication: true,
    applyApprovedApplication: true,
    applyApprovedClaim: true,

    initializeApprovalCatalog: ProtocolErrors.AlreadyInitialized,
  },

  implOverride: {
    initializeApprovalCatalog: ProtocolErrors.InitializerBlockedOff,
  },
});

add(Factories.OracleRouterV1, {
  reasons: [ProtocolErrors.CallerNotOracleAdmin],
  functions: {
    pullAssetPrice: true,
    attachSource: true,
    resetSourceGroup: true,

    initializePriceOracle: ProtocolErrors.AlreadyInitialized,
  },

  implOverride: {
    initializePriceOracle: ProtocolErrors.InitializerBlockedOff,
  },
});

add(Factories.CollateralFundV1, {
  functions: {
    deposit: true,
    invest: true,
    investIncludingDeposit: true,
    withdraw: true,
    setAllApprovalsFor: true,
    setApprovalsFor: true,

    // no assets to check
    borrow: ProtocolErrors.IllegalState,
    repay: ProtocolErrors.IllegalState,
    trustedInvest: ProtocolErrors.IllegalState,
    trustedDeposit: ProtocolErrors.IllegalState,
    trustedWithdraw: ProtocolErrors.IllegalState,

    initializeCollateralFund: ProtocolErrors.AlreadyInitialized,
  },

  implOverride: {
    initializeCollateralFund: ProtocolErrors.InitializerBlockedOff,
  },
});

add(Factories.ReinvestorV1, {
  functions: {
    initializeReinvestor: ProtocolErrors.AlreadyInitialized,
  },

  implOverride: {
    initializeReinvestor: ProtocolErrors.InitializerBlockedOff,
  },
});

add(Factories.PremiumFundV1, {
  functions: {
    setApprovalsFor: true,
    swapAsset: true,
    swapAssets: true,
    syncAsset: true,
    syncAssets: true,

    // no assets to check
    registerPremiumSource: ProtocolErrors.IllegalState,
    premiumAllocationUpdated: ProtocolErrors.IllegalState,
    premiumAllocationFinished: ProtocolErrors.IllegalState,

    initializePremiumFund: ProtocolErrors.AlreadyInitialized,
  },

  implOverride: {
    initializePremiumFund: ProtocolErrors.InitializerBlockedOff,
  },
});

add(Factories.InsuredPoolV1, {
  functions: {
    ...ERC20.functions,

    initializeInsured: ProtocolErrors.AlreadyInitialized,
  },

  implOverride: {
    initializeInsured: ProtocolErrors.InitializerBlockedOff,
  },
});

add(Factories.JoinablePoolExtension, {
  functions: {
    cancelJoin: true,
  },
});

add(Factories.ImperpetualPoolExtension, {
  functions: {
    applyPendingAdjustments: true,
  },
});

add(Factories.ImperpetualPoolV1, {
  functions: {
    ...ERC20.functions,

    pushCoverageExcess: true,
    cancelJoin: true,

    initializeWeighted: ProtocolErrors.AlreadyInitialized,
  },

  implOverride: {
    initializeWeighted: ProtocolErrors.InitializerBlockedOff,
  },

  delegatedContracts: [Factories.ImperpetualPoolExtension, Factories.JoinablePoolExtension],
});
