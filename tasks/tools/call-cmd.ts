import { task, types } from 'hardhat/config';

import { exit } from 'process';

import { ZERO_ADDRESS } from '../../helpers/constants';
import { Factories } from '../../helpers/contract-types';
import { dreAction } from '../../helpers/dre';
import { notFalsyOrZeroAddress } from '../../helpers/runtime-utils';
import { ICallCommand } from '../subtasks/call-cmd';

task('call-cmd', 'Invokes a configuration command')
  .addParam('ctl', 'Address of MarketAddressController', ZERO_ADDRESS, types.string)
  .addFlag('static', 'Make this call as static')
  .addFlag('waittx', 'Wait for tx to complete')
  .addOptionalParam('roles', 'Role(s) for the call', '', types.string)
  .addOptionalParam('gaslimit', 'Gas limit', undefined, types.int)
  .addOptionalParam('gasprice', 'Gas price', undefined, types.int)
  .addOptionalParam('nonce', 'Nonce', undefined, types.int)
  .addOptionalVariadicPositionalParam('args', 'Command arguments')
  .setAction(
    dreAction(
      async ({ ctl, waittx, roles, static: staticCall, gaslimit: gasLimit, gasprice: gasPrice, nonce, args }, DRE) => {
        try {
          const prep = prepareArgs(ctl as string, roles as string, args as string[]);

          await DRE.run('helper:call-cmd', {
            // eslint-disable-next-line no-nested-ternary
            mode: staticCall ? 'static' : waittx ? 'waitTx' : 'call',
            ...prep,
            gaslimit: gasLimit as number,
            gasprice: gasPrice as number,
            nonce: nonce as number,
          });
        } catch (err) {
          console.error(err);
          exit(1);
        }
      }
    )
  );

task('encode-cmd', 'Encodes a configuration command')
  .addParam('ctl', 'Address of MarketAddressController', ZERO_ADDRESS, types.string)
  .addOptionalParam('roles', 'Role(s) for the call', '', types.string)
  .addOptionalVariadicPositionalParam('args', 'Command arguments')
  .setAction(
    dreAction(async ({ ctl, roles, args }, DRE) => {
      try {
        const prep = prepareArgs(ctl as string, roles as string, args as string[]);

        await DRE.run('helper:call-cmd', { mode: 'encode', ...prep });
      } catch (err) {
        console.error(err);
        exit(1);
      }
    })
  );

function prepareArgs(
  ctlArg: string,
  rolesArg: string,
  args: string[]
): {
  ctl: string;
  cmds: ICallCommand[];
} {
  const ctl = notFalsyOrZeroAddress(ctlArg) ? ctlArg : Factories.AccessController.get().address;
  const cmds: ICallCommand[] = [];
  const separator = '///';

  // eslint-disable-next-line no-nested-ternary
  const roleList: string[] = !rolesArg ? [] : rolesArg[0] !== '[' ? [rolesArg] : (JSON.parse(rolesArg) as string[]);

  args.push(separator);
  let j = 0;
  for (let i = 0; i < args.length; i++) {
    if (args[i] !== separator || i === j) {
      continue;
    }
    let cmd = args[j] || '';
    const roles = [...roleList];

    // eslint-disable-next-line no-constant-condition
    while (true) {
      const pos = cmd.indexOf('/');
      if (pos < 0) {
        break;
      }
      roles.push(cmd.substring(0, pos));
      cmd = cmd.substring(pos + 1);
    }

    cmds.push({
      roles,
      cmd,
      args: args.slice(j + 1, i),
    });
    j = i + 1;
  }

  console.log(cmds);

  return { ctl, cmds };
}
