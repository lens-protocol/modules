import '@nomiclabs/hardhat-ethers';
import { task } from 'hardhat/config';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { deployWithVerify } from '../../helpers/utils';
import { DegreesOfSeparationReferenceModule__factory, LensHub__factory } from '../../../typechain';

export let runtimeHRE: HardhatRuntimeEnvironment;

task(
  'deploy-degrees-of-separation-reference-module',
  'Deploys, verifies and whitelists the degrees of separation reference module'
)
  .addParam('hub')
  .setAction(async ({ hub }, hre) => {
    runtimeHRE = hre;
    const ethers = hre.ethers;
    const accounts = await ethers.getSigners();
    const deployer = accounts[0];
    const governance = accounts[1];

    console.log('\n\n- - - - - - - - Deploying degrees of separation reference module\n\n');
    const degreesOfSeparationReferenceModule = await deployWithVerify(
      new DegreesOfSeparationReferenceModule__factory(deployer).deploy(hub),
      [hub],
      'contracts/reference/DegreesOfSeparationReferenceModule.sol:DegreesOfSeparationReferenceModule'
    );

    console.log('\n\n- - - - - - - - Whitelisting degrees of separation reference module\n\n');
    await LensHub__factory.connect(hub, governance).whitelistReferenceModule(
      degreesOfSeparationReferenceModule.address,
      true
    );
  });
