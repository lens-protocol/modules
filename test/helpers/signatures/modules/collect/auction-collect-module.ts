// File based on https://github.com/dmihal/eth-permit/blob/master/src/eth-permit.ts, modified for other EIP-712 message

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumberish } from 'ethers';
import { ethers } from 'hardhat';
import { AuctionCollectModule__factory } from '../../../../../typechain';
import { BID_WITH_SIG_DOMAIN } from '../../../../modules/collect/auction-collect-module.spec';
import { DEFAULT_AMOUNT, FIRST_PROFILE_ID, FIRST_PUB_ID } from '../../../../__setup.spec';
import { Domain, EIP712Domain, RSV, signData, toStringOrNumber } from '../../utils';

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
  nonce?: BigNumberish;
  deadline?: BigNumberish;
}

export async function signBidWithSigMessage({
  signer,
  domain = BID_WITH_SIG_DOMAIN,
  profileId = FIRST_PROFILE_ID,
  pubId = FIRST_PUB_ID,
  amount = DEFAULT_AMOUNT,
  followNftTokenId = 0,
  nonce,
  deadline = ethers.constants.MaxUint256,
}: SignBidWithSigMessageData): Promise<BidWithSigMessage & RSV> {
  const message: BidWithSigMessage = {
    profileId: toStringOrNumber(profileId),
    pubId: toStringOrNumber(pubId),
    amount: toStringOrNumber(amount),
    followNftTokenId: toStringOrNumber(followNftTokenId),
    nonce: toStringOrNumber(
      nonce ||
        (await new AuctionCollectModule__factory(signer)
          .attach(domain.verifyingContract)
          .nonces(signer.address))
    ),
    deadline: toStringOrNumber(deadline),
  };

  const typedData = createTypedData(message, domain);
  const sig = await signData(signer.provider, signer.address, typedData);

  return { ...sig, ...message };
}
