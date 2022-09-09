// File based on https://github.com/dmihal/eth-permit/blob/master/src/eth-permit.ts, modified for other EIP-712 message

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumberish } from 'ethers';
import { ethers } from 'hardhat';
import { UpdatableOwnableFeeCollectModule__factory } from '../../../../../typechain';
import { UPDATE_MODULE_PARAMETERS_WITH_SIG_DOMAIN } from '../../../../modules/collect/updatable-ownable-fee-collect-module.spec';
import {
  currency,
  DEFAULT_AMOUNT,
  feeRecipient,
  FIRST_PROFILE_ID,
  FIRST_PUB_ID,
  REFERRAL_FEE_BPS,
} from '../../../../__setup.spec';
import { Domain, EIP712Domain, RSV, signData, toStringOrNumber } from '../../utils';

interface UpdateModuleParametersWithSigMessage {
  profileId: number | string;
  pubId: number | string;
  amount: number | string;
  currency: string;
  recipient: string;
  referralFee: number | string;
  followerOnly: boolean;
  nonce: number | string;
  deadline: number | string;
}

const createTypedData = (message: UpdateModuleParametersWithSigMessage, domain: Domain) => {
  const typedData = {
    types: {
      EIP712Domain,
      UpdateModuleParametersWithSig: [
        { name: 'profileId', type: 'uint256' },
        { name: 'pubId', type: 'uint256' },
        { name: 'amount', type: 'uint256' },
        { name: 'currency', type: 'address' },
        { name: 'recipient', type: 'address' },
        { name: 'referralFee', type: 'uint16' },
        { name: 'followerOnly', type: 'bool' },
        { name: 'nonce', type: 'uint256' },
        { name: 'deadline', type: 'uint256' },
      ],
    },
    primaryType: 'UpdateModuleParametersWithSig',
    domain,
    message,
  };

  return typedData;
};

interface SignUpdateModuleParametersWithSigMessageData {
  signer: SignerWithAddress;
  domain?: Domain;
  profileId?: BigNumberish;
  pubId?: BigNumberish;
  amount?: BigNumberish;
  feeCurrency?: string;
  recipient?: string;
  referralFee?: BigNumberish;
  followerOnly?: boolean;
  nonce?: BigNumberish;
  deadline?: BigNumberish;
}

export async function signUpdateModuleParametersWithSigMessage({
  signer,
  domain = UPDATE_MODULE_PARAMETERS_WITH_SIG_DOMAIN,
  profileId = FIRST_PROFILE_ID,
  pubId = FIRST_PUB_ID,
  amount = DEFAULT_AMOUNT,
  feeCurrency = currency.address,
  recipient = feeRecipient.address,
  referralFee = REFERRAL_FEE_BPS,
  followerOnly = false,
  nonce,
  deadline = ethers.constants.MaxUint256,
}: SignUpdateModuleParametersWithSigMessageData): Promise<
  UpdateModuleParametersWithSigMessage & RSV
> {
  const message: UpdateModuleParametersWithSigMessage = {
    profileId: toStringOrNumber(profileId),
    pubId: toStringOrNumber(pubId),
    amount: toStringOrNumber(amount),
    currency: feeCurrency,
    recipient: recipient,
    referralFee: toStringOrNumber(referralFee),
    followerOnly: followerOnly,
    nonce: toStringOrNumber(
      nonce ||
        (await new UpdatableOwnableFeeCollectModule__factory(signer)
          .attach(domain.verifyingContract)
          .sigNonces(signer.address))
    ),
    deadline: toStringOrNumber(deadline),
  };

  const typedData = createTypedData(message, domain);
  const sig = await signData(signer.provider, signer.address, typedData);

  return { ...sig, ...message };
}
