import { TypedDataDomain, TypedDataField } from '@ethersproject/abstract-signer';
import { _TypedDataEncoder } from '@ethersproject/hash';
import { keccak256 } from '@ethersproject/keccak256';
import { toUtf8Bytes } from '@ethersproject/strings';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { signTypedData_v4 } from 'eth-sig-util'; // eslint-disable-line camelcase
import { fromRpcSig, ECDSASignature } from 'ethereumjs-util';
import { BigNumberish, Contract, ContractFunction, Overrides, Signature } from 'ethers';
import { splitSignature } from 'ethers/lib/utils';

export const encodeTypeHash = (typeName: string, types: Record<string, Array<TypedDataField>>): string => {
  const encoder = _TypedDataEncoder.from(types);
  return keccak256(toUtf8Bytes(encoder.encodeType(typeName)));
};

const getSignatureFromTypedData = (
  privateKey: string,
  typedData: any // eslint-disable-line @typescript-eslint/explicit-module-boundary-types,@typescript-eslint/no-explicit-any
  // ^^ should be TypedData, from eth-sig-utils, but TS doesn't accept it
): ECDSASignature => {
  const signature = signTypedData_v4(Buffer.from(privateKey.substring(2, 66), 'hex'), {
    data: typedData, // eslint-disable-line @typescript-eslint/no-unsafe-assignment
  });
  return fromRpcSig(signature);
};

type Functions = { [name: string]: ContractFunction };

class ContractFunctions<F extends Functions> extends Contract {
  readonly functions!: F;
}

type DropOverrides<T extends unknown[]> = T extends [...infer U, Overrides?] ? U : [...T];

export interface PermitMaker {
  domain: TypedDataDomain;
  types: Record<string, Array<TypedDataField>>;
  primaryType: string;
  value: Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

  encodeTypeHash(): string;
  getSignatureFromTypedData(privateKey: string): ECDSASignature;
  signBy(signer: SignerWithAddress): Promise<Signature>;
}

export const buildPermitMaker = <F extends Functions, N extends keyof F & string>(
  domain: {
    name: string;
    revision?: string;
    chainId: number;
  },
  params: {
    approver: string;
    nonce: BigNumberish;
    expiry: number;
  },
  c: ContractFunctions<F>,
  name: N,
  callArgs: DropOverrides<Parameters<F[N]>>
): PermitMaker => {
  const fragment = c.interface.getFunction(name);
  const mName = `${name}ByPermit`;

  const msgObj: Record<string, any> = { ...params }; // eslint-disable-line @typescript-eslint/no-explicit-any
  const args: Array<TypedDataField> = [];

  args.push({ name: 'approver', type: 'address' });
  fragment.inputs.forEach((param, index) => {
    args.push({
      name: param.name,
      type: param.format(),
    });
    msgObj[param.name] = callArgs[index]; // eslint-disable-line @typescript-eslint/no-unsafe-assignment
  });

  {
    const fragment2 = c.interface.getFunction(mName);
    args.forEach((param, index) => {
      const input = fragment2.inputs[index];
      const expected = input.format();
      if (param.type !== expected) {
        throw new Error(`Incompatible by-permit function: args[${index}], ${expected}, ${param.type}`);
      }
    });
  }

  args.push({ name: 'nonce', type: 'uint256' });
  args.push({ name: 'expiry', type: 'uint256' });

  return {
    domain: {
      name: domain.name,
      version: domain.revision ?? '1',
      chainId: domain.chainId,
      verifyingContract: c.address,
    },
    types: {
      [mName]: args,
    },
    primaryType: mName,
    value: msgObj,

    encodeTypeHash(): string {
      return encodeTypeHash(this.primaryType, this.types);
    },

    getSignatureFromTypedData(privateKey: string): ECDSASignature {
      return getSignatureFromTypedData(privateKey, this);
    },

    async signBy(signer: SignerWithAddress): Promise<Signature> {
      return splitSignature(await signer._signTypedData(this.domain, this.types, this.value)); // eslint-disable-line no-underscore-dangle
    },
  };
};
