import '@nomiclabs/hardhat-ethers';
import { task } from 'hardhat/config';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { deployWithVerify } from '../../helpers/utils';
import { StepwiseCollectModule__factory, LensHub__factory } from '../../../typechain';

export let runtimeHRE: HardhatRuntimeEnvironment;

task(
  'deploy-stepwise-collect-module',
  'Deploys, verifies and whitelists the stepwise collect module'
)
  .addParam('hub')
  .addParam('globals')
  .setAction(async ({ hub, globals }, hre) => {
    runtimeHRE = hre;
    const ethers = hre.ethers;
    const accounts = await ethers.getSigners();
    const deployer = accounts[0];
    const governance = accounts[1];

    console.log('\n\n- - - - - - - - Deploying stepwise fee collect module\n\n');
    const stepwiseCollectModule = await deployWithVerify(
      new StepwiseCollectModule__factory(deployer).deploy(hub, globals),
      [hub, globals],
      'contracts/collect/StepwiseCollectModule.sol:StepwiseCollectModule'
    );

    if (process.env.HARDHAT_NETWORK !== 'matic') {
      console.log('\n\n- - - - - - - - Whitelisting stepwise fee collect module\n\n');
      await LensHub__factory.connect(hub, governance).whitelistCollectModule(
        stepwiseCollectModule.address,
        true
      );
    }
  });
