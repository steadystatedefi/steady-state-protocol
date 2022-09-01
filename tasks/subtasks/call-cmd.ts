import { Contract, ContractTransaction } from '@ethersproject/contracts';
import { BigNumber, BigNumberish } from 'ethers';
import { subtask, types } from 'hardhat/config';

import { AccessFlag, AccessFlags } from '../../helpers/access-flags';
import { ZERO, ZERO_ADDRESS } from '../../helpers/constants';
import { Factories, getFactory } from '../../helpers/contract-types';
import { stringifyArgs } from '../../helpers/contract-verification';
import {
  getExternalFromJsonDb,
  getExternalsFromJsonDb,
  getFromJsonDb,
  getInstanceFromJsonDb,
} from '../../helpers/deploy-db';
import { falsyOrZeroAddress } from '../../helpers/runtime-utils';
import { AccessController } from '../../types';

interface ICallParams {
  applyCall: (accessFlags: BigNumber, contract: Contract, fnName: string, isStatic: boolean, args: unknown[]) => void;
}

export interface ICallCommand {
  roles: string[];
  cmd: string;
  args: unknown[];
}

subtask('helper:call-cmd', 'Invokes a configuration command')
  .addParam('ctl', 'Address of AccessController', ZERO_ADDRESS, types.string)
  .addParam('mode', 'Call mode: call, waitTx, encode, static', 'call', types.string)
  .addOptionalParam('gaslimit', 'Gas limit', undefined, types.int)
  .addOptionalParam('gasprice', 'Gas price', undefined, types.int)
  .addOptionalParam('nonce', 'Nonce', undefined, types.int)
  .addParam('cmds', 'Commands', [], types.any)
  .setAction(async ({ ctl, mode: modeArg, cmds, gaslimit, gasprice, nonce }) => {
    const gasLimit = gaslimit as number;
    const gasPrice = gasprice as number;
    const mode = modeArg as string;

    if (falsyOrZeroAddress(ctl as string)) {
      throw new Error('Unknown AccessController');
    }
    const ac = Factories.AccessController.attach(ctl as string);

    const contractCalls: {
      accessFlags: BigNumber;
      contract: Contract;
      fnName: string;
      isStatic: boolean;
      args: unknown[];
    }[] = [];

    let allFlags = ZERO;
    let allStatic = true;

    const callParams = <ICallParams>{
      applyCall: (accessFlags: BigNumber, contract: Contract, fnName: string, isStatic: boolean, args: unknown[]) => {
        console.log('Parsed', isStatic ? 'static call:' : 'call:', contract.address, fnName, args);
        allFlags = allFlags.or(accessFlags);
        allStatic &&= isStatic;
        contractCalls.push({ accessFlags, contract, fnName, isStatic, args });
      },
    };

    for (const cmdEntry of <ICallCommand[]>cmds) {
      await parseCommand(ac, callParams, cmdEntry.roles, cmdEntry.cmd, cmdEntry.args || []);
    }

    if (contractCalls.length === 0) {
      console.log('Nothing to call');
      return;
    }

    const prepareCallWithRolesArgs = () => {
      const callWithRolesBatchArgs: {
        accessFlags: BigNumber;
        callFlag: number;
        callAddr: string;
        callData: string;
      }[] = [];
      for (const call of contractCalls) {
        callWithRolesBatchArgs.push({
          accessFlags: call.accessFlags,
          callFlag: 0,
          callAddr: call.contract.address,
          callData: call.contract.interface.encodeFunctionData(call.fnName, call.args),
        });
      }
      return callWithRolesBatchArgs;
    };

    if (mode === 'encode') {
      if (contractCalls.length === 1 && allFlags.eq(0)) {
        const cc = contractCalls[0];
        const encodedCall = cc.contract.interface.encodeFunctionData(cc.fnName, cc.args);
        console.log(`\nEncoded call:\n\n{\n\tto: "${cc.contract.address}",\n\tdata: "${encodedCall}"\n}\n`);
      } else {
        const encodedCall = ac.interface.encodeFunctionData('callWithRolesBatch', [prepareCallWithRolesArgs()]);
        console.log(`\nEncoded call with roles:\n\n{\n\tto: "${ac.address}",\n\tdata: "${encodedCall}"\n}\n`);
        if (allStatic && allFlags.eq(0)) {
          console.log('ATTN! All encoded methods are static and require no access permissions.');
        }
      }
      return;
    }
    console.log('\nCaller', await ac.signer.getAddress());

    const overrides = { gasLimit, gasPrice, nonce: nonce as number };

    if (mode === 'static' || (allStatic && allFlags.eq(0))) {
      if (contractCalls.length === 1 && allFlags.eq(0)) {
        const cc = contractCalls[0];
        console.log(`Calling as static`, cc.contract.address);
        const result = (await cc.contract.callStatic[cc.fnName](...cc.args)) as unknown;
        console.log(`Result: `, stringifyArgs(result));
      } else {
        console.log(`Calling as static batch (${contractCalls.length})`, ac.address);
        const encodedResult = await ac.callStatic.callWithRolesBatch(prepareCallWithRolesArgs(), overrides);
        for (let i = 0; i < contractCalls.length; i++) {
          const cc = contractCalls[i];
          const result = cc.contract.interface.decodeFunctionResult(cc.fnName, encodedResult[i]);
          console.log(`Result of ${cc.fnName}: `, stringifyArgs(result));
        }
      }
      return;
    }

    let waitTxFlag = false;
    switch (mode) {
      case 'waitTx':
        waitTxFlag = true;
        break;
      case 'call':
        break;
      default:
        throw new Error(`unknown mode:${mode}`);
    }

    let tx: ContractTransaction;
    if (contractCalls.length === 1 && allFlags.eq(0)) {
      const cc = contractCalls[0];
      console.log(`Calling`, cc.contract.address);
      tx = (await cc.contract.functions[cc.fnName](...cc.args, overrides)) as ContractTransaction;
    } else {
      console.log(`Calling as batch`, ac.address);
      tx = await ac.callWithRolesBatch(prepareCallWithRolesArgs(), overrides);
    }

    console.log('Tx hash:', tx.hash);
    if (waitTxFlag) {
      console.log('Gas used:', (await tx.wait(1)).gasUsed.toString());
    }
  });

async function parseCommand(
  ac: AccessController,
  callParams: ICallParams,
  roles: BigNumberish[],
  command: string,
  cmdArgs: unknown[]
): Promise<void> {
  const dotPos = command.indexOf('.');
  if (dotPos >= 0) {
    await callQualifiedFunc(ac, roles, command, cmdArgs, callParams);
    return;
  }

  const call = async (cmd: string, args: unknown[], role: AccessFlag) => {
    console.log('Call alias:', cmd, args);
    await callQualifiedFunc(ac, role === undefined ? [] : [role], cmd, args, callParams);
  };

  // const qualifiedName = (typeId: string, instanceId: keyof typeof AccessFlags | string, funcName: string) =>
  //   `${typeId}@${typeof instanceId === 'string' ? instanceId : AccessFlags[instanceId]}.${funcName}`;

  const cmdAliases: {
    [key: string]:
      | (() => Promise<void>)
      | {
          cmd: string;
          role?: AccessFlag;
        };
  } = {};

  const fullCmd = cmdAliases[command];
  if (!fullCmd) {
    throw new Error(`Unknown command: ${command}`);
  } else if (typeof fullCmd === 'object') {
    await call(fullCmd.cmd, cmdArgs, fullCmd.role ?? 0);
  } else {
    await fullCmd();
  }
}

async function callQualifiedFunc(
  ac: AccessController,
  roles: BigNumberish[],
  cmd: string,
  args: unknown[],
  callParams: ICallParams
): Promise<void> {
  const dotPos = cmd.indexOf('.');
  const objName = cmd.substring(0, dotPos);
  const funcName = cmd.substring(dotPos + 1);
  const contract = await findObject(ac, objName);

  callContract(ac, roles, contract, funcName, args, callParams);
}

async function findObject(ac: AccessController, objName: string): Promise<Contract> {
  if (objName === 'AC' || objName === 'ACCESS_CONTROLLER') {
    return ac;
  }

  const bracketPos = objName.indexOf('@');
  if (bracketPos < 0) {
    const objEntry = getFromJsonDb(objName);
    if (objEntry) {
      let instEntry = getInstanceFromJsonDb(objEntry.address);
      if (!instEntry) {
        instEntry = getExternalFromJsonDb(objEntry.address);
      }

      if (instEntry) {
        const factory = getFactory(instEntry.factory);
        return factory.attach(objEntry.address);
      }
    }

    const found = getExternalsFromJsonDb().filter(
      ([, desc]) => desc.id === objName && !falsyOrZeroAddress(desc.verify?.impl)
    );

    if (found.length === 0) {
      throw new Error(`Unknown object name: ${objName}`);
    } else if (found.length > 1) {
      throw new Error(`Ambigous object name: ${objName}, ${JSON.stringify(found)}`);
    }
    const [addr, desc] = found[0];

    const factory = getFactory(desc.factory);
    return factory.attach(addr);
  }

  const typeName = objName.substring(0, bracketPos);
  let addrName = objName.substring(bracketPos + 1);

  if (addrName.substring(0, 2) !== '0x') {
    const roleId = AccessFlags[addrName] as AccessFlag;
    if (!roleId) {
      throw new Error(`Unknown role: ${typeName}`);
    }
    addrName = await ac.getAddress(roleId);
  }

  if (falsyOrZeroAddress(addrName)) {
    throw new Error(`Invalid address: ${addrName}`);
  }

  const factory = getFactory(typeName);
  return factory.attach(addrName);
}

function callContract(
  ac: AccessController,
  roles: BigNumberish[],
  contract: Contract,
  funcName: string,
  args: unknown[],
  callParams: ICallParams
): void {
  let accessFlags = BigNumber.from(0);
  console.log('roles', roles);
  roles.forEach((value) => {
    if (typeof value === 'number') {
      accessFlags = accessFlags.or(value);
    } else if (typeof value === 'string') {
      const id = AccessFlags[value] as AccessFlag;
      if (!id || ZERO.eq(id)) {
        throw new Error(`Unknown role: ${value}`);
      }
      accessFlags = accessFlags.or(id);
    } else {
      accessFlags = accessFlags.or(value);
    }
  });

  const fnFrag = contract.interface.getFunction(funcName);
  callParams.applyCall(accessFlags, contract, fnFrag.name, fnFrag.constant, args);
}
