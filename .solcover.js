const { accounts } = require(`./helpers/test-wallets.json`);

module.exports = {
  client: require('ganache-core'),
  skipFiles: [
    './access',
    './access/interfaces',
    './funds/mocks',
    './insured/mocks',
    './insurer/mocks',
    './pricing',
    './pricing/interfaces',
    './interfaces',
    './dependencies',
    './tools',
  ],
  mocha: {
    enableTimeouts: false,
  },
  providerOptions: {
    accounts,
  },
};
