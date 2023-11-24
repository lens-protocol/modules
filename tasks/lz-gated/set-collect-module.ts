import '@nomiclabs/hardhat-ethers';
import { task } from 'hardhat/config';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { getAddrs, getEnvFromNetworkName } from '../helpers/utils';
import {
  LZGatedCollectModule__factory,
  LensHub__factory,
} from '../../typechain';
import {
  LZ_CONFIG,
  SANDBOX_USER_PROFILE_ID,
  TOKEN_CONTRACT,
  TOKEN_THRESHOLD,
  TOKEN_CHAIN_ID,
  SAMPLE_CONTENT_URI,
} from './config';

export let runtimeHRE: HardhatRuntimeEnvironment;

task('set-collect-module', 'sets the LZGatedCollectModule on a post created by our sandbox profile')
  .addParam('hub')
  .addOptionalParam('sandbox')
  .setAction(async ({ hub, sandbox }, hre) => {
  runtimeHRE = hre;
  const ethers = hre.ethers;
  const networkName = hre.network.name;
  const [deployer] = await ethers.getSigners();

  if (!LZ_CONFIG[networkName]) throw new Error('invalid network');

  const env = getEnvFromNetworkName(networkName, sandbox);
  const contracts = getAddrs()[env];

  // tokenContract, balanceThreshold, chainId
  const collectModuleInitData = ethers.utils.defaultAbiCoder.encode(
    ['address', 'uint256', 'uint16'],
    [TOKEN_CONTRACT, TOKEN_THRESHOLD, TOKEN_CHAIN_ID]
  );

  console.log(`\n\n- - - - - - - - Creating post with collect module set to LZGatedCollectModule \n\n`);
  const lensHub = await LensHub__factory.connect(hub, deployer);
  const tx = await lensHub.post({
    profileId: SANDBOX_USER_PROFILE_ID,
    contentURI: SAMPLE_CONTENT_URI,
    collectModule: contracts.LZGatedCollectModule,
    collectModuleInitData,
    referenceModule: ethers.constants.AddressZero,
    referenceModuleInitData: [],
  }, { gasLimit: 300000 });
  console.log(`tx: ${tx.hash}`);
  await tx.wait();

  console.log('set!');
  const pubCount = await lensHub.getPubCount(SANDBOX_USER_PROFILE_ID);
  const res = await LZGatedCollectModule__factory
    .connect(contracts.LZGatedCollectModule, deployer)
    .gatedCollectDataPerPub(SANDBOX_USER_PROFILE_ID, pubCount);

  console.log(`gatedCollectDataPerPub(profileId: ${SANDBOX_USER_PROFILE_ID}, pubId: ${pubCount.toNumber()}) =>`, res);
});
