import '@nomiclabs/hardhat-ethers';
import { task } from 'hardhat/config';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { getAddrs, getEnvFromNetworkName } from '../helpers/utils';
import {
  LZGatedProxy__factory,
  LensHub__factory,
} from '../../typechain';
import {
  LZ_CONFIG,
  SANDBOX_USER_PROFILE_ID,
  TOKEN_CONTRACT,
  TOKEN_THRESHOLD,
  TOKEN_CHAIN_ID,
} from './config';
import getFollowWithSigParts from '../helpers/getFollowWithSigParts';
import ILayerZeroMessagingLibrary from '../helpers/abi/ILayerZeroMessagingLibrary.json';

// derived from `npx hardhat estimate-fee-follow` and accounting for potential follow nft deployment
const ESTIMATED_FOLLOW_FEE_GWEI = '2500';
const ESTIMATED_GAS_REMOTE = 500_000 // based on some tests...
const GAS_LIMIT = 300_000; // based on some tests...

export let runtimeHRE: HardhatRuntimeEnvironment;

// the same can be done for LZGatedCollectModule + LZGatedReferenceModule, just need to setup the correct sig data
task('relay-follow-with-sig', 'try to folllow a profile which has set their follow module to LZGatedFollowModule')
  .addParam('hub')
  .addOptionalParam('sandbox')
  .setAction(async ({ hub, sandbox }, hre) => {
  runtimeHRE = hre;
  const ethers = hre.ethers;
  const networkName = hre.network.name;
  const [deployer] = await ethers.getSigners();

  if (!LZ_CONFIG[networkName]) throw new Error('invalid network');

  const destination = LZ_CONFIG[networkName].remote;
  const env = getEnvFromNetworkName(destination, sandbox);
  const contracts = getAddrs()[env];

  const rpc = destination === 'mumbai'
    ? process.env.MUMBAI_RPC_URL
    : process.env.POLYGON_RPC_URL;
  const provider = new ethers.providers.JsonRpcProvider(rpc);
  const lensHub = await LensHub__factory.connect(hub, provider);
  const lzGatedProxy = await LZGatedProxy__factory.connect(contracts.lz[networkName].LZGatedProxy, deployer);

  const followerAddress = await deployer.getAddress(); // practice self-care and follow yourself :shrug:
  const nonce = (await lensHub.sigNonces(followerAddress)).toNumber();
  const { chainId } = await provider.getNetwork();

  const followWithSigData = await getFollowWithSigParts({
    chainId,
    wallet: deployer,
    lensHubAddress: lensHub.address,
    profileIds: [SANDBOX_USER_PROFILE_ID],
    datas: [[]],
    nonce,
    deadline: ethers.constants.MaxUint256.toHexString(),
    follower: followerAddress,
  });

  console.log(`followWithSigData:`);
  console.log(JSON.stringify(followWithSigData,null,2));

  console.log('lzGatedProxy.relayFollowWithSig()');
  const tx = await lzGatedProxy.relayFollowWithSig(
    TOKEN_CONTRACT,
    TOKEN_THRESHOLD,
    ESTIMATED_GAS_REMOTE,
    followWithSigData,
    { value: ethers.utils.parseUnits(ESTIMATED_FOLLOW_FEE_GWEI, 'gwei'), gasLimit: GAS_LIMIT }
  );
  console.log(`tx: ${tx.hash}`);
  await tx.wait();

  // assuming `followerAddress` has a balance of `TOKEN_CONTRACT` >= `TOKEN_THRESHOLD` - likely good
  // check the latext tx against the deployed LZGatedFollowModule
});
