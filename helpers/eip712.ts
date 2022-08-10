import { TypedDataDomain, TypedDataField } from '@ethersproject/abstract-signer';
import { _TypedDataEncoder } from '@ethersproject/hash';
import { keccak256 } from '@ethersproject/keccak256';
import { toUtf8Bytes } from '@ethersproject/strings';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumberish, Contract, ContractFunction, Overrides, Signature } from 'ethers';
import { ParamType, splitSignature } from 'ethers/lib/utils';

type Functions = { [name: string]: ContractFunction };

class ContractFunctions<F extends Functions> extends Contract {
  readonly functions!: F;
}

type DropOverrides<T extends unknown[]> = T extends [...infer U, Overrides?] ? U : [...T];

export interface PermitMaker {
  domain: TypedDataDomain;
  types: Record<string, Array<TypedDataField>>;
  primaryType: string;
  value: Record<string, unknown>;

  domainSeparator(): string;
  encodeTypeHash(): string;
  signBy(signer: SignerWithAddress): Promise<Signature>;
}

const parseTuple = (
  types: Record<string, Array<TypedDataField>>,
  components: Array<ParamType>,
  typeNames: Map<string, string>
): Array<TypedDataField> => {
  const args: Array<TypedDataField> = [];

  components.forEach((param) => {
    let typeName = param.format();

    if (param.type === 'tuple') {
      let altName = typeNames.get(typeName);
      if (altName === undefined) {
        altName = `T${typeNames.size + 1}`;
        typeNames.set(typeName, altName);
      }
      typeName = altName;
      types[typeName] = parseTuple(types, param.components, typeNames); // eslint-disable-line no-param-reassign
    } else if (param.type === 'array') {
      throw new Error('not implemented');
    }
    args.push({
      name: param.name,
      type: typeName,
    });
  });

  return args;
};

export const buildPermitMaker = <F extends Functions, N extends keyof F & string>(
  domain: {
    name: string;
    version?: string;
    chainId: number;
  },
  params: {
    approver: string;
    nonce: BigNumberish;
    expiry: number;
  },
  c: ContractFunctions<F>,
  name: N,
  callArgs: DropOverrides<Parameters<F[N]>>,
  typeNames?: Record<string, string>
): PermitMaker => {
  const fragment = c.interface.getFunction(name);
  const mName = `${name}ByPermit`;

  const types: Record<string, Array<TypedDataField>> = {};

  const msgObj: Record<string, unknown> = { ...params };
  const args: Array<TypedDataField> = [];

  args.push({ name: 'approver', type: 'address' });

  const typeMap = new Map<string, string>();

  if (typeNames !== undefined) {
    Object.entries(typeNames).forEach((entry) => {
      typeMap.set(entry[0], entry[1]);
    });
  }

  parseTuple(types, fragment.inputs, typeMap).forEach((param, index) => {
    args.push(param);
    // eslint-disable-line @typescript-eslint/no-unsafe-assignment
    msgObj[param.name] = callArgs[index];
  });

  {
    const fragment2 = c.interface.getFunction(mName);
    args.forEach((param, index) => {
      const input = fragment2.inputs[index];
      const inputType = input.format();
      const expected = typeMap.get(inputType) ?? inputType;
      const actual = param.type;
      if (actual !== expected) {
        throw new Error(
          `Incompatible by-permit function: args[${index}], ${expected}, ${actual} ${
            index === 0 ? '' : fragment.inputs[index - 1].format()
          }`
        );
      }
    });
  }

  args.push({ name: 'nonce', type: 'uint256' });
  args.push({ name: 'expiry', type: 'uint256' });

  types[mName] = args;

  return {
    domain: {
      name: domain.name,
      version: domain.version ?? '1',
      chainId: domain.chainId,
      verifyingContract: c.address,
    },
    types,
    primaryType: mName,
    value: msgObj,

    domainSeparator(): string {
      return _TypedDataEncoder.hashDomain(this.domain);
    },

    encodeTypeHash(): string {
      return keccak256(toUtf8Bytes(_TypedDataEncoder.from(this.types).encodeType(this.primaryType)));
    },

    async signBy(signer: SignerWithAddress): Promise<Signature> {
      return splitSignature(await signer._signTypedData(this.domain, this.types, this.value)); // eslint-disable-line no-underscore-dangle
    },
  };
};
