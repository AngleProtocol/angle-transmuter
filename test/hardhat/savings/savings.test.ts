import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { Signer } from 'ethers';
import { formatBytes32String, parseEther, parseUnits } from 'ethers/lib/utils';
import hre, { ethers } from 'hardhat';

import {
  MockAccessControlManager,
  MockAccessControlManager__factory,
  MockTokenPermit,
  MockTokenPermit__factory,
  Savings,
  Savings__factory,
} from '../../../typechain';
import { parseAmount } from '../../../utils/bignumber';
import { expect } from '../utils/chai-setup';
import { inReceipt } from '../utils/expectEvent';
import { deployUpgradeable, expectApprox, increaseTime, latestTime, MAX_UINT256, ZERO_ADDRESS } from '../utils/helpers';

describe('Savings', () => {
  let deployer: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let charlie: SignerWithAddress;

  let savings: Savings;
  let acm: MockAccessControlManager;
  let governor: string;
  let agEUR: MockTokenPermit;
  const yearlyRate = 1.1;
  const ratePerSecond = yearlyRate ** (1 / (365 * 24 * 3600)) - 1;
  const rate = parseUnits(ratePerSecond.toFixed(27), 27);

  const impersonatedSigners: { [key: string]: Signer } = {};

  before(async () => {
    [deployer, alice, bob, charlie] = await ethers.getSigners();
    // add any addresses you want to impersonate here
    governor = '0xdC4e6DFe07EFCa50a197DF15D9200883eF4Eb1c8';
    const impersonatedAddresses = [governor];

    for (const address of impersonatedAddresses) {
      await hre.network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [address],
      });
      await hre.network.provider.send('hardhat_setBalance', [address, '0x10000000000000000000000000000']);
      impersonatedSigners[address] = await ethers.getSigner(address);
    }
  });

  beforeEach(async () => {
    savings = (await deployUpgradeable(new Savings__factory(deployer))) as Savings;
    acm = (await new MockAccessControlManager__factory(deployer).deploy()) as MockAccessControlManager;
    agEUR = (await new MockTokenPermit__factory(deployer).deploy('agEUR', 'agEUR', 18)) as MockTokenPermit;
    await acm.toggleGovernor(governor);
    await acm.toggleGuardian(governor);
    await agEUR.connect(alice).approve(savings.address, MAX_UINT256);
    await agEUR.connect(bob).approve(savings.address, MAX_UINT256);
    await agEUR.mint(alice.address, parseEther('1000'));
    await agEUR.mint(bob.address, parseEther('1000'));
    await savings.connect(alice).initialize(acm.address, agEUR.address, 'Angle Euro Savings Contract', 'xagEUR', 1);
  });

  describe('initializer', () => {
    it('success - initialization', async () => {
      expect(await savings.accessControlManager()).to.be.equal(acm.address);
      expect(await savings.name()).to.be.equal('Angle Euro Savings Contract');
      expect(await savings.symbol()).to.be.equal('xagEUR');
      expect(await savings.asset()).to.be.equal(agEUR.address);
      expect(await savings.balanceOf(savings.address)).to.be.equal(parseEther('1'));
      expect(await agEUR.balanceOf(savings.address)).to.be.equal(parseEther('1'));
      await expect(
        savings.initialize(ZERO_ADDRESS, agEUR.address, 'Angle Euro Savings Contract', 'xagEUR', 1),
      ).to.be.revertedWith('AlreadyInitialized');
    });
    it('reverts - ZeroAddress', async () => {
      const savingsRevert = (await deployUpgradeable(new Savings__factory(deployer))) as Savings;
      await expect(
        savingsRevert.initialize(ZERO_ADDRESS, agEUR.address, 'Angle Euro Savings Contract', 'xagEUR', 1),
      ).to.be.revertedWith('ZeroAddress');
    });
  });
  describe('setRate', () => {
    it('success - rate set', async () => {
      const receipt = await (await savings.connect(impersonatedSigners[governor]).setRate(rate)).wait();
      inReceipt(receipt, 'RateUpdated', {
        newRate: rate,
      });
      expect(await savings.rate()).to.be.equal(rate);
      expectApprox(await savings.estimatedAPR(), parseEther('0.1'), 0.1);
      expect(await savings.lastUpdate()).to.be.equal(await latestTime());
      const receipt2 = await (await savings.connect(impersonatedSigners[governor]).setRate(rate.mul(2))).wait();
      inReceipt(receipt2, 'RateUpdated', {
        newRate: rate.mul(2),
      });
      expect(await savings.rate()).to.be.equal(rate.mul(2));
      expect(await savings.lastUpdate()).to.be.equal(await latestTime());
    });
    it('reverts - not governor', async () => {
      await expect(savings.setRate(parseEther('1'))).to.be.revertedWith('NotGovernor');
    });
  });
  describe('togglePause', () => {
    it('success - paused and unpaused', async () => {
      const receipt = await (await savings.connect(impersonatedSigners[governor]).togglePause()).wait();
      inReceipt(receipt, 'ToggledPause', {
        pauseStatus: 1,
      });
      expect(await savings.paused()).to.be.equal(1);
      const receipt2 = await (await savings.connect(impersonatedSigners[governor]).togglePause()).wait();
      inReceipt(receipt2, 'ToggledPause', {
        pauseStatus: 0,
      });
      expect(await savings.paused()).to.be.equal(0);
      await savings.connect(impersonatedSigners[governor]).togglePause();
      await expect(savings.connect(alice).deposit(parseEther('1'), alice.address)).to.be.revertedWith('Paused');
      await expect(savings.connect(alice).mint(parseEther('1'), alice.address)).to.be.revertedWith('Paused');
      await expect(savings.connect(alice).withdraw(parseEther('1'), alice.address, alice.address)).to.be.revertedWith(
        'Paused',
      );
      await expect(savings.connect(alice).redeem(parseEther('1'), alice.address, alice.address)).to.be.revertedWith(
        'Paused',
      );
    });
    it('reverts - not governor or guardian', async () => {
      await expect(savings.togglePause()).to.be.revertedWith('NotGovernorOrGuardian');
    });
  });
  describe('computeUpdatedAssets', () => {
    it('success - value changed', async () => {
      expect(await savings.computeUpdatedAssets(parseEther('100'), 24 * 3600 * 265)).to.be.equal(parseEther('100'));
      await savings.connect(impersonatedSigners[governor]).setRate(rate);
      expect(await savings.computeUpdatedAssets(1, 0)).to.be.equal(1);
      expect(await savings.computeUpdatedAssets(0, 1)).to.be.equal(0);
      expectApprox(await savings.computeUpdatedAssets(parseEther('1'), 3600), parseEther('1.00001088'), 0.1);
      expectApprox(await savings.computeUpdatedAssets(parseEther('1'), 3600 * 24), parseEther('1.000261157877'), 0.1);
      expectApprox(await savings.computeUpdatedAssets(parseEther('1'), 3600 * 24 * 30), parseEther('1.00786447'), 0.1);
      expectApprox(await savings.computeUpdatedAssets(parseEther('1'), 3600 * 24 * 365), parseEther('1.1'), 0.1);
      expectApprox(
        await savings.computeUpdatedAssets(parseEther('1'), 3600 * 24 * 365 * 10),
        parseEther('2.5536647'),
        0.1,
      );
    });
  });
  describe('totalAssets', () => {
    it('success - value changed', async () => {
      expect(await savings.totalAssets()).to.be.equal(parseEther('1'));
      await savings.connect(impersonatedSigners[governor]).setRate(rate);
      await increaseTime(3600 * 24 * 365);
      expect(await agEUR.balanceOf(savings.address)).to.be.equal(parseEther('1'));
      expectApprox(await savings.totalAssets(), parseEther('1.1'), 0.1);
      // Now if we set a new rate after a year it is going to accrue
      const receipt = await (await savings.connect(impersonatedSigners[governor]).setRate(rate)).wait();
      const delta = (await savings.totalAssets()).sub(parseEther('1'));
      expect(await agEUR.balanceOf(savings.address)).to.be.equal(await savings.totalAssets());
      inReceipt(receipt, 'Accrued', {
        interest: delta,
      });
      expect(await savings.lastUpdate()).to.be.equal(await latestTime());
    });
  });
  describe('deposit', () => {
    it('success - value changed', async () => {
      await savings.connect(impersonatedSigners[governor]).setRate(rate);
      await increaseTime(3600 * 24 * 365);
      // There is 1.1 assets and 1 share so it'll give -> x / 1.1 shares if you deposit x
      const receipt = await (await savings.connect(alice).deposit(parseEther('10'), bob.address)).wait();
      const sharesMinted = await savings.balanceOf(bob.address);
      expectApprox(sharesMinted, parseEther('9.09090'), 0.1);
      expect(await savings.totalSupply()).to.be.equal(sharesMinted.add(parseEther('1')));
      expect(await savings.lastUpdate()).to.be.equal(await latestTime());
      const newAssets = await savings.totalAssets();
      expectApprox(newAssets, parseEther('11.1'), 0.1);
      const delta = newAssets.sub(parseEther('11'));

      inReceipt(receipt, 'Deposit', {
        caller: alice.address,
        owner: bob.address,
        assets: parseEther('10'),
        shares: sharesMinted,
      });

      inReceipt(receipt, 'Accrued', {
        interest: delta,
      });

      await increaseTime(3600 * 24 * 365);
      // There are 11.1 * 1.1 = 12.21 assets and 9.09 shares so it'll give -> x * 10.0909 / 12.21 if you deposit x
      const receipt2 = await (await savings.connect(alice).deposit(parseEther('5'), charlie.address)).wait();
      const sharesMinted2 = await savings.balanceOf(charlie.address);
      expectApprox(sharesMinted2, parseEther('4.13222'), 0.1);
      expect(await savings.totalSupply()).to.be.equal(sharesMinted.add(parseEther('1')).add(sharesMinted2));
      expect(await savings.lastUpdate()).to.be.equal(await latestTime());
      expectApprox(await savings.totalAssets(), parseEther('17.21'), 0.1);
      const delta2 = (await savings.totalAssets()).sub(newAssets.add(parseEther('5')));
      inReceipt(receipt2, 'Deposit', {
        caller: alice.address,
        owner: charlie.address,
        assets: parseEther('5'),
        shares: sharesMinted2,
      });

      inReceipt(receipt2, 'Accrued', {
        interest: delta2,
      });
    });
  });
  describe('mint', () => {
    it('success - value changed', async () => {
      await savings.connect(impersonatedSigners[governor]).setRate(rate);
      await increaseTime(3600 * 24 * 365);
      // There is 1.1 assets and 1 share so to mint x shares you need to bring -> 1.1*x of assets
      const aliceBalance = await agEUR.balanceOf(alice.address);
      const receipt = await (await savings.connect(alice).mint(parseEther('10'), bob.address)).wait();
      expect(await savings.balanceOf(bob.address)).to.be.equal(parseEther('10'));
      expect(await savings.totalSupply()).to.be.equal(parseEther('11'));
      expect(await savings.lastUpdate()).to.be.equal(await latestTime());
      const newAssets = await savings.totalAssets();
      // There should be 11+1.1 = 12.2
      expectApprox(newAssets, parseEther('12.1'), 0.1);
      const aliceNewBalance = await agEUR.balanceOf(alice.address);
      expectApprox(aliceNewBalance, aliceBalance.sub(parseEther('11')), 0.1);
      const delta = newAssets.sub(parseEther('1')).sub(aliceBalance.sub(aliceNewBalance));
      inReceipt(receipt, 'Deposit', {
        caller: alice.address,
        owner: bob.address,
        assets: aliceBalance.sub(aliceNewBalance),
        shares: parseEther('10'),
      });

      inReceipt(receipt, 'Accrued', {
        interest: delta,
      });

      await increaseTime(3600 * 24 * 365);
      // There are 12.1*1.1 = 13.31 assets and 11 shares so it'll take -> x*13.31/11 to mint x
      const receipt2 = await (await savings.connect(alice).mint(parseEther('5'), charlie.address)).wait();
      expect(await savings.balanceOf(charlie.address)).to.be.equal(parseEther('5'));
      expect(await savings.totalSupply()).to.be.equal(parseEther('16'));
      expect(await savings.lastUpdate()).to.be.equal(await latestTime());
      const newAssets2 = await savings.totalAssets();
      expectApprox(newAssets2, parseEther('19.36'), 0.1);
      const aliceNewBalance2 = await agEUR.balanceOf(alice.address);
      expectApprox(aliceNewBalance2, aliceNewBalance.sub(parseEther('6.05')), 0.1);
      const delta2 = newAssets2.sub(newAssets).sub(aliceNewBalance.sub(aliceNewBalance2));
      inReceipt(receipt2, 'Deposit', {
        caller: alice.address,
        owner: charlie.address,
        assets: aliceNewBalance.sub(aliceNewBalance2),
        shares: parseEther('5'),
      });

      inReceipt(receipt2, 'Accrued', {
        interest: delta2,
      });
    });
  });
  /*
TODO:
- test mint, withdraw, redeem, convertToShares and convertToAssets, previewMint, previewRedeem and stuff
- test if redemption after a year effectively gives you your yield
- accrual
- check decimals
  */

  /*
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
*/
});
