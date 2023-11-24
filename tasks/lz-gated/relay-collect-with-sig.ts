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
  SANDBOX_GATED_COLLECT_PUB_ID,
} from './config';
import getCollectWithSigParts from '../helpers/getCollectWithSigParts';

const ESTIMATED_GAS_REMOTE = 600_000 // based on some tests...
const GAS_LIMIT = 300_000; // based on some tests...

export let runtimeHRE: HardhatRuntimeEnvironment;

task('relay-collect-with-sig', 'try to collect a post which has the collect module set to LZGatedCollectModule')
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

  const collector = await deployer.getAddress(); // practice self-care and collect your own posts :shrug:
  const nonce = (await lensHub.sigNonces(collector)).toNumber();
  const { chainId } = await provider.getNetwork();

  const collectWithSigData = await getCollectWithSigParts({
    chainId,
    wallet: deployer,
    lensHubAddress: lensHub.address,
    profileId: SANDBOX_USER_PROFILE_ID,
    pubId: SANDBOX_GATED_COLLECT_PUB_ID,
    data: [],
    nonce,
    deadline: ethers.constants.MaxUint256.toHexString(),
    collector,
  });

  console.log(`collectWithSigData:`);
  console.log(JSON.stringify(collectWithSigData,null,2));

  const fees = await lzGatedProxy.estimateFeesCollect(
    TOKEN_CONTRACT,
    TOKEN_THRESHOLD,
    ESTIMATED_GAS_REMOTE,
    collectWithSigData,
  );
  console.log(
    `nativeFee in ${['mumbai', 'polygon'].includes(networkName) ? 'matic' : 'ether'}`, ethers.utils.formatEther(fees[0])
  );

  console.log('lzGatedProxy.relayCollectWithSig()');
  const tx = await lzGatedProxy.relayCollectWithSig(
    TOKEN_CONTRACT,
    TOKEN_THRESHOLD,
    ESTIMATED_GAS_REMOTE,
    collectWithSigData,
    { value: fees[0], gasLimit: GAS_LIMIT }
  );
  console.log(`tx: ${tx.hash}`);
  await tx.wait();

  // assuming `collector` has a balance of `TOKEN_CONTRACT` >= `TOKEN_THRESHOLD` - likely good
  // check the latext tx against the deployed LZGatedCollectModule
});
