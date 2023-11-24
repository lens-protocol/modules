import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumberish, Bytes } from 'ethers';
import { ethers } from 'hardhat';
import { Domain, EIP712Domain, signData, toStringOrNumber } from '../utils';
import { domain } from '../../utils';
import { lensHub } from '../../../__setup.spec';

interface CommentWithSigMessage {
  profileId: number | string,
  contentURI: string,
  profileIdPointed: number | string,
  pubIdPointed: number | string,
  referenceModuleData: Bytes | string,
  collectModule: string,
  collectModuleInitData: Bytes | string,
  referenceModule: string,
  referenceModuleInitData: Bytes | string,
  nonce: number | string,
  deadline: number | string,
};

const createTypedData = (message: CommentWithSigMessage) => ({
  types: {
    EIP712Domain,
    CommentWithSig: [
      { name: 'profileId', type: 'uint256' },
      { name: 'contentURI', type: 'string' },
      { name: 'profileIdPointed', type: 'uint256' },
      { name: 'pubIdPointed', type: 'uint256' },
      { name: 'referenceModuleData', type: 'bytes' },
      { name: 'collectModule', type: 'address' },
      { name: 'collectModuleInitData', type: 'bytes' },
      { name: 'referenceModule', type: 'address' },
      { name: 'referenceModuleInitData', type: 'bytes' },
      { name: 'nonce', type: 'uint256' },
      { name: 'deadline', type: 'uint256' },
    ],
  },
  domain: domain(),
  primaryType: 'CommentWithSig',
  message,
});

interface SignCommentWithSigData {
  signer: SignerWithAddress,
  profileId: number | string,
  contentURI: string,
  profileIdPointed: number | string,
  pubIdPointed: number | string,
  referenceModuleData: Bytes | string,
  collectModule: string,
  collectModuleInitData: Bytes | string,
  referenceModule: string,
  referenceModuleInitData: Bytes | string,
  deadline?: BigNumberish
};

export default async ({
  signer,
  profileId,
  contentURI,
  profileIdPointed,
  pubIdPointed,
  referenceModuleData,
  collectModule,
  collectModuleInitData,
  referenceModule,
  referenceModuleInitData,
  deadline = ethers.constants.MaxUint256,
}: SignCommentWithSigData) => {
  const nonce = (await lensHub.sigNonces(signer.address)).toNumber();
  const typedData = createTypedData({
    profileId,
    contentURI,
    profileIdPointed,
    pubIdPointed,
    referenceModuleData,
    collectModule,
    collectModuleInitData,
    referenceModule,
    referenceModuleInitData,
    nonce,
    deadline: toStringOrNumber(deadline)
  });

  const { v, r, s } = await signData(signer.provider, signer.address, typedData);

  return {
    profileId,
    contentURI,
    profileIdPointed,
    pubIdPointed,
    referenceModuleData,
    collectModule,
    collectModuleInitData,
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
