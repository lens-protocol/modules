import { BigNumber, BigNumberish } from '@ethersproject/bignumber';
import { parseEther } from '@ethersproject/units';
import '@nomiclabs/hardhat-ethers';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import { UpdatableOwnableFeeCollectModule__factory } from '../../../typechain';
import { ERRORS } from '../../helpers/errors';
import {
  abiCoder,
  updatableOwnableFeeCollectModule,
  BPS_MAX,
  chainId,
  currency,
  feeRecipient,
  FIRST_PROFILE_ID,
  FIRST_PUB_ID,
  lensHub,
  makeSuiteCleanRoom,
  MOCK_FOLLOW_NFT_URI,
  MOCK_PROFILE_HANDLE,
  MOCK_URI,
  moduleGlobals,
  anotherUser,
  REFERRAL_FEE_BPS,
  user,
  deployer,
  treasury,
  TREASURY_FEE_BPS,
  governance,
  DEFAULT_AMOUNT,
} from './../../__setup.spec';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { publisher } from '../../__setup.spec';
import { getTimestamp, matchEvent, setNextBlockTimestamp, waitForTx } from '../../helpers/utils';
import { Domain } from '../../helpers/signatures/utils';
import { PubType } from '../../helpers/constants';
import { signUpdateModuleParametersWithSigMessage } from '../../helpers/signatures/modules/collect/updatable-ownable-fee-collect-module';
import { base64 } from 'ethers/lib/utils';

export let UPDATE_MODULE_PARAMETERS_WITH_SIG_DOMAIN: Domain;

makeSuiteCleanRoom('UpdatableOwnableFeeCollectModule', function () {
  const FIRST_TOKEN_ID = ethers.constants.One;
  let DEFAULT_COLLECT_DATA;

  interface UpdatableOwnableFeeCollectModuleInitData {
    amount?: BigNumber;
    feeCurrency?: string;
    recipient?: string;
    referralFee?: number;
    followerOnly?: boolean;
  }

  async function getUpdatableOwnableFeeCollectModuleInitData({
    amount = DEFAULT_AMOUNT,
    feeCurrency = currency.address,
    recipient = feeRecipient.address,
    referralFee = REFERRAL_FEE_BPS,
    followerOnly = false,
  }: UpdatableOwnableFeeCollectModuleInitData): Promise<string> {
    return abiCoder.encode(
      ['uint256', 'address', 'address', 'uint16', 'bool'],
      [amount, feeCurrency, recipient, referralFee, followerOnly]
    );
  }

  interface MintAndApproveCurrency {
    owner?: SignerWithAddress;
    spender?: string;
    amountToMint?: BigNumberish;
    amountToApprove?: BigNumberish;
  }

  async function mintAndApproveCurrency({
    owner = user,
    spender = updatableOwnableFeeCollectModule.address,
    amountToMint = parseEther('100000'),
    amountToApprove = ethers.constants.MaxUint256,
  }: MintAndApproveCurrency) {
    await currency.connect(owner).mint(owner.address, amountToMint);
    await currency.connect(owner).approve(spender, amountToApprove);
  }

  beforeEach(async function () {
    UPDATE_MODULE_PARAMETERS_WITH_SIG_DOMAIN = {
      name: 'UpdatableOwnableFeeCollectModule',
      version: '1',
      chainId: chainId,
      verifyingContract: updatableOwnableFeeCollectModule.address,
    };
    await expect(
      lensHub.createProfile({
        to: publisher.address,
        handle: MOCK_PROFILE_HANDLE,
        imageURI: MOCK_URI,
        followModule: ethers.constants.AddressZero,
        followModuleInitData: [],
        followNFTURI: MOCK_FOLLOW_NFT_URI,
      })
    ).to.not.be.reverted;
  });

  context('UpdatableOwnableFeeCollectModule', function () {
    context('Publication creation', function () {
      context('Negatives', function () {
        it('User should fail to post using unwhitelisted currency', async function () {
          const unwhitelistedCurrency = ethers.constants.AddressZero;
          expect(await moduleGlobals.isCurrencyWhitelisted(unwhitelistedCurrency)).to.be.false;
          const collectModuleInitData = await getUpdatableOwnableFeeCollectModuleInitData({
            feeCurrency: unwhitelistedCurrency,
          });
          await expect(
            lensHub.connect(publisher).post({
              profileId: FIRST_PROFILE_ID,
              contentURI: MOCK_URI,
              collectModule: updatableOwnableFeeCollectModule.address,
              collectModuleInitData: collectModuleInitData,
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
        });

        it('User should fail to post using referral fee greater than max BPS', async function () {
          const referralFee = BPS_MAX + 1;
          expect(referralFee).to.be.greaterThan(BPS_MAX);
          const collectModuleInitData = await getUpdatableOwnableFeeCollectModuleInitData({
            referralFee: referralFee,
          });
          await expect(
            lensHub.connect(publisher).post({
              profileId: FIRST_PROFILE_ID,
              contentURI: MOCK_URI,
              collectModule: updatableOwnableFeeCollectModule.address,
              collectModuleInitData: collectModuleInitData,
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
        });

        it('User should fail to post passing data with wrong format', async function () {
          const wrongFormattedCollectModuleInitData = abiCoder.encode(
            ['uint256', 'address', 'bool'],
            [DEFAULT_AMOUNT, currency.address, false]
          );
          await expect(
            lensHub.connect(publisher).post({
              profileId: FIRST_PROFILE_ID,
              contentURI: MOCK_URI,
              collectModule: updatableOwnableFeeCollectModule.address,
              collectModuleInitData: wrongFormattedCollectModuleInitData,
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.be.reverted;
        });

        it('Module initialization should fail if the call is not done by the hub', async function () {
          expect(publisher.address).to.not.equal(lensHub.address);
          await expect(
            updatableOwnableFeeCollectModule
              .connect(publisher)
              .initializePublicationCollectModule(
                FIRST_PROFILE_ID,
                FIRST_PUB_ID,
                await getUpdatableOwnableFeeCollectModuleInitData({})
              )
          ).to.be.revertedWith(ERRORS.NOT_HUB);
        });
      });

      context('Scenarios', function () {
        it('User should be able to create a publication that burns tokens by setting the recipient as the zero address', async function () {
          await expect(
            lensHub.connect(publisher).post({
              profileId: FIRST_PROFILE_ID,
              contentURI: MOCK_URI,
              collectModule: updatableOwnableFeeCollectModule.address,
              collectModuleInitData: await getUpdatableOwnableFeeCollectModuleInitData({
                recipient: ethers.constants.AddressZero,
              }),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.not.be.reverted;
          expect(
            await updatableOwnableFeeCollectModule.getPublicationData(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID
            )
          ).to.eqls([
            FIRST_TOKEN_ID,
            DEFAULT_AMOUNT,
            currency.address,
            ethers.constants.AddressZero,
            REFERRAL_FEE_BPS,
            false,
          ]);
        });

        it('User should be able to create a publication with zero fees', async function () {
          await expect(
            lensHub.connect(publisher).post({
              profileId: FIRST_PROFILE_ID,
              contentURI: MOCK_URI,
              collectModule: updatableOwnableFeeCollectModule.address,
              collectModuleInitData: await getUpdatableOwnableFeeCollectModuleInitData({
                amount: ethers.constants.Zero,
              }),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.not.be.reverted;
          expect(
            await updatableOwnableFeeCollectModule.getPublicationData(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID
            )
          ).to.eqls([
            FIRST_TOKEN_ID,
            ethers.constants.Zero,
            currency.address,
            feeRecipient.address,
            REFERRAL_FEE_BPS,
            false,
          ]);
        });

        it('Ownership NFT should be minted to the publication author after a publishing succeeded', async function () {
          expect(await updatableOwnableFeeCollectModule.totalSupply()).to.be.equals(0);
          await expect(
            lensHub.connect(publisher).post({
              profileId: FIRST_PROFILE_ID,
              contentURI: MOCK_URI,
              collectModule: updatableOwnableFeeCollectModule.address,
              collectModuleInitData: await getUpdatableOwnableFeeCollectModuleInitData({}),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.not.be.reverted;
          expect(
            await updatableOwnableFeeCollectModule.getPublicationData(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID
            )
          ).to.eqls([
            FIRST_TOKEN_ID,
            DEFAULT_AMOUNT,
            currency.address,
            feeRecipient.address,
            REFERRAL_FEE_BPS,
            false,
          ]);
          // Checks now one NFT has been issued and its owner is the publisher
          expect(await updatableOwnableFeeCollectModule.totalSupply()).to.be.equals(
            ethers.constants.One
          );
          expect(await updatableOwnableFeeCollectModule.ownerOf(FIRST_TOKEN_ID)).to.be.equals(
            publisher.address
          );
        });
      });
    });

    context('Publication reverse resolution by token ID', function () {
      context('Negatives', function () {
        it('Fails to retrieve publication if token ID does not exist', async function () {
          expect(await updatableOwnableFeeCollectModule.totalSupply()).to.be.equals(
            ethers.constants.Zero
          );
          await expect(
            updatableOwnableFeeCollectModule.getPublicationByTokenId(FIRST_TOKEN_ID)
          ).to.revertedWith(ERRORS.TOKEN_DOES_NOT_EXIST);
        });
      });

      context('Scenarios', function () {
        it('Returns the correct information after publication has been created', async function () {
          // Creates publication
          await expect(
            lensHub.connect(publisher).post({
              profileId: FIRST_PROFILE_ID,
              contentURI: MOCK_URI,
              collectModule: updatableOwnableFeeCollectModule.address,
              collectModuleInitData: await getUpdatableOwnableFeeCollectModuleInitData({}),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.not.be.reverted;
          // Checks the reverse publication resolution by token ID gets the correct information
          expect(
            await updatableOwnableFeeCollectModule.getPublicationByTokenId(FIRST_TOKEN_ID)
          ).to.eqls([
            ethers.constants.Zero,
            ethers.constants.Zero,
            MOCK_URI,
            ethers.constants.AddressZero,
            updatableOwnableFeeCollectModule.address,
            ethers.constants.AddressZero,
          ]);
        });
      });
    });

    context('Ownership NFT token URI', function () {
      context('Negatives', function () {
        it('Fails to retrieve the token URI if token ID does not exist', async function () {
          expect(await updatableOwnableFeeCollectModule.totalSupply()).to.be.equals(
            ethers.constants.Zero
          );
          await expect(updatableOwnableFeeCollectModule.tokenURI(FIRST_TOKEN_ID)).to.revertedWith(
            ERRORS.TOKEN_DOES_NOT_EXIST
          );
        });
      });

      context('Scenarios', function () {
        it('Returns the correct token URI after publication has been created', async function () {
          // Creates publication
          await expect(
            lensHub.connect(publisher).post({
              profileId: FIRST_PROFILE_ID,
              contentURI: MOCK_URI,
              collectModule: updatableOwnableFeeCollectModule.address,
              collectModuleInitData: await getUpdatableOwnableFeeCollectModuleInitData({}),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.not.be.reverted;
          // Checks the reverse publication resolution by token ID gets the correct information
          const tokenURI = await updatableOwnableFeeCollectModule.tokenURI(FIRST_TOKEN_ID);
          const jsonMetadataBase64String = tokenURI.split('data:application/json;base64,')[1];
          const jsonMetadataBytes = ethers.utils.base64.decode(jsonMetadataBase64String);
          const jsonMetadataString = ethers.utils.toUtf8String(jsonMetadataBytes);
          const jsonMetadata = JSON.parse(jsonMetadataString);
          expect(jsonMetadata).to.eql({
            name: 'Ownership of Lens Publication #1-1',
            description:
              'Owning this NFT allows the owner to change the collect parameters of the #1-1 publication.',
            image: 'ipfs://bafkreifclgvhtotpoquwoo7enjof6xfqjbthukddkxagtykjfnc3kh6khm',
          });
        });
      });
    });

    context('Update module params', function () {
      beforeEach(async function () {
        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: updatableOwnableFeeCollectModule.address,
            collectModuleInitData: await getUpdatableOwnableFeeCollectModuleInitData({}),
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: [],
          })
        ).to.not.be.reverted;
      });

      context('Negatives', function () {
        it('User should fail to update module parameters if he is not owning the corresponding ownership NFT', async function () {
          expect(await updatableOwnableFeeCollectModule.ownerOf(FIRST_TOKEN_ID)).to.be.equals(
            publisher.address
          );
          expect(anotherUser.address).to.not.be.equals(publisher.address);
          await expect(
            updatableOwnableFeeCollectModule
              .connect(anotherUser)
              .updateModuleParameters(
                FIRST_PROFILE_ID,
                FIRST_PUB_ID,
                DEFAULT_AMOUNT,
                currency.address,
                feeRecipient.address,
                REFERRAL_FEE_BPS,
                true
              )
          ).to.be.revertedWith(ERRORS.ONLY_OWNER);
        });

        it('User should fail to update module parameters if he is not owning the corresponding ownership NFT after being trasnferred', async function () {
          expect(await updatableOwnableFeeCollectModule.ownerOf(FIRST_TOKEN_ID)).to.be.equals(
            publisher.address
          );
          expect(anotherUser.address).to.not.be.equals(publisher.address);
          await expect(
            updatableOwnableFeeCollectModule
              .connect(publisher)
              .transferFrom(publisher.address, anotherUser.address, FIRST_TOKEN_ID)
          ).to.not.be.reverted;
          expect(await updatableOwnableFeeCollectModule.ownerOf(FIRST_TOKEN_ID)).to.be.equals(
            anotherUser.address
          );
          await expect(
            updatableOwnableFeeCollectModule
              .connect(publisher)
              .updateModuleParameters(
                FIRST_PROFILE_ID,
                FIRST_PUB_ID,
                DEFAULT_AMOUNT,
                currency.address,
                feeRecipient.address,
                REFERRAL_FEE_BPS,
                true
              )
          ).to.be.revertedWith(ERRORS.ONLY_OWNER);
        });

        it('User should fail to update module parameters if he is setting an unwhitelisted currency', async function () {
          const unwhitelistedCurrency = ethers.constants.AddressZero;
          expect(await moduleGlobals.isCurrencyWhitelisted(unwhitelistedCurrency)).to.be.false;
          await expect(
            updatableOwnableFeeCollectModule
              .connect(publisher)
              .updateModuleParameters(
                FIRST_PROFILE_ID,
                FIRST_PUB_ID,
                DEFAULT_AMOUNT,
                unwhitelistedCurrency,
                feeRecipient.address,
                REFERRAL_FEE_BPS,
                true
              )
          ).to.be.revertedWith(ERRORS.INVALID_PARAMETERS);
        });

        it('User should fail to update module parameters if he is setting a referral fee greater than max BPS', async function () {
          const referralFee = BPS_MAX + 1;
          expect(referralFee).to.be.greaterThan(BPS_MAX);
          await expect(
            updatableOwnableFeeCollectModule
              .connect(publisher)
              .updateModuleParameters(
                FIRST_PROFILE_ID,
                FIRST_PUB_ID,
                DEFAULT_AMOUNT,
                currency.address,
                feeRecipient.address,
                referralFee,
                true
              )
          ).to.be.revertedWith(ERRORS.INVALID_PARAMETERS);
        });

        it('User should fail to update module parameters if publication does not exists', async function () {
          const unexistentPubId = 69;
          expect(await lensHub.getPubType(FIRST_PROFILE_ID, unexistentPubId)).to.equals(
            PubType.Nonexistent
          );
          await expect(
            updatableOwnableFeeCollectModule
              .connect(publisher)
              .updateModuleParameters(
                FIRST_PROFILE_ID,
                unexistentPubId,
                DEFAULT_AMOUNT,
                currency.address,
                feeRecipient.address,
                REFERRAL_FEE_BPS,
                true
              )
          ).to.be.revertedWith(ERRORS.ERC721_QUERY_FOR_NONEXISTENT_TOKEN);
        });
      });

      context('Scenarios', function () {
        it('User should be able to update parameters if owns the ownership NFT and that should emit the expected event', async function () {
          // Verifies the owner before and after the ownership NFT transfer
          expect(await updatableOwnableFeeCollectModule.ownerOf(FIRST_TOKEN_ID)).to.be.equals(
            publisher.address
          );
          // Verifies the parameters before being changed
          expect(
            await updatableOwnableFeeCollectModule.getPublicationData(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID
            )
          ).to.eqls([
            FIRST_TOKEN_ID,
            DEFAULT_AMOUNT,
            currency.address,
            feeRecipient.address,
            REFERRAL_FEE_BPS,
            false,
          ]);
          // Updates the parameters
          const tx = updatableOwnableFeeCollectModule
            .connect(publisher)
            .updateModuleParameters(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID,
              DEFAULT_AMOUNT.add(1),
              currency.address,
              ethers.constants.AddressZero,
              REFERRAL_FEE_BPS,
              true
            );
          const txReceipt = await waitForTx(tx);
          // Verifies the expected event has been emited
          matchEvent(
            txReceipt,
            'ModuleParametersUpdated',
            [
              FIRST_PROFILE_ID,
              FIRST_PUB_ID,
              DEFAULT_AMOUNT.add(1),
              currency.address,
              ethers.constants.AddressZero,
              REFERRAL_FEE_BPS,
              true,
            ],
            updatableOwnableFeeCollectModule
          );
          // Verifies the parameters has been changed
          expect(
            await updatableOwnableFeeCollectModule.getPublicationData(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID
            )
          ).to.eqls([
            FIRST_TOKEN_ID,
            DEFAULT_AMOUNT.add(1),
            currency.address,
            ethers.constants.AddressZero,
            REFERRAL_FEE_BPS,
            true,
          ]);
        });

        it('User should be able to update parameters if owns the ownership NFT after it being transferred', async function () {
          // Verifies the owner before and after the ownership NFT transfer
          expect(await updatableOwnableFeeCollectModule.ownerOf(FIRST_TOKEN_ID)).to.be.equals(
            publisher.address
          );
          expect(anotherUser.address).to.not.be.equals(publisher.address);
          await expect(
            updatableOwnableFeeCollectModule
              .connect(publisher)
              .transferFrom(publisher.address, anotherUser.address, FIRST_TOKEN_ID)
          ).to.not.be.reverted;
          expect(await updatableOwnableFeeCollectModule.ownerOf(FIRST_TOKEN_ID)).to.be.equals(
            anotherUser.address
          );
          // Verifies the parameters before being changed
          expect(
            await updatableOwnableFeeCollectModule.getPublicationData(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID
            )
          ).to.eqls([
            FIRST_TOKEN_ID,
            DEFAULT_AMOUNT,
            currency.address,
            feeRecipient.address,
            REFERRAL_FEE_BPS,
            false,
          ]);
          // The new owner updates the parameters
          await expect(
            updatableOwnableFeeCollectModule
              .connect(anotherUser)
              .updateModuleParameters(
                FIRST_PROFILE_ID,
                FIRST_PUB_ID,
                DEFAULT_AMOUNT.add(1),
                currency.address,
                ethers.constants.AddressZero,
                REFERRAL_FEE_BPS,
                true
              )
          ).to.not.be.reverted;
          // Verifies the parameters has been changed
          expect(
            await updatableOwnableFeeCollectModule.getPublicationData(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID
            )
          ).to.eqls([
            FIRST_TOKEN_ID,
            DEFAULT_AMOUNT.add(1),
            currency.address,
            ethers.constants.AddressZero,
            REFERRAL_FEE_BPS,
            true,
          ]);
        });
      });
    });

    context('Update module params with sig', function () {
      beforeEach(async function () {
        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: updatableOwnableFeeCollectModule.address,
            collectModuleInitData: await getUpdatableOwnableFeeCollectModuleInitData({}),
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: [],
          })
        ).to.not.be.reverted;
      });

      context('Negatives', function () {
        it('User should fail to update module params with sig if recovered signer does not match the expected one', async function () {
          const signature = await signUpdateModuleParametersWithSigMessage({
            signer: anotherUser,
          });
          await expect(
            updatableOwnableFeeCollectModule.updateModuleParametersWithSig(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID,
              DEFAULT_AMOUNT,
              currency.address,
              feeRecipient.address,
              REFERRAL_FEE_BPS,
              false,
              publisher.address,
              signature
            )
          ).to.be.revertedWith(ERRORS.SIGNATURE_INVALID);
        });

        it('User should fail to update module params with sig if signed message deadline was exceeded', async function () {
          const expiredDeadline = ethers.constants.One;
          const signature = await signUpdateModuleParametersWithSigMessage({
            signer: publisher,
            deadline: expiredDeadline,
          });
          expect(expiredDeadline.lt(await getTimestamp())).to.be.true;
          await expect(
            updatableOwnableFeeCollectModule.updateModuleParametersWithSig(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID,
              DEFAULT_AMOUNT,
              currency.address,
              feeRecipient.address,
              REFERRAL_FEE_BPS,
              false,
              publisher.address,
              signature
            )
          ).to.be.revertedWith(ERRORS.SIGNATURE_EXPIRED);
        });

        it('User should fail to update module params with sig if signed message had wrong nonce', async function () {
          const currentNonce = await updatableOwnableFeeCollectModule.sigNonces(publisher.address);
          const invalidNonce = await currentNonce.add(5);
          const signature = await signUpdateModuleParametersWithSigMessage({
            signer: publisher,
            nonce: invalidNonce,
          });
          await expect(
            updatableOwnableFeeCollectModule.updateModuleParametersWithSig(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID,
              DEFAULT_AMOUNT,
              currency.address,
              feeRecipient.address,
              REFERRAL_FEE_BPS,
              false,
              publisher.address,
              signature
            )
          ).to.be.revertedWith(ERRORS.SIGNATURE_INVALID);
        });

        it('User should fail to update module params with sig if signed message domain had wrong version', async function () {
          const invalidVersion = '0';
          const invalidDomain: Domain = {
            name: 'UpdatableOwnableFeeCollectModule',
            version: invalidVersion,
            chainId: chainId,
            verifyingContract: updatableOwnableFeeCollectModule.address,
          };
          const signature = await signUpdateModuleParametersWithSigMessage({
            signer: publisher,
            domain: invalidDomain,
          });
          await expect(
            updatableOwnableFeeCollectModule.updateModuleParametersWithSig(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID,
              DEFAULT_AMOUNT,
              currency.address,
              feeRecipient.address,
              REFERRAL_FEE_BPS,
              false,
              publisher.address,
              signature
            )
          ).to.be.revertedWith(ERRORS.SIGNATURE_INVALID);
        });

        it('User should fail to update module params with sig if signed message domain had wrong chain ID', async function () {
          const invalidChainId = 69;
          expect(chainId).to.not.equals(invalidChainId);
          const invalidDomain: Domain = {
            name: 'UpdatableOwnableFeeCollectModule',
            version: '1',
            chainId: invalidChainId,
            verifyingContract: updatableOwnableFeeCollectModule.address,
          };
          const signature = await signUpdateModuleParametersWithSigMessage({
            signer: publisher,
            domain: invalidDomain,
          });
          await expect(
            updatableOwnableFeeCollectModule.updateModuleParametersWithSig(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID,
              DEFAULT_AMOUNT,
              currency.address,
              feeRecipient.address,
              REFERRAL_FEE_BPS,
              false,
              publisher.address,
              signature
            )
          ).to.be.revertedWith(ERRORS.SIGNATURE_INVALID);
        });

        it('User should fail to update module params with sig if signed message domain had wrong verifying contract', async function () {
          const invalidVerifyingContract = (
            await new UpdatableOwnableFeeCollectModule__factory(deployer).deploy(
              lensHub.address,
              moduleGlobals.address
            )
          ).address;
          const invalidDomain: Domain = {
            name: 'UpdatableOwnableFeeCollectModule',
            version: '1',
            chainId: chainId,
            verifyingContract: invalidVerifyingContract,
          };
          const signature = await signUpdateModuleParametersWithSigMessage({
            signer: publisher,
            domain: invalidDomain,
          });
          await expect(
            updatableOwnableFeeCollectModule.updateModuleParametersWithSig(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID,
              DEFAULT_AMOUNT,
              currency.address,
              feeRecipient.address,
              REFERRAL_FEE_BPS,
              false,
              publisher.address,
              signature
            )
          ).to.be.revertedWith(ERRORS.SIGNATURE_INVALID);
        });

        it('User should fail to update module params with sig if signed message domain had wrong name', async function () {
          const invalidName = 'Updatable Ownable Fee Collect Module';
          const invalidDomain: Domain = {
            name: invalidName,
            version: '1',
            chainId: chainId,
            verifyingContract: updatableOwnableFeeCollectModule.address,
          };
          const signature = await signUpdateModuleParametersWithSigMessage({
            signer: publisher,
            domain: invalidDomain,
          });
          await expect(
            updatableOwnableFeeCollectModule.updateModuleParametersWithSig(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID,
              DEFAULT_AMOUNT,
              currency.address,
              feeRecipient.address,
              REFERRAL_FEE_BPS,
              false,
              publisher.address,
              signature
            )
          ).to.be.revertedWith(ERRORS.SIGNATURE_INVALID);
        });

        it('User should fail to update module parameters if he is not owning the corresponding ownership NFT', async function () {
          expect(await updatableOwnableFeeCollectModule.ownerOf(FIRST_TOKEN_ID)).to.be.equals(
            publisher.address
          );
          expect(anotherUser.address).to.not.be.equals(publisher.address);
          await expect(
            updatableOwnableFeeCollectModule.updateModuleParametersWithSig(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID,
              DEFAULT_AMOUNT,
              currency.address,
              feeRecipient.address,
              REFERRAL_FEE_BPS,
              false,
              anotherUser.address,
              await signUpdateModuleParametersWithSigMessage({ signer: anotherUser })
            )
          ).to.be.revertedWith(ERRORS.ONLY_OWNER);
        });

        it('User should fail to update module parameters if he is not owning the corresponding ownership NFT after being trasnferred', async function () {
          expect(await updatableOwnableFeeCollectModule.ownerOf(FIRST_TOKEN_ID)).to.be.equals(
            publisher.address
          );
          expect(anotherUser.address).to.not.be.equals(publisher.address);
          await expect(
            updatableOwnableFeeCollectModule
              .connect(publisher)
              .transferFrom(publisher.address, anotherUser.address, FIRST_TOKEN_ID)
          ).to.not.be.reverted;
          expect(await updatableOwnableFeeCollectModule.ownerOf(FIRST_TOKEN_ID)).to.be.equals(
            anotherUser.address
          );
          await expect(
            updatableOwnableFeeCollectModule.updateModuleParametersWithSig(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID,
              DEFAULT_AMOUNT,
              currency.address,
              feeRecipient.address,
              REFERRAL_FEE_BPS,
              false,
              publisher.address,
              await signUpdateModuleParametersWithSigMessage({ signer: publisher })
            )
          ).to.be.revertedWith(ERRORS.ONLY_OWNER);
        });

        it('User should fail to update module parameters if he is setting an unwhitelisted currency', async function () {
          const unwhitelistedCurrency = ethers.constants.AddressZero;
          expect(await moduleGlobals.isCurrencyWhitelisted(unwhitelistedCurrency)).to.be.false;
          await expect(
            updatableOwnableFeeCollectModule.updateModuleParametersWithSig(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID,
              DEFAULT_AMOUNT,
              unwhitelistedCurrency,
              feeRecipient.address,
              REFERRAL_FEE_BPS,
              false,
              publisher.address,
              await signUpdateModuleParametersWithSigMessage({
                signer: publisher,
                feeCurrency: unwhitelistedCurrency,
              })
            )
          ).to.be.revertedWith(ERRORS.INVALID_PARAMETERS);
        });

        it('User should fail to update module parameters if he is setting a referral fee greater than max BPS', async function () {
          const referralFee = BPS_MAX + 1;
          expect(referralFee).to.be.greaterThan(BPS_MAX);
          await expect(
            updatableOwnableFeeCollectModule.updateModuleParametersWithSig(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID,
              DEFAULT_AMOUNT,
              currency.address,
              feeRecipient.address,
              referralFee,
              false,
              publisher.address,
              await signUpdateModuleParametersWithSigMessage({
                signer: publisher,
                referralFee: referralFee,
              })
            )
          ).to.be.revertedWith(ERRORS.INVALID_PARAMETERS);
        });

        it('User should fail to update module parameters if publication does not exists', async function () {
          const unexistentPubId = 69;
          expect(await lensHub.getPubType(FIRST_PROFILE_ID, unexistentPubId)).to.equals(
            PubType.Nonexistent
          );
          await expect(
            updatableOwnableFeeCollectModule.updateModuleParametersWithSig(
              FIRST_PROFILE_ID,
              unexistentPubId,
              DEFAULT_AMOUNT,
              currency.address,
              feeRecipient.address,
              REFERRAL_FEE_BPS,
              false,
              publisher.address,
              await signUpdateModuleParametersWithSigMessage({
                signer: publisher,
                pubId: unexistentPubId,
              })
            )
          ).to.be.revertedWith(ERRORS.ERC721_QUERY_FOR_NONEXISTENT_TOKEN);
        });
      });

      context('Scenarios', function () {
        it('User should be able to update parameters through sig if owns the ownership NFT and that should emit the expected event', async function () {
          // Verifies the owner before and after the ownership NFT transfer
          expect(await updatableOwnableFeeCollectModule.ownerOf(FIRST_TOKEN_ID)).to.be.equals(
            publisher.address
          );
          // Verifies the parameters before being changed
          expect(
            await updatableOwnableFeeCollectModule.getPublicationData(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID
            )
          ).to.eqls([
            FIRST_TOKEN_ID,
            DEFAULT_AMOUNT,
            currency.address,
            feeRecipient.address,
            REFERRAL_FEE_BPS,
            false,
          ]);
          // Updates the parameters
          const tx = updatableOwnableFeeCollectModule.updateModuleParametersWithSig(
            FIRST_PROFILE_ID,
            FIRST_PUB_ID,
            DEFAULT_AMOUNT.add(1),
            currency.address,
            feeRecipient.address,
            REFERRAL_FEE_BPS,
            true,
            publisher.address,
            await signUpdateModuleParametersWithSigMessage({
              signer: publisher,
              amount: DEFAULT_AMOUNT.add(1),
              followerOnly: true,
            })
          );
          const txReceipt = await waitForTx(tx);
          // Verifies the expected event has been emited
          matchEvent(
            txReceipt,
            'ModuleParametersUpdated',
            [
              FIRST_PROFILE_ID,
              FIRST_PUB_ID,
              DEFAULT_AMOUNT.add(1),
              currency.address,
              feeRecipient.address,
              REFERRAL_FEE_BPS,
              true,
            ],
            updatableOwnableFeeCollectModule
          );
          // Verifies the parameters has been changed
          expect(
            await updatableOwnableFeeCollectModule.getPublicationData(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID
            )
          ).to.eqls([
            FIRST_TOKEN_ID,
            DEFAULT_AMOUNT.add(1),
            currency.address,
            feeRecipient.address,
            REFERRAL_FEE_BPS,
            true,
          ]);
        });

        it('User should be able to update parameters through sig if owns the ownership NFT after it being transferred', async function () {
          // Verifies the owner before and after the ownership NFT transfer
          expect(await updatableOwnableFeeCollectModule.ownerOf(FIRST_TOKEN_ID)).to.be.equals(
            publisher.address
          );
          expect(anotherUser.address).to.not.be.equals(publisher.address);
          await expect(
            updatableOwnableFeeCollectModule
              .connect(publisher)
              .transferFrom(publisher.address, anotherUser.address, FIRST_TOKEN_ID)
          ).to.not.be.reverted;
          expect(await updatableOwnableFeeCollectModule.ownerOf(FIRST_TOKEN_ID)).to.be.equals(
            anotherUser.address
          );
          // Verifies the parameters before being changed
          expect(
            await updatableOwnableFeeCollectModule.getPublicationData(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID
            )
          ).to.eqls([
            FIRST_TOKEN_ID,
            DEFAULT_AMOUNT,
            currency.address,
            feeRecipient.address,
            REFERRAL_FEE_BPS,
            false,
          ]);
          // The new owner updates the parameters
          await expect(
            updatableOwnableFeeCollectModule.updateModuleParametersWithSig(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID,
              DEFAULT_AMOUNT.add(1),
              currency.address,
              feeRecipient.address,
              REFERRAL_FEE_BPS,
              true,
              anotherUser.address,
              await signUpdateModuleParametersWithSigMessage({
                signer: anotherUser,
                amount: DEFAULT_AMOUNT.add(1),
                followerOnly: true,
              })
            )
          ).to.not.be.reverted;
          // Verifies the parameters has been changed
          expect(
            await updatableOwnableFeeCollectModule.getPublicationData(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID
            )
          ).to.eqls([
            FIRST_TOKEN_ID,
            DEFAULT_AMOUNT.add(1),
            currency.address,
            feeRecipient.address,
            REFERRAL_FEE_BPS,
            true,
          ]);
        });
      });
    });

    context('Collect fees', function () {
      const REFERRER_PROFILE_ID = FIRST_PROFILE_ID + 1;

      beforeEach(async function () {
        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: updatableOwnableFeeCollectModule.address,
            collectModuleInitData: await getUpdatableOwnableFeeCollectModuleInitData({}),
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: [],
          })
        ).to.not.be.reverted;
        DEFAULT_COLLECT_DATA = abiCoder.encode(
          ['address', 'uint256'],
          [currency.address, DEFAULT_AMOUNT]
        );
      });

      context('Negatives', function () {
        it('Process collect call should fail if caller is not the hub', async function () {
          await expect(
            updatableOwnableFeeCollectModule
              .connect(user)
              .processCollect(0, user.address, FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_COLLECT_DATA)
          ).to.be.revertedWith(ERRORS.NOT_HUB);
        });

        it('User should fail to process collect over unexistent publication', async function () {
          const unexistentPubId = 69;
          expect(await lensHub.getPubType(FIRST_PROFILE_ID, unexistentPubId)).to.equals(
            PubType.Nonexistent
          );
          await expect(
            lensHub.connect(user).collect(FIRST_PROFILE_ID, unexistentPubId, DEFAULT_COLLECT_DATA)
          ).to.be.revertedWith(ERRORS.PUBLICATION_DOES_NOT_EXIST);
        });

        it('User should fail to process collect if is only for followers and and he is not following the publication owner', async function () {
          // Updates the parameters to set the publication as collectable only by followers
          await expect(
            updatableOwnableFeeCollectModule
              .connect(publisher)
              .updateModuleParameters(
                FIRST_PROFILE_ID,
                FIRST_PUB_ID,
                DEFAULT_AMOUNT,
                currency.address,
                feeRecipient.address,
                REFERRAL_FEE_BPS,
                true
              )
          ).to.not.be.reverted;
          // Executes the collect call
          await expect(
            lensHub.connect(user).collect(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_COLLECT_DATA)
          ).to.be.revertedWith(ERRORS.FOLLOW_INVALID);
        });

        it('User should fail to process collect if the expected amount mismatch', async function () {
          // The owner updates the parameters to raise the collect price
          await expect(
            updatableOwnableFeeCollectModule
              .connect(publisher)
              .updateModuleParameters(
                FIRST_PROFILE_ID,
                FIRST_PUB_ID,
                DEFAULT_AMOUNT.mul(2),
                currency.address,
                feeRecipient.address,
                REFERRAL_FEE_BPS,
                false
              )
          ).to.not.be.reverted;
          // Executes the collect call but passing through the old price as expected
          await expect(
            lensHub.connect(user).collect(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_COLLECT_DATA)
          ).to.be.revertedWith(ERRORS.MODULE_DATA_MISMATCH);
        });

        it('User should fail to process collect if the expected currency mismatch', async function () {
          // Executes the collect call but passing through a different currency as expected
          const dataWithWrongCurrency = abiCoder.encode(
            ['address', 'uint256'],
            [ethers.constants.AddressZero, DEFAULT_AMOUNT]
          );
          await expect(
            lensHub.connect(user).collect(FIRST_PROFILE_ID, FIRST_PUB_ID, dataWithWrongCurrency)
          ).to.be.revertedWith(ERRORS.MODULE_DATA_MISMATCH);
        });

        it('User should fail to process collect if has not approved the currency to be spent by the module', async function () {
          await mintAndApproveCurrency({ amountToApprove: 0 });
          await expect(
            lensHub.connect(user).collect(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_COLLECT_DATA)
          ).to.be.revertedWith(ERRORS.ERC20_INSUFFICIENT_ALLOWANCE);
        });

        it('User should fail to process collect if has approved the currency to be spent by the module but does not have enough balance', async function () {
          await mintAndApproveCurrency({ amountToMint: 0 });
          await expect(
            lensHub.connect(user).collect(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_COLLECT_DATA)
          ).to.be.revertedWith(ERRORS.ERC20_TRANSFER_EXCEEDS_BALANCE);
        });

        it('User should fail to process collect if the expected amount mismatch when collecting through a mirror', async function () {
          await expect(
            lensHub.createProfile({
              to: anotherUser.address,
              handle: 'referrer.lens',
              imageURI: MOCK_URI,
              followModule: ethers.constants.AddressZero,
              followModuleInitData: [],
              followNFTURI: MOCK_FOLLOW_NFT_URI,
            })
          ).to.not.be.reverted;
          await expect(
            lensHub.connect(anotherUser).mirror({
              profileId: REFERRER_PROFILE_ID,
              profileIdPointed: FIRST_PROFILE_ID,
              pubIdPointed: FIRST_PUB_ID,
              referenceModuleData: [],
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.not.be.reverted;
          // The owner updates the parameters to raise the collect price
          await expect(
            updatableOwnableFeeCollectModule
              .connect(publisher)
              .updateModuleParameters(
                FIRST_PROFILE_ID,
                FIRST_PUB_ID,
                DEFAULT_AMOUNT.mul(2),
                currency.address,
                feeRecipient.address,
                REFERRAL_FEE_BPS,
                false
              )
          ).to.not.be.reverted;
          // Executes the collect call but passing through the old price as expected
          await expect(
            lensHub.connect(user).collect(REFERRER_PROFILE_ID, FIRST_PUB_ID, DEFAULT_COLLECT_DATA)
          ).to.be.revertedWith(ERRORS.MODULE_DATA_MISMATCH);
        });

        it('User should fail to process collect if the expected currency mismatch when collecting through a mirror', async function () {
          await expect(
            lensHub.createProfile({
              to: anotherUser.address,
              handle: 'referrer.lens',
              imageURI: MOCK_URI,
              followModule: ethers.constants.AddressZero,
              followModuleInitData: [],
              followNFTURI: MOCK_FOLLOW_NFT_URI,
            })
          ).to.not.be.reverted;
          await expect(
            lensHub.connect(anotherUser).mirror({
              profileId: REFERRER_PROFILE_ID,
              profileIdPointed: FIRST_PROFILE_ID,
              pubIdPointed: FIRST_PUB_ID,
              referenceModuleData: [],
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.not.be.reverted;
          // Executes the collect call but passing through a different currency as expected
          const dataWithWrongCurrency = abiCoder.encode(
            ['address', 'uint256'],
            [ethers.constants.AddressZero, DEFAULT_AMOUNT]
          );
          await expect(
            lensHub.connect(user).collect(REFERRER_PROFILE_ID, FIRST_PUB_ID, dataWithWrongCurrency)
          ).to.be.revertedWith(ERRORS.MODULE_DATA_MISMATCH);
        });

        it('User should fail to process collect if has not approved the currency to be spent by the module when collecting through a mirror', async function () {
          await expect(
            lensHub.createProfile({
              to: anotherUser.address,
              handle: 'referrer.lens',
              imageURI: MOCK_URI,
              followModule: ethers.constants.AddressZero,
              followModuleInitData: [],
              followNFTURI: MOCK_FOLLOW_NFT_URI,
            })
          ).to.not.be.reverted;
          await expect(
            lensHub.connect(anotherUser).mirror({
              profileId: REFERRER_PROFILE_ID,
              profileIdPointed: FIRST_PROFILE_ID,
              pubIdPointed: FIRST_PUB_ID,
              referenceModuleData: [],
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.not.be.reverted;
          await mintAndApproveCurrency({ amountToApprove: 0 });
          await expect(
            lensHub.connect(user).collect(REFERRER_PROFILE_ID, FIRST_PUB_ID, DEFAULT_COLLECT_DATA)
          ).to.be.revertedWith(ERRORS.ERC20_INSUFFICIENT_ALLOWANCE);
        });

        it('User should fail to process collect if has approved the currency to be spent by the module but does not have enough balance when collecting through a mirror', async function () {
          await expect(
            lensHub.createProfile({
              to: anotherUser.address,
              handle: 'referrer.lens',
              imageURI: MOCK_URI,
              followModule: ethers.constants.AddressZero,
              followModuleInitData: [],
              followNFTURI: MOCK_FOLLOW_NFT_URI,
            })
          ).to.not.be.reverted;
          await expect(
            lensHub.connect(anotherUser).mirror({
              profileId: REFERRER_PROFILE_ID,
              profileIdPointed: FIRST_PROFILE_ID,
              pubIdPointed: FIRST_PUB_ID,
              referenceModuleData: [],
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.not.be.reverted;
          await mintAndApproveCurrency({ amountToMint: 0 });
          await expect(
            lensHub.connect(user).collect(REFERRER_PROFILE_ID, FIRST_PUB_ID, DEFAULT_COLLECT_DATA)
          ).to.be.revertedWith(ERRORS.ERC20_TRANSFER_EXCEEDS_BALANCE);
        });
      });

      context('Scenarios', function () {
        beforeEach(async function () {
          // Creates a new profile
          await expect(
            lensHub.createProfile({
              to: anotherUser.address,
              handle: 'referrer.lens',
              imageURI: MOCK_URI,
              followModule: ethers.constants.AddressZero,
              followModuleInitData: [],
              followNFTURI: MOCK_FOLLOW_NFT_URI,
            })
          ).to.not.be.reverted;
          // The created profile
          await expect(
            lensHub.connect(anotherUser).mirror({
              profileId: REFERRER_PROFILE_ID,
              profileIdPointed: FIRST_PROFILE_ID,
              pubIdPointed: FIRST_PUB_ID,
              referenceModuleData: [],
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.not.be.reverted;
          await mintAndApproveCurrency({});
        });

        it('Owner of referrer profile should not receive collect fees if referrer fee was set to zero', async function () {
          const treasuryBalanceBeforeCollect = await currency.balanceOf(treasury.address);
          const referrerBalanceBeforeCollect = await currency.balanceOf(anotherUser.address);
          const recipientBalanceBeforeCollect = await currency.balanceOf(feeRecipient.address);
          // Updates the parameters to remove the referrer fees
          await expect(
            updatableOwnableFeeCollectModule
              .connect(publisher)
              .updateModuleParameters(
                FIRST_PROFILE_ID,
                FIRST_PUB_ID,
                DEFAULT_AMOUNT,
                currency.address,
                feeRecipient.address,
                ethers.constants.Zero,
                false
              )
          ).to.not.be.reverted;
          // Collects through mirrored publication to set a referrer profile
          await expect(
            lensHub.connect(user).collect(REFERRER_PROFILE_ID, FIRST_PUB_ID, DEFAULT_COLLECT_DATA)
          ).to.not.be.reverted;
          const treasuryBalanceAfterCollect = await currency.balanceOf(treasury.address);
          const referrerBalanceAfterCollect = await currency.balanceOf(anotherUser.address);
          const recipientBalanceAfterCollect = await currency.balanceOf(feeRecipient.address);
          const expectedTreasuryFee = DEFAULT_AMOUNT.mul(TREASURY_FEE_BPS).div(BPS_MAX);
          const expectedScaledAmount = DEFAULT_AMOUNT.sub(expectedTreasuryFee);
          expect(treasuryBalanceAfterCollect).to.be.equals(
            treasuryBalanceBeforeCollect.add(expectedTreasuryFee)
          );
          expect(referrerBalanceAfterCollect).to.be.equals(referrerBalanceBeforeCollect);
          expect(recipientBalanceAfterCollect).to.be.equals(
            recipientBalanceBeforeCollect.add(expectedScaledAmount)
          );
        });

        it('Fee recipient should receive all the fees except for the cut corresponding to the treasury', async function () {
          const treasuryBalanceBeforeCollect = await currency.balanceOf(treasury.address);
          const recipientBalanceBeforeCollect = await currency.balanceOf(feeRecipient.address);
          // Collects through original publication to avoid setting a referrer profile
          await expect(
            lensHub.connect(user).collect(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_COLLECT_DATA)
          ).to.not.be.reverted;
          const treasuryBalanceAfterCollect = await currency.balanceOf(treasury.address);
          const recipientBalanceAfterCollect = await currency.balanceOf(feeRecipient.address);
          const expectedTreasuryFee = DEFAULT_AMOUNT.mul(TREASURY_FEE_BPS).div(BPS_MAX);
          const expectedScaledAmount = DEFAULT_AMOUNT.sub(expectedTreasuryFee);
          expect(treasuryBalanceAfterCollect).to.be.equals(
            treasuryBalanceBeforeCollect.add(expectedTreasuryFee)
          );
          expect(recipientBalanceAfterCollect).to.be.equals(
            recipientBalanceBeforeCollect.add(expectedScaledAmount)
          );
        });

        it('Recipient, owner of referrer profile and treasury should receive a cut of the collect fees', async function () {
          const treasuryBalanceBeforeCollect = await currency.balanceOf(treasury.address);
          const referrerBalanceBeforeCollect = await currency.balanceOf(anotherUser.address);
          const recipientBalanceBeforeCollect = await currency.balanceOf(feeRecipient.address);
          // Collects through mirrored publication to set a referrer profile
          await expect(
            lensHub.connect(user).collect(REFERRER_PROFILE_ID, FIRST_PUB_ID, DEFAULT_COLLECT_DATA)
          ).to.not.be.reverted;
          const treasuryBalanceAfterCollect = await currency.balanceOf(treasury.address);
          const referrerBalanceAfterCollect = await currency.balanceOf(anotherUser.address);
          const recipientBalanceAfterCollect = await currency.balanceOf(feeRecipient.address);
          const expectedTreasuryFee = DEFAULT_AMOUNT.mul(TREASURY_FEE_BPS).div(BPS_MAX);
          const expectedScaledAmount = DEFAULT_AMOUNT.sub(expectedTreasuryFee);
          const expectedReferralFee = expectedScaledAmount.mul(REFERRAL_FEE_BPS).div(BPS_MAX);
          const expectedRecipientFee = expectedScaledAmount.sub(expectedReferralFee);
          expect(treasuryBalanceAfterCollect).to.be.equals(
            treasuryBalanceBeforeCollect.add(expectedTreasuryFee)
          );
          expect(referrerBalanceAfterCollect).to.be.equals(
            referrerBalanceBeforeCollect.add(expectedReferralFee)
          );
          expect(recipientBalanceAfterCollect).to.be.equals(
            recipientBalanceBeforeCollect.add(expectedRecipientFee)
          );
        });

        it('Owner should receive all collect fees when publication is collected through original publication and treasury fee was set to zero', async function () {
          // Sets treasury fee to zero
          await expect(moduleGlobals.connect(governance).setTreasuryFee(0)).to.not.be.reverted;
          const treasuryBalanceBeforeCollect = await currency.balanceOf(treasury.address);
          const recipientBalanceBeforeCollect = await currency.balanceOf(feeRecipient.address);
          // Collects through original publication to avoid setting a referrer profile
          await expect(
            lensHub.connect(user).collect(FIRST_PUB_ID, FIRST_PUB_ID, DEFAULT_COLLECT_DATA)
          ).to.not.be.reverted;
          const treasuryBalanceAfterCollect = await currency.balanceOf(treasury.address);
          const recipientBalanceAfterCollect = await currency.balanceOf(feeRecipient.address);
          expect(treasuryBalanceAfterCollect).to.be.equals(treasuryBalanceBeforeCollect);
          expect(recipientBalanceAfterCollect).to.be.equals(
            recipientBalanceBeforeCollect.add(DEFAULT_AMOUNT)
          );
        });

        it('Fee recipient and referrer profile owner should share the entire fees between them if treasury feet was set to zero', async function () {
          // Sets treasury fee to zero
          await expect(moduleGlobals.connect(governance).setTreasuryFee(0)).to.not.be.reverted;
          const treasuryBalanceBeforeCollect = await currency.balanceOf(treasury.address);
          const referrerBalanceBeforeCollect = await currency.balanceOf(anotherUser.address);
          const recipientBalanceBeforeCollect = await currency.balanceOf(feeRecipient.address);
          // Collects through mirrored publication to set a referrer profile
          await expect(
            lensHub.connect(user).collect(REFERRER_PROFILE_ID, FIRST_PUB_ID, DEFAULT_COLLECT_DATA)
          ).to.not.be.reverted;
          const treasuryBalanceAfterCollect = await currency.balanceOf(treasury.address);
          const referrerBalanceAfterCollect = await currency.balanceOf(anotherUser.address);
          const recipientBalanceAfterCollect = await currency.balanceOf(feeRecipient.address);
          const expectedReferralFee = DEFAULT_AMOUNT.mul(REFERRAL_FEE_BPS).div(BPS_MAX);
          const expectedRecipientFee = DEFAULT_AMOUNT.sub(expectedReferralFee);
          expect(treasuryBalanceAfterCollect).to.be.equals(treasuryBalanceBeforeCollect);
          expect(referrerBalanceAfterCollect).to.be.equals(
            referrerBalanceBeforeCollect.add(expectedReferralFee)
          );
          expect(recipientBalanceAfterCollect).to.be.equals(
            recipientBalanceBeforeCollect.add(expectedRecipientFee)
          );
          expect(
            recipientBalanceAfterCollect
              .sub(recipientBalanceBeforeCollect)
              .add(referrerBalanceAfterCollect)
              .sub(referrerBalanceBeforeCollect)
          ).to.be.equals(DEFAULT_AMOUNT);
        });

        it('No fees charged if collect amount was set to zero', async function () {
          const collectorBalanceBeforeCollect = await currency.balanceOf(user.address);
          const recipientBalanceBeforeCollect = await currency.balanceOf(feeRecipient.address);
          // Updates the parameters to set the collect amount to zero
          await expect(
            updatableOwnableFeeCollectModule
              .connect(publisher)
              .updateModuleParameters(
                FIRST_PROFILE_ID,
                FIRST_PUB_ID,
                ethers.constants.Zero,
                currency.address,
                feeRecipient.address,
                REFERRAL_FEE_BPS,
                false
              )
          ).to.not.be.reverted;
          // Collects the publication
          await expect(
            lensHub.connect(user).collect(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_COLLECT_DATA)
          ).to.not.be.reverted;
          const collectorBalanceAfterCollect = await currency.balanceOf(user.address);
          const recipientBalanceAfterCollect = await currency.balanceOf(feeRecipient.address);
          expect(recipientBalanceAfterCollect).to.be.equals(recipientBalanceBeforeCollect);
          expect(collectorBalanceAfterCollect).to.be.equals(collectorBalanceBeforeCollect);
        });
      });
    });
  });
});
