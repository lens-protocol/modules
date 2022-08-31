import '@nomiclabs/hardhat-ethers';
import { task } from 'hardhat/config';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { deployWithVerify } from '../../helpers/utils';
import { AuctionCollectModule__factory, LensHub__factory } from '../../../typechain';

export let runtimeHRE: HardhatRuntimeEnvironment;

task('deploy-auction-collect-module', 'Deploys, verifies and whitelists the auction collect module')
  .addParam('hub')
  .addParam('globals')
  .setAction(async ({ hub, globals }, hre) => {
    runtimeHRE = hre;
    const ethers = hre.ethers;
    const accounts = await ethers.getSigners();
    const deployer = accounts[0];
    const governance = accounts[1];

    console.log('\n\n- - - - - - - - Deploying auction collect module\n\n');
    const auctionCollectModule = await deployWithVerify(
      new AuctionCollectModule__factory(deployer).deploy(hub, globals),
      [hub, globals],
      'contracts/collect/AuctionCollectModule.sol:AuctionCollectModule'
    );

    console.log('\n\n- - - - - - - - Whitelisting auction collect module\n\n');
    await LensHub__factory.connect(hub, governance).whitelistCollectModule(
      auctionCollectModule.address,
      true
    );
  });
