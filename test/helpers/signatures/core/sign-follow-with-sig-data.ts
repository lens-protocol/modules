import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumberish, Bytes } from 'ethers';
import { ethers } from 'hardhat';
import { Domain, EIP712Domain, signData, toStringOrNumber } from '../utils';
import { domain } from '../../utils';
import { lensHub } from '../../../__setup.spec';

interface FollowWithSigMessage {
  profileIds: string[] | number[],
  datas: Bytes[] | string[],
  nonce: number | string,
  deadline: number | string,
};

const createTypedData = (message: FollowWithSigMessage) => ({
  types: {
    EIP712Domain,
    FollowWithSig: [
      { name: 'profileIds', type: 'uint256[]' },
      { name: 'datas', type: 'bytes[]' },
      { name: 'nonce', type: 'uint256' },
      { name: 'deadline', type: 'uint256' },
    ],
  },
  domain: domain(),
  primaryType: 'FollowWithSig',
  message,
});

interface SignFollowWithSigData {
  signer: SignerWithAddress;
  profileIds: string[] | number[],
  datas: Bytes[] | string[],
  deadline?: BigNumberish,
};

export default async ({
  signer,
  profileIds,
  datas,
  deadline = ethers.constants.MaxUint256,
}: SignFollowWithSigData) => {
  const nonce = (await lensHub.sigNonces(signer.address)).toNumber();
  const typedData = createTypedData({
    profileIds,
    datas,
    nonce,
    deadline: toStringOrNumber(deadline)
  });

  const { v, r, s } = await signData(signer.provider, signer.address, typedData);

  return {
    follower: signer.address,
    profileIds,
    datas,
    sig: {
      v,
      r,
      s,
      deadline: toStringOrNumber(deadline),
    },
  };
}
