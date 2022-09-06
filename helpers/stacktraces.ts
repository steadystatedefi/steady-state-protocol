import { Logger, ErrorCode } from '@ethersproject/logger';

interface ErrorParams {
  error?: {
    stackTrace?: {
      sourceReference?: {
        sourceContent?: string;
      };
    }[];
  };
}

let superMakeError: ((this: Logger, message: string, code?: ErrorCode, params?: ErrorParams) => Error) | null = null;

function makeErrorNoSources(this: Logger, message: string, code?: ErrorCode, params?: ErrorParams): Error {
  const stackTrace = params?.error?.stackTrace;
  if (stackTrace?.length) {
    stackTrace.forEach((value) => {
      if (value?.sourceReference?.sourceContent) {
        // eslint-disable-next-line no-param-reassign
        delete value.sourceReference.sourceContent;
      }
    });
  }
  // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
  return superMakeError!.bind(this)(message, code, params);
}

export function improveStackTrace(): void {
  if (superMakeError === null) {
    // eslint-disable-next-line @typescript-eslint/unbound-method
    superMakeError = Logger.prototype.makeError;
    Logger.prototype.makeError = makeErrorNoSources;
  }
}
