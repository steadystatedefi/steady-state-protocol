const accounts = require(`./helpers/test-wallets.js`).accounts;

module.exports = {
  client: require('ganache-cli'),
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
    './tools'
  ],
  mocha: {
    enableTimeouts: false,
  },
  providerOptions: {
    accounts,
  },
};

