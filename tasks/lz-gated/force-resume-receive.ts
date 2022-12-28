import '@nomiclabs/hardhat-ethers';
import { task } from 'hardhat/config';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { getAddrs, getEnvFromNetworkName } from '../helpers/utils';
import {
  LZGatedFollowModule__factory,
  LZGatedCollectModule__factory,
  LZGatedReferenceModule__factory,
} from '../../typechain';
import { LZ_CONFIG } from './config';

const FACTORIES = {
  LZGatedFollowtModule: LZGatedFollowModule__factory,
  LZGatedCollectModule: LZGatedCollectModule__factory,
  LZGatedReferenceModule: LZGatedReferenceModule__factory
};

// worst case, in the case of a revert
task('force-resume-receive', 'force our lz contract to receive new messages after a revert')
  .addOptionalParam('sandbox')
  .setAction(async ({ sandbox }, hre) => {
  const ethers = hre.ethers;
  const networkName = hre.network.name;
  const [deployer] = await ethers.getSigners();

  if (!LZ_CONFIG[networkName]) throw new Error('invalid network');

  const contracts = getAddrs()[getEnvFromNetworkName(networkName, sandbox)];

  const toResumeChain = 'goerli';
  const toResume = 'LZGatedCollectModule';
  const contract = FACTORIES[toResume].connect(contracts[toResume], deployer);

  console.log(`force resuming ${toResume} for LZGatedProxy at ${toResumeChain}`);
  const trustedRemote = ethers.utils.solidityPack(
    ['address','address'],
    [contracts.lz[toResumeChain].LZGatedProxy, contract.address]
  );
  const tx = await contract.forceResumeReceive(LZ_CONFIG[toResumeChain].chainId, trustedRemote, { gasLimit: 2100000 });
  console.log(`tx: ${tx.hash}`);
  await tx.wait();

  console.log('done!');
});
