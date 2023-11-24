import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumberish, Bytes } from 'ethers';
import { ethers } from 'hardhat';
import { Domain, EIP712Domain, signData, toStringOrNumber } from '../utils';
import { domain } from '../../utils';
import { lensHub } from '../../../__setup.spec';

interface MirrorWithSigMessage {
  profileId: number | string,
  profileIdPointed: number | string,
  pubIdPointed: number | string,
  referenceModuleData: Bytes | string,
  referenceModule: string,
  referenceModuleInitData: Bytes | string,
  nonce: number | string,
  deadline: number | string,
};

const createTypedData = (message: MirrorWithSigMessage) => ({
  types: {
    EIP712Domain,
    MirrorWithSig: [
      { name: 'profileId', type: 'uint256' },
      { name: 'profileIdPointed', type: 'uint256' },
      { name: 'pubIdPointed', type: 'uint256' },
      { name: 'referenceModuleData', type: 'bytes' },
      { name: 'referenceModule', type: 'address' },
      { name: 'referenceModuleInitData', type: 'bytes' },
      { name: 'nonce', type: 'uint256' },
      { name: 'deadline', type: 'uint256' },
    ],
  },
  domain: domain(),
  primaryType: 'MirrorWithSig',
  message,
});

interface SignMirrorWithSigData {
  signer: SignerWithAddress,
  profileId: number | string,
  profileIdPointed: number | string,
  pubIdPointed: number | string,
  referenceModuleData: Bytes | string,
  referenceModule: string,
  referenceModuleInitData: Bytes | string,
  deadline?: BigNumberish
};

export default async ({
  signer,
  profileId,
  profileIdPointed,
  pubIdPointed,
  referenceModuleData,
  referenceModule,
  referenceModuleInitData,
  deadline = ethers.constants.MaxUint256,
}: SignMirrorWithSigData) => {
  const nonce = (await lensHub.sigNonces(signer.address)).toNumber();
  const typedData = createTypedData({
    profileId,
    profileIdPointed,
    pubIdPointed,
    referenceModuleData,
    referenceModule,
    referenceModuleInitData,
    nonce,
    deadline: toStringOrNumber(deadline)
  });

  const { v, r, s } = await signData(signer.provider, signer.address, typedData);

  return {
    profileId,
    profileIdPointed,
    pubIdPointed,
    referenceModuleData,
    referenceModule,
    referenceModuleInitData,
    sig: {
      v,
      r,
      s,
      deadline: toStringOrNumber(deadline),
    },
  };
}
