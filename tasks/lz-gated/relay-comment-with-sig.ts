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
  SANDBOX_GATED_REFERENCE_PUB_ID,
  SAMPLE_CONTENT_URI,
} from './config';
import getCommentWithSigParts from '../helpers/getCommentWithSigParts';

const ESTIMATED_GAS_REMOTE = 400_000 // based on some tests...
const GAS_LIMIT = 400_000; // based on some tests...

export let runtimeHRE: HardhatRuntimeEnvironment;

task('relay-comment-with-sig', 'try to comment on a post which has the reference module set to LZGatedReferenceModule')
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

  const sender = await deployer.getAddress(); // practice self-care and mirror your own posts :shrug:
  const nonce = (await lensHub.sigNonces(sender)).toNumber();
  const { chainId } = await provider.getNetwork();

  const collectModuleInitData = ethers.utils.defaultAbiCoder.encode(
    ['bool'],
    [false]
  );

  const commentWithSigData = await getCommentWithSigParts({
    chainId,
    wallet: deployer,
    lensHubAddress: lensHub.address,
    profileId: SANDBOX_USER_PROFILE_ID,
    contentURI: SAMPLE_CONTENT_URI,
    profileIdPointed: SANDBOX_USER_PROFILE_ID,
    pubIdPointed: SANDBOX_GATED_REFERENCE_PUB_ID,
    referenceModuleData: [],
    collectModule: contracts.FreeCollectModule,
    collectModuleInitData,
    referenceModule: ethers.constants.AddressZero,
    referenceModuleInitData: [],
    nonce,
    deadline: ethers.constants.MaxUint256.toHexString(),
  });

  console.log(`commentWithSigData:`);
  console.log(JSON.stringify(commentWithSigData,null,2));

  const fees = await lzGatedProxy.estimateFeesComment(
    sender,
    TOKEN_CONTRACT,
    TOKEN_THRESHOLD,
    ESTIMATED_GAS_REMOTE,
    commentWithSigData,
  );
  console.log(
    `nativeFee in ${['mumbai', 'polygon'].includes(networkName) ? 'matic' : 'ether'}`, ethers.utils.formatEther(fees[0])
  );

  console.log('lzGatedProxy.relayCommentWithSig()');
  const tx = await lzGatedProxy.relayCommentWithSig(
    sender,
    TOKEN_CONTRACT,
    TOKEN_THRESHOLD,
    ESTIMATED_GAS_REMOTE,
    commentWithSigData,
    { value: fees[0], gasLimit: GAS_LIMIT }
  );
  console.log(`tx: ${tx.hash}`);
  await tx.wait();

  // assuming `sender` has a balance of `TOKEN_CONTRACT` >= `TOKEN_THRESHOLD` - likely good
  // check the latext tx against the deployed LZGatedReferenceModule
});
