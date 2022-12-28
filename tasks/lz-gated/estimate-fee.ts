import '@nomiclabs/hardhat-ethers';
import { task } from 'hardhat/config';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { getAddrs, getEnvFromNetworkName } from '../helpers/utils';
import { LensHub__factory } from '../../typechain';
import {
  LZ_CONFIG,
  SANDBOX_USER_PROFILE_ID,
  TOKEN_CONTRACT,
  TOKEN_THRESHOLD,
  TOKEN_CHAIN_ID,
  SANDBOX_GATED_COLLECT_PUB_ID,
  SANDBOX_GATED_REFERENCE_PUB_ID,
} from './config';
import getFollowWithSigParts from '../helpers/getFollowWithSigParts';
import getCollectWithSigParts from '../helpers/getCollectWithSigParts';
import getMirrorWithSigParts from '../helpers/getMirrorWithSigParts';
import ILayerZeroMessagingLibrary from '../helpers/abi/ILayerZeroMessagingLibrary.json';

export let runtimeHRE: HardhatRuntimeEnvironment;

let lensHub;
let ethers;

const _getPayloadFollow = async (wallet) => {
  console.log('generating payload for #relayFollowWithSig');

  const followerAddress = await wallet.getAddress();
  const nonce = (await lensHub.sigNonces(followerAddress)).toNumber();
  const { chainId } = await lensHub.provider.getNetwork();

  const followWithSigData = await getFollowWithSigParts({
    chainId,
    wallet,
    lensHubAddress: lensHub.address,
    profileIds: [ethers.BigNumber.from(SANDBOX_USER_PROFILE_ID)],
    datas: [[]],
    nonce,
    deadline: ethers.constants.MaxUint256.toHexString(),
    follower: followerAddress,
  });

  const followWithSigType = 'tuple(address follower, uint256[] profileIds, bytes[] datas, tuple(uint8 v, bytes32 r, bytes32 s, uint256 deadline) sig) followSig';
  const types = ['address', 'uint256', followWithSigType];

  const payload = ethers.utils.defaultAbiCoder.encode(
    types,
    [TOKEN_CONTRACT, TOKEN_THRESHOLD, followWithSigData]
  );

  // based on some tests; covers potential follow nft deployment
  const estimatedGasRemote = 500_000;

  return { payload, types, estimatedGasRemote };
};

const _getPayloadCollect = async (wallet) => {
  console.log('generating payload for #relayCollectWithSig');

  const collector = await wallet.getAddress();
  const nonce = (await lensHub.sigNonces(collector)).toNumber();
  const { chainId } = await lensHub.provider.getNetwork();

  const collectWithSigData = await getCollectWithSigParts({
    chainId,
    wallet,
    lensHubAddress: lensHub.address,
    profileId: SANDBOX_USER_PROFILE_ID,
    pubId: SANDBOX_GATED_COLLECT_PUB_ID,
    data: [],
    nonce,
    deadline: ethers.constants.MaxUint256.toHexString(),
    collector,
  });

  const collectWithSigType = 'tuple(address collector, uint256 profileId, bytes data, tuple(uint8 v, bytes32 r, bytes32 s, uint256 deadline) sig) collectSig';
  const types = ['address', 'uint256', collectWithSigType];

  const payload = ethers.utils.defaultAbiCoder.encode(
    types,
    [TOKEN_CONTRACT, TOKEN_THRESHOLD, collectWithSigData]
  );

  // based on some tests
  const estimatedGasRemote = 500_000;

  return { payload, types, estimatedGasRemote };
};

const _getPayloadMirror = async (wallet) => {
  console.log('generating payload for #relayMirrorWithSig');

  const isComment = false;
  const sender = await wallet.getAddress();
  const nonce = (await lensHub.sigNonces(sender)).toNumber();
  const { chainId } = await lensHub.provider.getNetwork();

  const mirrorWithSigData = await getMirrorWithSigParts({
    chainId,
    wallet,
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

  const mirrorWithSigType = 'tuple(uint256 profileId, uint256 profileIdPointed, uint256 pubIdPointed, bytes referenceModuleData, address referenceModule, bytes referenceModuleInitData, tuple(uint8 v, bytes32 r, bytes32 s, uint256 deadline) sig) collectSig';
  const types = ['bool', 'address', 'address', 'uint256', mirrorWithSigType];

  const payload = ethers.utils.defaultAbiCoder.encode(
    types,
    [isComment, sender, TOKEN_CONTRACT, TOKEN_THRESHOLD, mirrorWithSigData]
  );

  // based on some tests
  const estimatedGasRemote = 500_000;

  return { payload, types, estimatedGasRemote };
};

task('estimate-fee', 'estimate the fee of relaying payloads from LZGatedProxy to LZGated* modules')
  .addParam('hub')
  .addOptionalParam('sandbox')
  .setAction(async ({ hub, sandbox }, hre) => {
  runtimeHRE = hre;
  ethers = hre.ethers;
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

  lensHub = await LensHub__factory.connect(hub, provider);
  const endpoint = new ethers.Contract(LZ_CONFIG[networkName].endpoint, ILayerZeroMessagingLibrary.abi, deployer.provider);

  console.log(`networkName: ${networkName}`);
  console.log(`endpoint.address: ${endpoint.address}`);

  // generate payload for each of the modules
  // const { payload, types, estimatedGasRemote } = await _getPayloadFollow(deployer);
  // const { payload, types, estimatedGasRemote } = await _getPayloadCollect(deployer);
  const { payload, types, estimatedGasRemote } = await _getPayloadMirror(deployer);

  console.log(`estimatedGasRemote: ${estimatedGasRemote}`);
  const adapterParams = ethers.utils.solidityPack(
    ['uint16', 'uint256'],
    [1, estimatedGasRemote]
  );

  const fees = await endpoint.estimateFees(
    LZ_CONFIG[destination].chainId, // the destination LayerZero chainId
    contracts.lz[networkName].LZGatedProxy, // your contract address that calls Endpoint.send()
    payload,
    false, // _payInZRO
    adapterParams // https://layerzero.gitbook.io/docs/evm-guides/advanced/relayer-adapter-parameters
  );

  console.log('payload types: ', types);
  console.log(`fees in ${['mumbai', 'polygon'].includes(networkName) ? 'matic' : 'ether'}`, ethers.utils.formatEther(fees[0]));
});
