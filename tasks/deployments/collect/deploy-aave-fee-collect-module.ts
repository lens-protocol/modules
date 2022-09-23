import '@nomiclabs/hardhat-ethers';
import { task } from 'hardhat/config';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { deployWithVerify } from '../../helpers/utils';
import { AaveFeeCollectModule__Factory, LensHub__factory } from '../../../typechain/factories';

export let runtimeHRE: HardhatRuntimeEnvironment;

const POOL_ADDRESSES_PROVIDER_ADDRESS_MUMBAI = '0x5343b5bA672Ae99d627A1C87866b8E53F47Db2E6';
const POOL_ADDRESSES_PROVIDER_ADDRESS_POLYGON = '0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb';

task(
  'deploy-aave-fee-collect-module',
  'Deploys, verifies and whitelists the Aave fee collect module'
)
  .addParam('hub')
  .addParam('globals')
  .addParam('poolAddressProvider')
  .setAction(async ({ hub, globals, poolAddressProvider }, hre) => {
    runtimeHRE = hre;
    const ethers = hre.ethers;
    const accounts = await ethers.getSigners();
    const deployer = accounts[0];
    const governance = accounts[1];

    // Setting pool address provider if left undefined
    if (!poolAddressProvider)
      poolAddressProvider =
        process.env.HARDHAT_NETWORK == 'polygon'
          ? POOL_ADDRESSES_PROVIDER_ADDRESS_POLYGON
          : POOL_ADDRESSES_PROVIDER_ADDRESS_MUMBAI;

    console.log('\n\n- - - - - - - - Deploying Aave fee collect module\n\n');
    const aaveFeeCollectModule = await deployWithVerify(
      new AaveFeeCollectModule__Factory(deployer).deploy(hub, globals, poolAddressProvider),
      [hub, globals, poolAddressProvider],
      'contracts/collect/AaveFeeCollectModule.sol:AaveFeeCollectModule'
    );

    console.log('\n\n- - - - - - - - Whitelisting Aave fee collect module\n\n');
    // await LensHub__factory.connect(hub, governance).whitelistCollectModule(
    //   auctionCollectModule.address,
    //   true
    // );
  });
