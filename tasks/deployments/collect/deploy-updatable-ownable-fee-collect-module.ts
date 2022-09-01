import '@nomiclabs/hardhat-ethers';
import { task } from 'hardhat/config';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { deployWithVerify } from '../../helpers/utils';
import { UpdatableOwnableFeeCollectModule__factory, LensHub__factory } from '../../../typechain';

export let runtimeHRE: HardhatRuntimeEnvironment;

task(
  'deploy-updatable-ownable-fee-collect-module',
  'Deploys, verifies and whitelists the updatable ownable fee collect module'
)
  .addParam('hub')
  .addParam('globals')
  .setAction(async ({ hub, globals }, hre) => {
    runtimeHRE = hre;
    const ethers = hre.ethers;
    const accounts = await ethers.getSigners();
    const deployer = accounts[0];
    const governance = accounts[1];

    console.log('\n\n- - - - - - - - Deploying updatable ownable fee collect module\n\n');
    const updatableOwnableFeeCollectModule = await deployWithVerify(
      new UpdatableOwnableFeeCollectModule__factory(deployer).deploy(hub, globals),
      [hub, globals],
      'contracts/collect/UpdatableOwnableFeeCollectModule.sol:UpdatableOwnableFeeCollectModule'
    );

    console.log('\n\n- - - - - - - - Whitelisting updatable ownable fee collect module\n\n');
    await LensHub__factory.connect(hub, governance).whitelistCollectModule(
      updatableOwnableFeeCollectModule.address,
      true
    );
  });
