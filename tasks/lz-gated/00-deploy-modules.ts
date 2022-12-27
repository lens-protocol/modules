import '@nomiclabs/hardhat-ethers';
import { task } from 'hardhat/config';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import {
  deployWithVerify,
  getAddrs,
  saveAddrs,
  waitForTx,
  getEnvFromNetworkName,
} from '../helpers/utils';
import {
  LZGatedFollowModule__factory,
  LZGatedCollectModule__factory,
  LZGatedReferenceModule__factory,
  LensHub__factory,
} from '../../typechain';
import { LZ_CONFIG } from './config';

export let runtimeHRE: HardhatRuntimeEnvironment;

task('deploy-modules', 'Deploys, verifies and whitelists LZGated* modules')
  .addParam('hub')
  .addOptionalParam('mockSandboxGovernance')
  .setAction(async ({ hub, mockSandboxGovernance }, hre) => {
  runtimeHRE = hre;
  const ethers = hre.ethers;
  const networkName = hre.network.name;
  const [deployer, governance] = await ethers.getSigners();

  if (!LZ_CONFIG[networkName]) throw new Error(`invalid network: ${networkName}`);

  console.log('\n\n- - - - - - - - Deploying LZGatedFollowModule \n\n');
  const followModule = await deployWithVerify(
    new LZGatedFollowModule__factory(deployer).deploy(hub, LZ_CONFIG[networkName].endpoint, [], []),
    [hub, LZ_CONFIG[networkName].endpoint, [], []],
    'contracts/follow/LZGatedFollowModule.sol:LZGatedFollowModule'
  );

  console.log('\n\n- - - - - - - - Deploying LZGatedReferenceModule \n\n');
  const referenceModule = await deployWithVerify(
    new LZGatedReferenceModule__factory(deployer).deploy(hub, LZ_CONFIG[networkName].endpoint, [], []),
    [hub, LZ_CONFIG[networkName].endpoint, [], []],
    'contracts/reference/LZGatedReferenceModule.sol:LZGatedReferenceModule'
  );

  console.log('\n\n- - - - - - - - Deploying LZGatedCollectModule \n\n');
  const collectModule = await deployWithVerify(
    new LZGatedCollectModule__factory(deployer).deploy(hub, LZ_CONFIG[networkName].endpoint, [], []),
    [hub, LZ_CONFIG[networkName].endpoint, [], []],
    'contracts/collect/LZGatedCollectModule.sol:LZGatedCollectModule'
  );

  const env = getEnvFromNetworkName(networkName, mockSandboxGovernance);

  const json = getAddrs();
  json[env]['LZGatedFollowModule'] = followModule.address;
  json[env]['LZGatedReferenceModule'] = referenceModule.address;
  json[env]['LZGatedCollectModule'] = collectModule.address;
  saveAddrs(json);

  if (networkName === 'mumbai') {
    const whitelistingContractAddress = mockSandboxGovernance || hub;
    const whitelistingSigner = mockSandboxGovernance ? deployer : governance; // `governance` never has funds :shrug:
    const whitelistingContract = await LensHub__factory.connect(whitelistingContractAddress, whitelistingSigner);

    console.log('\n\n- - - - - - - - Whitelisting LZGatedFollowModule\n\n');
    await waitForTx(whitelistingContract.whitelistFollowModule(followModule.address, true));

    console.log('\n\n- - - - - - - - Whitelisting LZGatedReferenceModule\n\n');
    await waitForTx(whitelistingContract.whitelistReferenceModule(referenceModule.address, true));

    console.log('\n\n- - - - - - - - Whitelisting LZGatedCollectModule\n\n');
    await waitForTx(whitelistingContract.whitelistCollectModule(collectModule.address, true));
  }
});
