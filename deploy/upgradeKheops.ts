import { ChainId, registry } from '@angleprotocol/sdk';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { Contract } from 'ethers';
import hre from 'hardhat';
import { DeployFunction } from 'hardhat-deploy/types';
import yargs from 'yargs';

import {
  Kheops,
  Kheops__factory,
  MockTokenPermit,
  MockTokenPermit__factory,
  ProxyAdmin,
  ProxyAdmin__factory,
} from '../typechain';

const argv = yargs.env('').boolean('ci').parseSync();

const func: DeployFunction = async ({ deployments, network, ethers }) => {
  console.log(`Deploying the contract on ${network.name}`);
  const { deploy } = deployments;
  const { deployer } = await ethers.getNamedSigners();

  let core: string;
  let proxyAdmin: string;
  let stableAddress: string;
  let governor: string;
  let signer: SignerWithAddress;
  let euroc: string;

  // Deployment only works if the deployer has enough to do a first deposit, otherwise it'll revert

  if (!network.live) {
    // If we're in mainnet fork, we're using the `CoreBorrow` address from mainnet
    core = registry(ChainId.MAINNET)?.CoreBorrow!;
    proxyAdmin = registry(ChainId.MAINNET)?.ProxyAdmin!;
    stableAddress = registry(ChainId.MAINNET)?.agEUR?.AgToken!;
    governor = registry(ChainId.MAINNET)?.Governor!;
    euroc = '0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c';

    console.log('Starting with the implementation');
    await deploy(`Kheops_Implementation`, {
      contract: 'Kheops',
      from: deployer.address,
      log: !argv.ci,
      args: [],
    });
    await deploy(`KheopsTest_Implementation`, {
      contract: 'KheopsTest',
      from: deployer.address,
      log: !argv.ci,
      args: [],
    });

    const implementationAddress = (await ethers.getContract(`Kheops_Implementation`)).address;
    const testImplementationAddress = (await ethers.getContract(`KheopsTest_Implementation`)).address;

    console.log(`Successfully deployed the contract at ${implementationAddress}`);
    console.log('');
    console.log('Now deploying the Proxy');

    await deploy('Kheops', {
      contract: 'TransparentUpgradeableProxy',
      from: deployer.address,
      args: [implementationAddress, proxyAdmin, '0x'],
      log: !argv.ci,
    });

    console.log('Successfully deployed the proxy');
    const proxyAddress = (await ethers.getContract('Kheops')).address;
    console.log('Now initializing the proxy');
    console.log(stableAddress, core);
    const kheops = new Contract(proxyAddress, Kheops__factory.abi, deployer) as Kheops;
    await kheops.connect(deployer).initialize(stableAddress, core);

    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [governor],
    });
    await hre.network.provider.send('hardhat_setBalance', [governor, '0x10000000000000000000000000000']);
    signer = await ethers.getSigner(governor);

    const proxyAdminContract = new ethers.Contract(
      proxyAdmin,
      ProxyAdmin__factory.createInterface(),
      signer,
    ) as ProxyAdmin;

    // Setting some storage in the contract
    const stablecoin = new Contract(euroc, MockTokenPermit__factory.abi, deployer) as MockTokenPermit;
    console.log('Adding Collateral');
    await kheops.connect(signer).addCollateral(euroc);
    console.log('Check');
    console.log((await kheops.collaterals(euroc)).decimals);
    await kheops.connect(signer).setFees(euroc, [1], [2], true);
    await kheops.connect(signer).setFees(euroc, [3], [4], false);
    console.log(await kheops.collaterals(euroc));
    console.log(await kheops.getCollateralFees(euroc, true));
    console.log(await kheops.getCollateralFees(euroc, false));
    console.log('Before this, approving the newly deployed proxy');
    // console.log((await kheops.collaterals(euroc)).extraData);
    await (await proxyAdminContract.connect(signer).upgrade(proxyAddress, testImplementationAddress)).wait();

    console.log((await kheops.collaterals(euroc)).decimals);

    console.log(await kheops.collaterals(euroc));
    console.log(await kheops.getCollateralFees(euroc, true));
    console.log(await kheops.getCollateralFees(euroc, false));
  }
};

func.tags = ['kheops-test'];
export default func;
