import '@nomiclabs/hardhat-ethers';
import { task } from 'hardhat/config';
import promiseLimit from 'promise-limit';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { getAddrs, getEnvFromNetworkName } from '../helpers/utils';
import {
  LZGatedFollowModule__factory,
  LZGatedCollectModule__factory,
  LZGatedReferenceModule__factory,
} from '../../typechain';
import { LZ_CONFIG } from './config';

export let runtimeHRE: HardhatRuntimeEnvironment;

// https://layerzero.gitbook.io/docs/evm-guides/master/set-trusted-remotes
task('set-trusted-remotes', 'Sets the trusted remotes for each module / remote pair')
  .addOptionalParam('sandbox')
  .setAction(async ({ hub, sandbox }, hre) => {
  runtimeHRE = hre;
  const ethers = hre.ethers;
  const networkName = hre.network.name;
  const [deployer] = await ethers.getSigners();
  const limit = promiseLimit(1);

  if (!LZ_CONFIG[networkName]) throw new Error(`invalid network: ${networkName}`);

  const env = getEnvFromNetworkName(networkName, sandbox);
  const contracts = getAddrs()[env];

  const followModule = await LZGatedFollowModule__factory.connect(contracts.LZGatedFollowModule, deployer);
  const referenceModule = await LZGatedReferenceModule__factory.connect(contracts.LZGatedReferenceModule, deployer);
  const collectModule = await LZGatedCollectModule__factory.connect(contracts.LZGatedCollectModule, deployer);

  const { remotes } = LZ_CONFIG[networkName];

  await Promise.all(remotes.map((remote) => limit(async () => {
    const { LZGatedProxy }: { LZGatedProxy: string | undefined } = contracts.lz
      ? contracts.lz[remote]
      : {};

    if (!LZGatedProxy) throw new Error(`missing LZGatedProxy at remote: ${remote}`);

    console.log(`\n\n- - - - - - - - Setting trusted LZGatedProxy at remote: ${remote} (${LZ_CONFIG[remote].chainId}, ${LZGatedProxy}) \n\n`);

    let tx;
    let trustedRemote;
    trustedRemote = ethers.utils.solidityPack(['address','address'], [LZGatedProxy, followModule.address]);
    tx = await followModule.setTrustedRemote(LZ_CONFIG[remote].chainId, trustedRemote);
    console.log(`tx: ${tx.hash}`);
    await tx.wait();

    trustedRemote = ethers.utils.solidityPack(['address','address'], [LZGatedProxy, referenceModule.address]);
    tx = await referenceModule.setTrustedRemote(LZ_CONFIG[remote].chainId, trustedRemote);
    console.log(`tx: ${tx.hash}`);
    await tx.wait();

    trustedRemote = ethers.utils.solidityPack(['address','address'], [LZGatedProxy, collectModule.address]);
    tx = await collectModule.setTrustedRemote(LZ_CONFIG[remote].chainId, trustedRemote);
    console.log(`tx: ${tx.hash}`);
    await tx.wait();
  })));
});
