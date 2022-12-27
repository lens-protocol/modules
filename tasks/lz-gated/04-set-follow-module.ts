import '@nomiclabs/hardhat-ethers';
import { task } from 'hardhat/config';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { getAddrs, getEnvFromNetworkName } from '../helpers/utils';
import {
  LZGatedFollowModule__factory,
  LensHub__factory,
} from '../../typechain';
import {
  LZ_CONFIG,
  SANDBOX_USER_PROFILE_ID,
  TOKEN_CONTRACT,
  TOKEN_THRESHOLD,
  TOKEN_CHAIN_ID,
} from './config';

export let runtimeHRE: HardhatRuntimeEnvironment;

task('set-follow-module', 'sets the LZGatedFollowModule on our sandbox profile')
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
  const data = ethers.utils.defaultAbiCoder.encode(
    ['address', 'uint256', 'uint16'],
    [TOKEN_CONTRACT, TOKEN_THRESHOLD, TOKEN_CHAIN_ID]
  );

  // `SANDBOX_USER_PROFILE_ID` profile was created thru MockProfileCreationProxy, owned by `deployer`
  // https://docs.lens.xyz/docs/deployed-contract-addresses#sandbox-mumbai-testnet-addresses

  console.log(`\n\n- - - - - - - - Setting follow module to be LZGatedFollowModule \n\n`);
  const tx = await LensHub__factory.connect(hub, deployer).setFollowModule(
    SANDBOX_USER_PROFILE_ID,
    contracts.LZGatedFollowModule,
    data,
    { gasLimit: 210000 }
  );
  console.log(`tx: ${tx.hash}`);
  await tx.wait();

  console.log('set!');
  const res = await LZGatedFollowModule__factory
    .connect(contracts.LZGatedFollowModule, deployer)
    .gatedFollowPerProfile(SANDBOX_USER_PROFILE_ID);

  console.log(res);
});
