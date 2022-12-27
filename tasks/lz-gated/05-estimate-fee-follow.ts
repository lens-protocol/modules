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
import getFollowWithSigParts from '../helpers/getFollowWithSigParts';
import ILayerZeroMessagingLibrary from '../helpers/abi/ILayerZeroMessagingLibrary.json';

export let runtimeHRE: HardhatRuntimeEnvironment;

// the same can be done for LZGatedCollectModule + LZGatedReferenceModule, just need to setup the correct sig data
task('estimate-fee-follow', 'estimate the fee of relaying the followSig from our LZGatedProxy to LZGatedFollowModule')
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
  const endpoint = new ethers.Contract(LZ_CONFIG[networkName].endpoint, ILayerZeroMessagingLibrary.abi, deployer.provider);

  const followerAddress = await deployer.getAddress();
  const nonce = (await lensHub.sigNonces(followerAddress)).toNumber();
  const { chainId } = await provider.getNetwork();

  const followWithSigData = await getFollowWithSigParts({
    chainId,
    wallet: deployer,
    lensHubAddress: lensHub.address,
    profileIds: [ethers.BigNumber.from(SANDBOX_USER_PROFILE_ID)],
    datas: [[]],
    nonce,
    deadline: ethers.constants.MaxUint256.toHexString(),
    follower: followerAddress,
  });

  // example payload
  const followWithSigType = 'tuple(address follower, uint256[] profileIds, bytes[] datas, tuple(uint8 v, bytes32 r, bytes32 s, uint256 deadline) sig) followSig';
  const types = ['address', 'uint256', followWithSigType];
  const payload = ethers.utils.defaultAbiCoder.encode(
    types,
    [TOKEN_CONTRACT, TOKEN_THRESHOLD, followWithSigData]
  );

  console.log(`networkName: ${networkName}`);
  console.log(`endpoint.address: ${endpoint.address}`);

  const ESTIMATED_GAS_REMOTE = 500_000 // based on some tests...
  console.log(`ESTIMATED_GAS_REMOTE: ${ESTIMATED_GAS_REMOTE}`);
  const adapterParams = ethers.utils.solidityPack(
    ['uint16', 'uint256'],
    [1, ESTIMATED_GAS_REMOTE]
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
