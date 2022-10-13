import { BigNumber as BigNumber2 } from '@ethersproject/bignumber';
import { chainConfig } from '@nomiclabs/hardhat-etherscan/dist/src/ChainConfig';
import { getEtherscanEndpoints } from '@nomiclabs/hardhat-etherscan/dist/src/network/prober';
import { Libraries } from '@nomiclabs/hardhat-etherscan/dist/src/solc/libraries';
import axios, { AxiosRequestConfig } from 'axios';
import BigNumber from 'bignumber.js';
import qs from 'qs';

import { DRE } from './dre';
import { sleep } from './runtime-utils';

export const stringifyArgs = (args: unknown): string =>
  JSON.stringify(args, (_key, value) => {
    if (typeof value === 'number') {
      return new BigNumber(value).toFixed();
    }

    if (typeof value === 'object') {
      if (value instanceof BigNumber) {
        return value.toFixed();
      }

      if (value instanceof BigNumber2) {
        return value.toString();
      }

      if ((value as { type: string }).type === 'BigNumber') {
        return BigNumber2.from(value).toString();
      }
    }

    return value as unknown;
  });

export const verifyContract = async (
  address: string,
  constructorArguments: (string | string[])[],
  libraries?: string
): Promise<[ok: boolean, err: string]> => verify(address, constructorArguments, libraries);

export const verifyContractStringified = async (
  address: string,
  constructorArguments: string,
  libraries?: string
): Promise<[ok: boolean, err: string]> => verify(address, JSON.parse(constructorArguments) as unknown[], libraries);

// extracted from hardhat-etherscan
interface VerificationSubtaskArgs {
  address: string;
  constructorArguments: unknown[];
  // Fully qualified name of the contract
  contract?: string;
  libraries?: Libraries;
}

async function verify(
  address: string,
  constructorArguments: unknown[],
  libraries?: string
): Promise<[ok: boolean, err: string]> {
  const params: VerificationSubtaskArgs = {
    address,
    constructorArguments,
  };

  if (libraries) {
    params.libraries = JSON.parse(libraries) as Libraries;
  }

  try {
    await DRE.run('verify:verify', params);
  } catch (error) {
    const { message } = error as Error;
    if (message === 'Contract source code already verified') {
      return [true, ''];
    }

    return [false, message];
  }

  return [true, ''];
}

export const verifyProxy = async (proxyAddr: string, implAddr: string): Promise<[ok: boolean, errMsg: string]> => {
  try {
    await internalVerifyProxy(proxyAddr, implAddr);
  } catch (error) {
    return [false, (error as Error).message];
  }

  return [true, ''];
};

async function internalVerifyProxy(proxyAddr: string, implAddr: string) {
  const { config } = DRE;
  const apiKey = config.etherscan.apiKey as string;
  const endpoints = await getEtherscanEndpoints(DRE.network.provider, DRE.network.name, chainConfig, []);
  const baseUrl = `${endpoints.urls.apiURL}?module=contract`;

  let guid: string;
  {
    const optionsVerify: AxiosRequestConfig = {
      method: 'POST',
      url: `${baseUrl}&action=verifyproxycontract&apikey=${apiKey}`,
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      data: qs.stringify({ address: proxyAddr, expectedimplementation: implAddr }),
    };
    const result = await axios(optionsVerify);
    const response = new EtherscanResponse(result.data as { status: string; result: string });

    if (!response.isOk()) {
      if (response.isProxyImplNotDetected()) {
        if (await internalVerifyProxyByWebForm(endpoints.urls.browserURL, proxyAddr, implAddr)) {
          return;
        }
      }
      throw new Error(response.message);
    }

    guid = response.message;
  }

  {
    const optionsStatus: AxiosRequestConfig = {
      method: 'GET',
      url: `${baseUrl}&action=checkproxyverification&guid=${guid}&apikey=${apiKey}`,
    };
    for (let i = 0; ; i += 1) {
      const result = await axios(optionsStatus);
      const response = new EtherscanResponse(result.data as { status: string; result: string });

      if (response.isOk()) {
        console.log();
        console.log(response.message);
        return;
      }

      if (!response.isPending()) {
        if (response.isProxyImplNotDetected()) {
          if (await internalVerifyProxyByWebForm(endpoints.urls.browserURL, proxyAddr, implAddr)) {
            return;
          }
        }

        throw Error(response.message);
      }

      if (i >= 20) {
        throw Error('Too many retries');
      }

      await sleep(100 + i * 200);
    }
  }
}

class EtherscanResponse {
  public readonly status: number;

  public readonly message: string;

  public constructor(response: { status: string; result: string }) {
    this.status = parseInt(response.status, 10);
    this.message = response.result;
  }

  public isPending() {
    return this.message === 'Pending in queue';
  }

  public isVerificationFailure() {
    return this.message === 'Fail - Unable to verify';
  }

  public isVerificationSuccess() {
    return this.message === 'Pass - Verified';
  }

  public isBytecodeMissingInNetworkError() {
    return this.message.startsWith('Unable to locate ContractCode at');
  }

  public isProxyImplNotDetected() {
    // A corresponding implementation contract was unfortunately not detected for the proxy address
    return this.message.startsWith('A corresponding implementation contract');
  }

  public isOk() {
    return this.status === 1;
  }
}

let lastCallAt = 0;
const defaultWebFormDelay = 3000; // millis

async function internalVerifyProxyByWebForm(endpoint: string, proxyAddr: string, implAddr: string): Promise<boolean> {
  const baseUrl = `${endpoint}/proxyContractChecker?a=${proxyAddr}`;
  console.log(`\n\tVerifying proxy via the web form...`);

  const fillForm = (s: string) => {
    const form = {
      __VIEWSTATE: '',
      __VIEWSTATEGENERATOR: '',
      __EVENTVALIDATION: '',
      ctl00$ContentPlaceHolder1$txtContractAddress: proxyAddr,
    };

    const re = / id="(__(VIEWSTATE|VIEWSTATEGENERATOR|EVENTVALIDATION))" +value="([^"]+)"/g;

    let m: RegExpExecArray | null;
    // eslint-disable-next-line no-cond-assign
    while ((m = re.exec(s))) {
      const index = m[1];
      const value = m[3];

      form[index] = value;
    }

    // eslint-disable-next-line no-underscore-dangle
    if (!form.__EVENTVALIDATION || !form.__VIEWSTATE || !form.__VIEWSTATEGENERATOR) {
      console.log(s);
      throw new Error('Unable to find fields required for the web form');
    }

    return form;
  };

  let webFormDelay = defaultWebFormDelay;
  const sendRequest = async (optionsVerify: AxiosRequestConfig, reqType: string) => {
    for (let i = 10; i > 0; i -= 1) {
      {
        const current = new Date().getTime();
        const remains = lastCallAt + webFormDelay - current;
        lastCallAt = current;
        if (remains > 0) {
          await sleep(remains);
        }
      }

      const result = await axios(optionsVerify);
      if (result.status !== 200) {
        console.log('Unexpected response:', reqType, result.status, result.statusText);
        return undefined;
      }
      const s = <string>result.data;
      if (s.indexOf('our servers are currently busy') < 0) {
        return s;
      }
      webFormDelay += 10000;
      console.log('\tServer is busy, wait for', webFormDelay, 'ms');
    }
    throw new Error('Too many retries for the web form');
  };

  let form;
  {
    const s = await sendRequest(
      {
        method: 'GET',
        url: baseUrl,
      },
      'get'
    ); // sampleGet;
    if (!s) {
      return false;
    }
    form = fillForm(s);
  }

  {
    const req: AxiosRequestConfig = {
      method: 'POST',
      headers: {
        Origin: endpoint,
        'Content-Type': 'application/x-www-form-urlencoded',
        Referer: baseUrl,
      },
      url: baseUrl,
    };

    const s = await sendRequest(
      {
        ...req,
        data: qs.stringify({
          ...form,
          ctl00$ContentPlaceHolder1$btnSubmit: 'Verify',
        }),
      },
      'verify'
    ); // sampleVerify;
    if (!s) {
      return false;
    }

    const re = / implementation contract is found at: <a href='\/address\/(0x[0-9a-fA-F]+)'>/;
    const m = re.exec(s);
    if (!m) {
      return false;
    }

    const foundImpl = m[1];
    if (foundImpl.toLowerCase() !== implAddr.toLowerCase()) {
      throw new Error(`Proxy implementation mismatched: expected=${implAddr}, found=${foundImpl}`);
    }

    form = fillForm(s);
    const s2 = await sendRequest(
      {
        ...req,
        data: qs.stringify({
          ...form,
          ctl00$ContentPlaceHolder1$btnSubmitProxyDetails: 'Save',
        }),
      },
      'save'
    );
    if (!s2 || s2.indexOf('Successfully saved') < 0) {
      return false;
    }

    return true;
  }
}
