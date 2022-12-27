import {
  // Signer,
  BigNumber,
  utils,
  Bytes,
} from "ethers";

const LENS_DOMAIN_NAME = 'Lens Protocol Profiles';
const LENS_DOMAIN_VERSION = '1';

const buildFollowWithSigParams = (
  chainId: number,
  lensHubAddress: string,
  profileIds: BigNumber[] | string[],
  datas: Bytes[] | string[],
  nonce: number,
  deadline: string
) => ({
  types: {
    FollowWithSig: [
      { name: 'profileIds', type: 'uint256[]' },
      { name: 'datas', type: 'bytes[]' },
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
    profileIds: profileIds,
    datas: datas,
    nonce: nonce,
    deadline: deadline,
  },
});

type FollowWithSigDataProps = {
  chainId: number;
  wallet: any; // Signer
  lensHubAddress: string;
  profileIds: BigNumber[] | string[];
  datas: Bytes[] | string[];
  nonce: number;
  deadline: string;
  follower: string;
};

export default async ({
  chainId,
  wallet,
  lensHubAddress,
  profileIds,
  datas,
  nonce,
  deadline,
  follower
}: FollowWithSigDataProps) => {
  const msgParams = buildFollowWithSigParams(
    chainId,
    lensHubAddress,
    profileIds,
    datas,
    nonce,
    deadline
  );
  const sig = await wallet._signTypedData(msgParams.domain, msgParams.types, msgParams.value);
  const { v, r, s } = utils.splitSignature(sig);

  return {
    follower,
    profileIds,
    datas,
    sig: {
      v,
      r,
      s,
      deadline,
    },
  };
};
