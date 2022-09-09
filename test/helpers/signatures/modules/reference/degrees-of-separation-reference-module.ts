// File based on https://github.com/dmihal/eth-permit/blob/master/src/eth-permit.ts, modified for other EIP-712 message

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumberish } from 'ethers';
import { ethers } from 'hardhat';
import { DegreesOfSeparationReferenceModule__factory } from '../../../../../typechain';
import {
  DEFAULT_DEGREES_OF_SEPARATION,
  UPDATE_MODULE_PARAMETERS_WITH_SIG_DOMAIN,
} from '../../../../modules/reference/degrees-of-separation-reference-module.spec';
import { FIRST_PROFILE_ID, FIRST_PUB_ID } from '../../../../__setup.spec';
import { Domain, EIP712Domain, RSV, signData, toStringOrNumber } from '../../utils';

interface UpdateModuleParametersWithSigMessage {
  profileId: number | string;
  pubId: number | string;
  commentsRestricted: boolean;
  mirrorsRestricted: boolean;
  degreesOfSeparation: number;
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
        { name: 'commentsRestricted', type: 'bool' },
        { name: 'mirrorsRestricted', type: 'bool' },
        { name: 'degreesOfSeparation', type: 'uint8' },
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
  commentsRestricted?: boolean;
  mirrorsRestricted?: boolean;
  degreesOfSeparation?: number;
  nonce?: BigNumberish;
  deadline?: BigNumberish;
}

export async function signUpdateModuleParametersWithSigMessage({
  signer,
  domain = UPDATE_MODULE_PARAMETERS_WITH_SIG_DOMAIN,
  profileId = FIRST_PROFILE_ID,
  pubId = FIRST_PUB_ID,
  commentsRestricted = true,
  mirrorsRestricted = true,
  degreesOfSeparation = DEFAULT_DEGREES_OF_SEPARATION,
  nonce,
  deadline = ethers.constants.MaxUint256,
}: SignUpdateModuleParametersWithSigMessageData): Promise<
  UpdateModuleParametersWithSigMessage & RSV
> {
  const message: UpdateModuleParametersWithSigMessage = {
    profileId: toStringOrNumber(profileId),
    pubId: toStringOrNumber(pubId),
    commentsRestricted: commentsRestricted,
    mirrorsRestricted: mirrorsRestricted,
    degreesOfSeparation: degreesOfSeparation,
    nonce: toStringOrNumber(
      nonce ||
        (await new DegreesOfSeparationReferenceModule__factory(signer)
          .attach(domain.verifyingContract)
          .nonces(signer.address))
    ),
    deadline: toStringOrNumber(deadline),
  };

  const typedData = createTypedData(message, domain);
  const sig = await signData(signer.provider, signer.address, typedData);

  return { ...sig, ...message };
}
