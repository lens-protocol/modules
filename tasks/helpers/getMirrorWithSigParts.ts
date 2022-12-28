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

const buildMirrorWithSigParams = (
  chainId: number,
  lensHubAddress: string,
  profileId: number | string,
  profileIdPointed: number | string,
  pubIdPointed: number | string,
  referenceModuleData: Bytes | string,
  referenceModule: string,
  referenceModuleInitData: Bytes | string,
  nonce: number,
  deadline: string
) => ({
  types: {
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
  domain: {
    name: LENS_DOMAIN_NAME,
    version: LENS_DOMAIN_VERSION,
    chainId,
    verifyingContract: lensHubAddress,
  },
  value: {
    profileId,
    profileIdPointed,
    pubIdPointed,
    referenceModuleData,
    referenceModule,
    referenceModuleInitData,
    nonce: nonce,
    deadline: deadline,
  },
});

type MirrorWithSigDataProps = {
  chainId: number;
  wallet: any; // Signer
  lensHubAddress: string;
  profileId: number | string,
  profileIdPointed: number | string,
  pubIdPointed: number | string,
  referenceModuleData: Bytes | string,
  referenceModule: string,
  referenceModuleInitData: Bytes | string,
  nonce: number;
  deadline: string;
};

export default async ({
  chainId,
  wallet,
  lensHubAddress,
  profileId,
  profileIdPointed,
  pubIdPointed,
  referenceModuleData,
  referenceModule,
  referenceModuleInitData,
  nonce,
  deadline
}: MirrorWithSigDataProps) => {
  const msgParams = buildMirrorWithSigParams(
    chainId,
    lensHubAddress,
    profileId,
    profileIdPointed,
    pubIdPointed,
    referenceModuleData,
    referenceModule,
    referenceModuleInitData,
    nonce,
    deadline
  );
  const sig = await wallet._signTypedData(msgParams.domain, msgParams.types, msgParams.value);
  const { v, r, s } = utils.splitSignature(sig);

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
      deadline,
    },
  };
};
