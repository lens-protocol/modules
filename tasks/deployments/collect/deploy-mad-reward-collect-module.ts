import '@nomiclabs/hardhat-ethers';
import { task } from 'hardhat/config';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import {
  deployWithVerify,
  getAddrs,
  saveAddrs,
  waitForTx,
  getEnvFromNetworkName,
} from '../../helpers/utils';
import {
  MadRewardCollectModule__factory,
  LensHub__factory,
} from '../../../typechain';

export let runtimeHRE: HardhatRuntimeEnvironment;

task('deploy-mad-reward-collect-module', 'Deploys, verifies and whitelists MadRewardCollectModule')
  .addParam('hub')
  .addOptionalParam('mockSandboxGovernance')
  .setAction(async ({ hub, mockSandboxGovernance }, hre) => {
  runtimeHRE = hre;
  const ethers = hre.ethers;
  const networkName = hre.network.name;
  const [deployer, governance] = await ethers.getSigners();

  const json = getAddrs();
  const env = getEnvFromNetworkName(networkName, mockSandboxGovernance);

  if (!json[env].MadSBT) throw new Error('Missing entry for MadSBT in addresses.json');

  console.log('\n\n- - - - - - - - Deploying MadRewardCollectModule \n\n');
  console.log(`- - - - - - using MadSBT at ${json[env].MadSBT}`);

  const collectModule = await deployWithVerify(
    new MadRewardCollectModule__factory(deployer).deploy(hub, json[env].MadSBT),
    [hub, json[env].MadSBT],
    'contracts/collect/MadRewardCollectModule.sol:MadRewardCollectModule'
  );

  json[env]['MadRewardCollectModule'] = collectModule.address;
  saveAddrs(json);

  if (networkName === 'mumbai') {
    const whitelistingContractAddress = mockSandboxGovernance || hub;
    const whitelistingSigner = mockSandboxGovernance ? deployer : governance;
    const whitelistingContract = await LensHub__factory.connect(whitelistingContractAddress, whitelistingSigner);

    console.log('\n\n- - - - - - - - Whitelisting MadRewardCollectModule\n\n');
    await waitForTx(whitelistingContract.whitelistCollectModule(collectModule.address, true));
  }
});
