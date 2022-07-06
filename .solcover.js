const { accounts } = require(`./helpers/test-wallets.json`);

module.exports = {
  client: require('ganache-core'),
  skipFiles: [
    './access/interfaces',
    './access/mocks',
    './funds/interfaces',
    './funds/mocks',
    './governance/interfaces',
    './governance/mocks',
    './insured/interfaces',
    './insured/mocks',
    './insurer/interfaces',
    './insurer/mocks',
    './premium/interfaces',
    './premium/mocks',
    './pricing',
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
