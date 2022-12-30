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
} from './config';
import getMirrorWithSigParts from '../helpers/getMirrorWithSigParts';

// derived from `npx hardhat estimate-fee`
const ESTIMATED_FEE_GWEI = '1200';
const ESTIMATED_GAS_REMOTE = 500_000 // based on some tests...
const GAS_LIMIT = 400_000; // based on some tests...

export let runtimeHRE: HardhatRuntimeEnvironment;

task('relay-mirror-with-sig', 'try to mirror a post which has the reference module set to LZGatedReferenceModule')
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

  const mirrorWithSigData = await getMirrorWithSigParts({
    chainId,
    wallet: deployer,
    lensHubAddress: lensHub.address,
    profileId: SANDBOX_USER_PROFILE_ID,
    profileIdPointed: SANDBOX_USER_PROFILE_ID,
    pubIdPointed: SANDBOX_GATED_REFERENCE_PUB_ID,
    referenceModuleData: [],
    referenceModule: ethers.constants.AddressZero,
    referenceModuleInitData: [],
    nonce,
    deadline: ethers.constants.MaxUint256.toHexString(),
  });

  console.log(`mirrorWithSigData:`);
  console.log(JSON.stringify(mirrorWithSigData,null,2));

  console.log('lzGatedProxy.relayMirrorWithSig()');
  const tx = await lzGatedProxy.relayMirrorWithSig(
    sender,
    TOKEN_CONTRACT,
    TOKEN_THRESHOLD,
    ESTIMATED_GAS_REMOTE,
    mirrorWithSigData,
    { value: ethers.utils.parseUnits(ESTIMATED_FEE_GWEI, 'gwei'), gasLimit: GAS_LIMIT }
  );
  console.log(`tx: ${tx.hash}`);
  await tx.wait();

  // assuming `sender` has a balance of `TOKEN_CONTRACT` >= `TOKEN_THRESHOLD` - likely good
  // check the latext tx against the deployed LZGatedReferenceModule
});
