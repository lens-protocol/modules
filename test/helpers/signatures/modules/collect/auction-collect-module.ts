// File based on https://github.com/dmihal/eth-permit/blob/master/src/eth-permit.ts, modified for other EIP-712 message

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumberish } from 'ethers';
import { ethers } from 'hardhat';
import {
  BID_WITH_SIG_DOMAIN,
  DEFAULT_BID_AMOUNT,
} from '../../../../modules/collect/auction-collect-module.spec';
import { FIRST_FOLLOW_NFT_ID, FIRST_PROFILE_ID, FIRST_PUB_ID } from '../../../../__setup.spec';
import {
  call,
  Domain,
  EIP712Domain,
  NONCES_FN,
  RSV,
  signData,
  toStringOrNumber,
  zeros,
} from '../../utils';

interface BidWithSigMessage {
  profileId: number | string;
  pubId: number | string;
  amount: number | string;
  followNftTokenId: number | string;
  nonce: number | string;
  deadline: number | string;
}

const createTypedData = (message: BidWithSigMessage, domain: Domain) => {
  const typedData = {
    types: {
      EIP712Domain,
      BidWithSig: [
        { name: 'profileId', type: 'uint256' },
        { name: 'pubId', type: 'uint256' },
        { name: 'amount', type: 'uint256' },
        { name: 'followNftTokenId', type: 'uint256' },
        { name: 'nonce', type: 'uint256' },
        { name: 'deadline', type: 'uint256' },
      ],
    },
    primaryType: 'BidWithSig',
    domain,
    message,
  };

  return typedData;
};

interface SignBidWithSigMessageData {
  signer: SignerWithAddress;
  domain?: Domain;
  profileId?: BigNumberish;
  pubId?: BigNumberish;
  amount?: BigNumberish;
  followNftTokenId?: BigNumberish;
  deadline?: BigNumberish;
  nonce?: BigNumberish;
}

export async function signBidWithSigMessage({
  signer,
  domain = BID_WITH_SIG_DOMAIN,
  profileId = FIRST_PROFILE_ID,
  pubId = FIRST_PUB_ID,
  amount = DEFAULT_BID_AMOUNT,
  followNftTokenId = 0,
  deadline = ethers.constants.MaxUint256,
  nonce,
}: SignBidWithSigMessageData): Promise<BidWithSigMessage & RSV> {
  const message: BidWithSigMessage = {
    profileId: toStringOrNumber(profileId),
    pubId: toStringOrNumber(pubId),
    amount: toStringOrNumber(amount),
    followNftTokenId: toStringOrNumber(followNftTokenId),
    nonce:
      (nonce ? toStringOrNumber(nonce) : nonce) ||
      (await call(
        signer.provider,
        domain.verifyingContract,
        `${NONCES_FN}${zeros(24)}${signer.address.substr(2)}`
      )),
    deadline: toStringOrNumber(deadline),
  };

  const typedData = createTypedData(message, domain);
  const sig = await signData(signer.provider, signer.address, typedData);

  return { ...sig, ...message };
}
