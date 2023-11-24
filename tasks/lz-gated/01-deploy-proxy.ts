import '@nomiclabs/hardhat-ethers';
import { task } from 'hardhat/config';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { deployContract, getAddrs, saveAddrs, getEnvFromNetworkName } from '../helpers/utils';
import { LZGatedProxy__factory } from '../../typechain';
import { LZ_CONFIG } from './config';

export let runtimeHRE: HardhatRuntimeEnvironment;

task('deploy-proxy', 'Deploys and whitelists LZGatedProxy against a specific env [mainnet|testnet|sandbox]')
  .addOptionalParam('sandbox')
  .setAction(async ({ sandbox }, hre) => {
  runtimeHRE = hre;
  const ethers = hre.ethers;
  const networkName = hre.network.name;
  const [deployer] = await ethers.getSigners();

  if (!LZ_CONFIG[networkName]) throw new Error(`invalid network: ${networkName}`);

  const remoteNetwork = LZ_CONFIG[networkName].remote;
  const env = getEnvFromNetworkName(remoteNetwork, sandbox);

  // modules deployed on the remote chain
  const deployedAddresses = getAddrs();
  const contracts = deployedAddresses[env];

  console.log(`\n\n- - - - - - - - Deploying LZGatedProxy on network:${networkName} against env:${env} \n\n`);

  const lzGatedProxy = await deployContract(
    new LZGatedProxy__factory(deployer).deploy(
      LZ_CONFIG[networkName].endpoint,
      LZ_CONFIG[remoteNetwork].chainId,
      contracts.LZGatedFollowModule,
      contracts.LZGatedReferenceModule,
      contracts.LZGatedCollectModule
    )
  );

  if (!contracts['lz']) contracts['lz'] = {};
  if (!contracts['lz'][networkName]) contracts['lz'][networkName] = {};

  contracts['lz'][networkName]['LZGatedProxy'] = lzGatedProxy.address;
  deployedAddresses[env] = contracts;

  saveAddrs(deployedAddresses);
});
