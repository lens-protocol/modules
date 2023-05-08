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
  TargetedCampaignReferenceModule__factory,
  LensHub__factory,
} from '../../../typechain';

export let runtimeHRE: HardhatRuntimeEnvironment;

task('deploy-targeted-campaign-reference-module', 'Deploys, verifies and whitelists TargetedCampaignReferenceModule')
  .addParam('hub')
  .addParam('globals')
  .addOptionalParam('mockSandboxGovernance')
  .setAction(async ({ hub, globals, mockSandboxGovernance }, hre) => {
  runtimeHRE = hre;
  const ethers = hre.ethers;
  const networkName = hre.network.name;
  const [deployer, governance] = await ethers.getSigners();

  const json = getAddrs();
  const env = getEnvFromNetworkName(networkName, mockSandboxGovernance);

  console.log('\n\n- - - - - - - - Deploying TargetedCampaignReferenceModule \n\n');

  const referenceModule = await deployWithVerify(
    new TargetedCampaignReferenceModule__factory(deployer).deploy(hub, globals, 0, 0),
    [hub, globals, 0, 0],
    'contracts/reference/TargetedCampaignReferenceModule.sol:TargetedCampaignReferenceModule'
  );

  json[env]['TargetedCampaignReferenceModule'] = referenceModule.address;
  saveAddrs(json);

  if (networkName === 'mumbai') {
    const whitelistingContractAddress = mockSandboxGovernance || hub;
    const whitelistingSigner = mockSandboxGovernance ? deployer : governance;
    const whitelistingContract = await LensHub__factory.connect(whitelistingContractAddress, whitelistingSigner);

    console.log('\n\n- - - - - - - - Whitelisting TargetedCampaignReferenceModule\n\n');
    await waitForTx(whitelistingContract.whitelistReferenceModule(referenceModule.address, true));
  }
});
