import { defaultAbiCoder } from '@ethersproject/abi';
import { Signer } from '@ethersproject/abstract-signer';
import { Contract } from '@ethersproject/contracts';
import { BigNumber } from 'ethers';

import { ProtocolErrors } from '../contract-errors';

import { FunctionAccessExceptions, getContractAccessExceptions } from './contracts-access';

function unquote(s: string): string {
  const quote = s[0];
  const single = quote === "'";
  return s
    .substring(1, s.length - 1)
    .replace(/\\\\/g, '\\')
    .replace(single ? /\\'/g : /\\"/g, quote);
}

interface SomeError {
  method: string;
  message: string;
  reason: string;
  error: SomeError;
  errorSignature: string;
  errorName: string;
  toString(): string;
}

function getErrorMessage(err: SomeError): string {
  // The error depends on provider and can be very different ...
  //
  // error.reason - The Revert reason; this is what you probably care about. :)
  // Additionally:
  // - error.address - the contract address
  // - error.args - [ BigNumber(1), BigNumber(2), BigNumber(3) ] in this case
  // - error.method - "someMethod()" in this case
  // - error.errorName
  // - error.errorSignature - "Error(string)" (the EIP 838 sighash; supports future custom errors)
  // - error.errorArgs - The arguments passed into the error (more relevant post EIP 838 custom errors)
  // - error.transaction - The call transaction used
  // console.log('>>>>>>>>>>>>>  ', error.reason, error.address, error.args, error.errorSignature, error.errorArgs, error.error)

  if (err.errorSignature && err.errorName !== 'Error') {
    return err.errorSignature;
  }

  let message = err.reason ?? err.message;
  if (message !== undefined) {
    return message;
  }

  const errorPrefix = 'Error:';
  message = err.toString();
  if (message && message.startsWith(errorPrefix)) {
    return message.substring(errorPrefix.length).trimStart();
  }

  return message ?? '';
}

const verifyMutableAccess = async (
  signer: Signer,
  c: Contract,
  name: string,
  isImpl: boolean,
  estimateGas: boolean | number,
  exceptions?: FunctionAccessExceptions,
  expected?: string[],
  checkAll?: boolean
): Promise<void> => {
  const DEFAULT_REVERTS = [
    ProtocolErrors.AccessDenied,
    ProtocolErrors.CallerNotEmergencyAdmin,
    ProtocolErrors.TXT_OWNABLE_CALLER_NOT_OWNER,
  ];

  const expectedReverts = new Set<string>(expected || DEFAULT_REVERTS);

  let hasErrors = false;

  const reportError = (error: object, fnName: string, args: unknown, message?: string | null) => {
    console.log(`\tMethod call: ${name}.${fnName}`, args);
    if ((message ?? null) !== null) {
      console.log(`\t\tError message:`, message);
    }
    hasErrors = true;
    if (!checkAll) {
      throw error;
    }
  };

  const contract = c.connect(signer);
  for (const [fnName, fnDesc] of Object.entries(contract.interface.functions)) {
    if (fnDesc.stateMutability === 'pure' || fnDesc.stateMutability === 'view') {
      continue;
    }

    let exception = exceptions ? exceptions[fnName] : undefined;
    if (!exception && exceptions) {
      exception = exceptions[fnName.substring(0, fnName.indexOf('('))];
    }

    const args = typeof exception === 'object' ? exception.args : defaultAbiCoder.getDefaultValue(fnDesc.inputs);
    if (typeof exception === 'object') {
      exception = exception.reason;
    }

    if (exception === true) {
      continue;
    }

    const isExpectedError = (hasReason: boolean, m?: string | null): boolean => {
      if ((m ?? null) === null) {
        return false;
      }

      const message = m ? m.trim() : '';
      const reasonNullCall = 'function call to a non-contract account';
      const reasonBrokenRedirect = "function selector was not recognized and there's no fallback function";

      if (hasReason) {
        if ((exception === undefined && expectedReverts.has(message)) || exception === message) {
          return true;
        }
      } else if (isImpl) {
        if (message === reasonNullCall || message === reasonBrokenRedirect) {
          return true;
        }
      }
      return false;
    };

    const handleError = (error: object, hasReason: boolean, m?: string | null) => {
      if (!isExpectedError(hasReason, m)) {
        if ((m ?? null) === null) {
          reportError(error, fnName, args, m);
        } else {
          reportError(error, fnName, args, m || getErrorMessage(error as SomeError));
        }
      }
    };

    let gasEstimate: BigNumber | null = null;

    if (typeof estimateGas === 'number' && estimateGas > 0) {
      gasEstimate = BigNumber.from(estimateGas);
    } else if (estimateGas === true || estimateGas === 0) {
      try {
        gasEstimate = (await contract.estimateGas[fnName](...args)).add(100_000);
      } catch (err: unknown) {
        const topError = err as SomeError;
        if (topError.method === 'estimateGas') {
          const error = topError.error ? topError.error : topError;
          const message = getErrorMessage(error);

          const prefixProviderReverted = 'execution reverted: ';
          const prefixProviderRevertedNoReason = 'execution reverted';

          if (message && message.indexOf(prefixProviderRevertedNoReason) !== 0) {
            const reason = substringAfter(message, prefixProviderReverted);
            if (isExpectedError(true, reason)) {
              handleError(error, true, reason);
              continue;
            }
          }
        }
        gasEstimate = BigNumber.from(1_000_000);
      }
    }

    try {
      if (gasEstimate === null) {
        await contract.callStatic[fnName](...args);
      } else {
        await contract.callStatic[fnName](...args, { gasLimit: gasEstimate });
      }
    } catch (err: unknown) {
      const topError = err as SomeError;
      const [reason, hasReason] = extractReason(topError, isImpl);
      handleError(topError, hasReason, reason);
      continue;
    }

    reportError(new Error(`Mutable function is accessible: ${name}.${fnName}`), fnName, args);
  }

  if (hasErrors) {
    throw new Error(`Access errors were found for ${name}`);
  }
};

function substringAfter(s: string, m: string, doUnquote?: boolean): string | null {
  const pos = (s ?? '').indexOf(m);
  if (pos < 0) {
    return null;
  }
  if (doUnquote) {
    return unquote(s.substring(pos + m.length - 1));
  }
  return s.substring(pos + m.length);
}

function extractReason(error: SomeError, isImpl: boolean): [string, boolean] {
  const message = getErrorMessage(error);

  const prefixReasonStr = "VM Exception while processing transaction: reverted with reason string '";
  const prefixReasonStr2 = 'VM Exception while processing transaction: revert with reason "';
  const prefixReasonStr3 = "VM Exception while processing transaction: reverted with custom error '";
  const prefixNoReason = 'Transaction reverted without a reason string';
  const prefixReverted = 'Transaction reverted: ';

  if (message === prefixNoReason) {
    return ['', false];
  }

  let reason = substringAfter(message, prefixReverted);
  if (isImpl && reason !== null) {
    return [reason, false];
  }

  reason =
    substringAfter(message, prefixReasonStr, true) ??
    substringAfter(message, prefixReasonStr2, true) ??
    substringAfter(message, prefixReasonStr3, true);

  if (reason !== null) {
    return [reason, true];
  }
  return [message ?? '', !!message];
}

export const verifyContractMutableAccess = async (
  signer: Signer,
  contract: Contract,
  name: string,
  estimateGas: boolean,
  checkAll: boolean
): Promise<void> => {
  const exceptions = getContractAccessExceptions(name);
  const isImpl = !!exceptions && !!exceptions.implOverride;
  const functions = isImpl ? { ...exceptions.functions, ...exceptions.implOverride } : exceptions?.functions;
  await verifyMutableAccess(signer, contract, name, isImpl, estimateGas, functions, exceptions?.reasons, checkAll);

  for (const delegateFactory of exceptions?.delegatedContracts ?? []) {
    console.log('\t\tChecking delegate:', delegateFactory.toString());
    const delegate = delegateFactory.attach(contract.address);
    await verifyContractMutableAccess(signer, delegate, delegateFactory.toString(), estimateGas, checkAll);
  }
};

export const verifyProxyMutableAccess = async (
  signer: Signer,
  contract: Contract,
  name: string,
  estimateGas: boolean,
  checkAll: boolean
): Promise<void> => {
  const exceptions = getContractAccessExceptions(name);
  await verifyMutableAccess(
    signer,
    contract,
    name,
    false,
    estimateGas,
    exceptions?.functions,
    exceptions?.reasons,
    checkAll
  );

  for (const delegateFactory of exceptions?.delegatedContracts ?? []) {
    console.log('\t\tChecking delegate:', delegateFactory.toString());
    const delegate = delegateFactory.attach(contract.address);
    await verifyProxyMutableAccess(signer, delegate, delegateFactory.toString(), estimateGas, checkAll);
  }
};
