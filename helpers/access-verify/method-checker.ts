import { defaultAbiCoder } from '@ethersproject/abi';
import { Signer } from '@ethersproject/abstract-signer';
import { Contract } from '@ethersproject/contracts';

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
  // - error.errorSignature - "Error(string)" (the EIP 838 sighash; supports future custom errors)
  // - error.errorArgs - The arguments passed into the error (more relevant post EIP 838 custom errors)
  // - error.transaction - The call transaction used
  // console.log('>>>>>>>>>>>>>  ', error.reason, error.address, error.args, error.errorSignature, error.errorArgs, error.error)

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
  estimateGas: boolean,
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

  const reportError = (error: object, fnName: string, args: unknown) => {
    console.log(`${name}.${fnName}`, args);
    console.error(error);
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

    const reasonUnknown = '<<MISSING>>';
    const handleError = (error: object, m: string | undefined, hasReason: boolean) => {
      if (m === undefined) {
        reportError(error, fnName, args);
        return;
      }

      const message = m.trim();
      const reasonNullCall = 'function call to a non-contract account';
      const reasonBrokenRedirect = "function selector was not recognized and there's no fallback function";

      if (hasReason) {
        if ((exception === undefined && expectedReverts.has(message)) || exception === message) {
          return;
        }
      } else if (isImpl) {
        if (message === reasonNullCall || message === reasonBrokenRedirect || message === reasonUnknown) {
          return;
        }
      }
      reportError(error, fnName, args);
    };

    const substringAfter = (s: string, m: string, doUnquote?: boolean): string | undefined => {
      const pos = (s ?? '').indexOf(m);
      if (pos < 0) {
        return undefined;
      }
      if (doUnquote) {
        return unquote(s.substring(pos + m.length - 1));
      }
      return s.substring(pos + m.length);
    };

    try {
      await contract.callStatic[fnName](...args, {
        gasLimit: estimateGas ? (await contract.estimateGas[fnName](...args)).add(100000) : undefined,
      });
    } catch (err) {
      const error = err as SomeError;
      if (error.method === 'estimateGas') {
        const prefixProviderReverted = 'execution reverted: ';
        const prefixProviderRevertedNoReason = 'execution reverted';

        const message = getErrorMessage(error.error);
        const reason = substringAfter(message, prefixProviderReverted);
        if (reason !== undefined) {
          handleError(error, reason, true);
        } else if (message && message.indexOf(prefixProviderRevertedNoReason) !== 0) {
          handleError(error, reasonUnknown, false);
        }
        continue;
      }

      const message: string = getErrorMessage(error);

      const prefixReasonStr = "VM Exception while processing transaction: reverted with reason string '";
      const prefixReasonStr2 = 'VM Exception while processing transaction: revert with reason "';
      const prefixReasonStr3 = "VM Exception while processing transaction: reverted with custom error '";
      const prefixNoReason = 'Transaction reverted without a reason string';
      const prefixReverted = 'Transaction reverted: ';

      if (message === prefixNoReason) {
        // console.log('1');
        handleError(error, '', true);
        continue;
      }

      let reason = substringAfter(message, prefixReverted);
      if (isImpl && reason !== undefined) {
        handleError(error, reason, false);
      } else {
        reason =
          substringAfter(message, prefixReasonStr, true) ??
          substringAfter(message, prefixReasonStr2, true) ??
          substringAfter(message, prefixReasonStr3, true);

        handleError(error, reason, true);
      }
      continue;
    }
    reportError(new Error(`Mutable function is accessible: ${name}.${fnName}`), fnName, args);
  }

  if (hasErrors) {
    throw new Error(`Access errors were found for ${name}`);
  }
};

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
};
