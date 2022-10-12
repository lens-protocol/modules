import '@nomiclabs/hardhat-ethers';
import { task } from 'hardhat/config';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { deployWithVerify } from '../../helpers/utils';
import { ERC4626FeeCollectModule__factory, LensHub__factory } from '../../../typechain';

export let runtimeHRE: HardhatRuntimeEnvironment;

task(
  'deploy-ERC4626-fee-collect-module',
  'Deploys, verifies and whitelists the ERC4626 fee collect module'
)
  .addParam('hub')
  .addParam('globals')
  .setAction(async ({ hub, globals }, hre) => {
    runtimeHRE = hre;
    const ethers = hre.ethers;
    const accounts = await ethers.getSigners();
    const deployer = accounts[0];
    const governance = accounts[1];

    console.log('\n\n- - - - - - - - Deploying ERC4626 fee collect module\n\n');
    const erc4626FeeCollectModule = await deployWithVerify(
      new ERC4626FeeCollectModule__factory(deployer).deploy(hub, globals),
      [hub, globals],
      'contracts/collect/ERC4626FeeCollectModule.sol:ERC4626FeeCollectModule'
    );

    if (process.env.HARDHAT_NETWORK !== 'matic') {
      console.log('\n\n- - - - - - - - Whitelisting ERC4626 fee collect module\n\n');
      await LensHub__factory.connect(hub, governance).whitelistCollectModule(
        erc4626FeeCollectModule.address,
        true
      );
    }
  });
