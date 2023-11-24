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

const buildCollectWithSigParams = (
  chainId: number,
  lensHubAddress: string,
  profileId: number | string,
  pubId: number | string,
  data: Bytes | string,
  nonce: number,
  deadline: string
) => ({
  types: {
    CollectWithSig: [
      { name: 'profileId', type: 'uint256' },
      { name: 'pubId', type: 'uint256' },
      { name: 'data', type: 'bytes' },
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
    pubId,
    data,
    nonce: nonce,
    deadline: deadline,
  },
});

type CollectWithSigDataProps = {
  chainId: number;
  wallet: any; // Signer
  lensHubAddress: string;
  profileId: number | string,
  pubId: number | string,
  data: Bytes | string,
  nonce: number;
  deadline: string;
  collector: string;
};

export default async ({
  chainId,
  wallet,
  lensHubAddress,
  profileId,
  pubId,
  data,
  nonce,
  deadline,
  collector,
}: CollectWithSigDataProps) => {
  const msgParams = buildCollectWithSigParams(
    chainId,
    lensHubAddress,
    profileId,
    pubId,
    data,
    nonce,
    deadline
  );
  const sig = await wallet._signTypedData(msgParams.domain, msgParams.types, msgParams.value);
  const { v, r, s } = utils.splitSignature(sig);

  return {
    collector,
    profileId,
    pubId,
    data,
    sig: {
      v,
      r,
      s,
      deadline,
    },
  };
};
