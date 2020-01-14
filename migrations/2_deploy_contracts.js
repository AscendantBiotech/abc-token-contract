var EthLocker = artifacts.require('eth_locker');

module.exports = function(deployer) {
  deployer.deploy(EthLocker, 'initial');
};
