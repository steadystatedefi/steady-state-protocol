import { Wallet } from 'ethers';
import { task, types } from 'hardhat/config';

task('new-wallet', 'Generates a new wallet').setAction(() => {
  const w = Wallet.createRandom();
  console.log('New wallet');
  console.log('  Address:', w.address);
  console.log('       PK:', w.publicKey);
  console.log('       SK:', w.privateKey);
  console.log(' Menmonic:', w.mnemonic);
  return Promise.resolve();
});

task('mnemonic-wallet', 'Prints a wallet by mnemonic')
  .addOptionalPositionalParam('mnemonic', '', undefined, types.string)
  .setAction(({ mnemonic }) => {
    const w = Wallet.fromMnemonic(mnemonic as string);
    console.log('Wallet from mnemonic');
    console.log('  Address:', w.address);
    console.log('       PK:', w.publicKey);
    console.log('       SK:', w.privateKey);
    console.log(' Menmonic:', w.mnemonic);
    return Promise.resolve();
  });
