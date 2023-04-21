import { ChainId, registry } from '@angleprotocol/sdk';
import { Contract } from 'ethers';
import { DeployFunction } from 'hardhat-deploy/types';
import yargs from 'yargs';

import { MAX_UINT256 } from '../test/hardhat/utils/helpers';
import { MockTokenPermit, MockTokenPermit__factory, Savings, Savings__factory } from '../typechain';

const argv = yargs.env('').boolean('ci').parseSync();

const func: DeployFunction = async ({ deployments, network, ethers }) => {
  console.log(`Deploying the contract on ${network.name}`);
  const { deploy } = deployments;
  const { deployer } = await ethers.getNamedSigners();

  let core: string;
  let proxyAdmin: string;
  let contractName: string;
  const stable = 'AgEUR';
  const name = 'Angle Euro Savings Contract';
  const symbol = 'xagEUR';
  const divizer = 1;
  let stableAddress: string;

  // Deployment only works if the deployer has enough to do a first deposit, otherwise it'll revert

  if (!network.live) {
    // If we're in mainnet fork, we're using the `CoreBorrow` address from mainnet
    core = registry(ChainId.MAINNET)?.CoreBorrow!;
    proxyAdmin = registry(ChainId.MAINNET)?.ProxyAdmin!;
    contractName = 'Savings' + stable + 'Ethereum';
    stableAddress = registry(ChainId.MAINNET)?.agEUR?.AgToken!;
  } else {
    // Otherwise, we're using the proxy admin address from the desired network
    core = registry(network.config.chainId as ChainId)?.CoreBorrow!;
    proxyAdmin = registry(network.config.chainId as ChainId)?.ProxyAdmin!;
    stableAddress = registry(network.config.chainId as ChainId)?.agEUR?.AgToken!;
    contractName = 'Savings' + stable + network.name.charAt(0).toUpperCase() + network.name.substring(1);
  }

  console.log('Starting with the implementation');
  await deploy(`Savings_Implementation`, {
    contract: 'Savings',
    from: deployer.address,
    log: !argv.ci,
    args: [],
  });
  const implementationAddress = (await ethers.getContract(`Savings_Implementation`)).address;

  console.log(`Successfully deployed the contract at ${implementationAddress}`);
  console.log('');
  console.log('Now deploying the Proxy');

  await deploy(contractName, {
    contract: 'TransparentUpgradeableProxy',
    from: deployer.address,
    args: [implementationAddress, proxyAdmin, '0x'],
    log: !argv.ci,
  });

  console.log('Successfully deployed the proxy');
  const proxyAddress = (await ethers.getContract(contractName)).address;
  console.log('Now initializing the proxy');

  const stablecoin = new Contract(stableAddress, MockTokenPermit__factory.abi, deployer) as MockTokenPermit;
  console.log('Before this, approving the newly deployed proxy');
  await (await stablecoin.connect(deployer).approve(proxyAddress, MAX_UINT256)).wait();

  console.log('Success');
  console.log(stablecoin.address);
  console.log('Deployer Balance', await stablecoin.balanceOf(deployer.address));
  const proxy = new Contract(proxyAddress, Savings__factory.abi, deployer) as Savings;
  console.log('Initializing...');
  await (await proxy.connect(deployer).initialize(core, stableAddress, name, symbol, divizer)).wait();
  console.log('Success');
};

func.tags = ['savings'];
export default func;
