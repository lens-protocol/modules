import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumberish, Bytes } from 'ethers';
import { ethers } from 'hardhat';
import { Domain, EIP712Domain, signData, toStringOrNumber } from '../utils';
import { domain } from '../../utils';
import { lensHub } from '../../../__setup.spec';

interface CollectWithSigMessage {
  profileId: string | number,
  pubId: string | number,
  data: Bytes | string,
  nonce: number | string,
  deadline: number | string,
};

const createTypedData = (message: CollectWithSigMessage) => ({
  types: {
    EIP712Domain,
    CollectWithSig: [
      { name: 'profileId', type: 'uint256' },
      { name: 'pubId', type: 'uint256' },
      { name: 'data', type: 'bytes' },
      { name: 'nonce', type: 'uint256' },
      { name: 'deadline', type: 'uint256' },
    ],
  },
  domain: domain(),
  primaryType: 'CollectWithSig',
  message,
});

interface SignCollectWithSigData {
  signer: SignerWithAddress,
  profileId: string | number,
  pubId: string | number,
  data: Bytes | string,
  deadline?: BigNumberish
};

export default async ({
  signer,
  profileId,
  pubId,
  data,
  deadline = ethers.constants.MaxUint256,
}: SignCollectWithSigData) => {
  const nonce = (await lensHub.sigNonces(signer.address)).toNumber();
  const typedData = createTypedData({
    profileId,
    pubId,
    data,
    nonce,
    deadline: toStringOrNumber(deadline)
  });

  const { v, r, s } = await signData(signer.provider, signer.address, typedData);

  return {
    collector: signer.address,
    profileId,
    pubId,
    data,
    sig: {
      v,
      r,
      s,
      deadline: toStringOrNumber(deadline),
    },
  };
}
