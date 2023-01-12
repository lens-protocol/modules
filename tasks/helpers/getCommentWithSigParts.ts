import {
  // Signer,
  BigNumber,
  utils,
  Bytes,
} from "ethers";
import {
  LENS_DOMAIN_NAME,
  LENS_DOMAIN_VERSION,
} from './utils';

const buildCommentWithSigParams = (
  chainId: number,
  lensHubAddress: string,
  profileId: number | string,
  contentURI: string,
  profileIdPointed: number | string,
  pubIdPointed: number | string,
  referenceModuleData: Bytes | string,
  collectModule: string,
  collectModuleInitData: Bytes | string,
  referenceModule: string,
  referenceModuleInitData: Bytes | string,
  nonce: number,
  deadline: string
) => ({
  types: {
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
    ]
  },
  domain: {
    name: LENS_DOMAIN_NAME,
    version: LENS_DOMAIN_VERSION,
    chainId,
    verifyingContract: lensHubAddress,
  },
  value: {
    profileId,
    contentURI,
    profileIdPointed,
    pubIdPointed,
    referenceModuleData,
    collectModule,
    collectModuleInitData,
    referenceModule,
    referenceModuleInitData,
    nonce: nonce,
    deadline: deadline,
  },
});

type CommentWithSigDataProps = {
  chainId: number;
  wallet: any; // Signer
  lensHubAddress: string;
  profileId: number | string;
  contentURI: string;
  profileIdPointed: number | string;
  pubIdPointed: number | string;
  referenceModuleData: Bytes | string;
  collectModule: string,
  collectModuleInitData: Bytes | string,
  referenceModule: string;
  referenceModuleInitData: Bytes | string;
  nonce: number;
  deadline: string;
};

export default async ({
  chainId,
  wallet,
  lensHubAddress,
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
  deadline
}: CommentWithSigDataProps) => {
  const msgParams = buildCommentWithSigParams(
    chainId,
    lensHubAddress,
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
    deadline
  );
  const sig = await wallet._signTypedData(msgParams.domain, msgParams.types, msgParams.value);
  const { v, r, s } = utils.splitSignature(sig);

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
      deadline,
    },
  };
};
