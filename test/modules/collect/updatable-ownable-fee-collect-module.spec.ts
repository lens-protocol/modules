import { BigNumber, BigNumberish } from '@ethersproject/bignumber';
import { parseEther } from '@ethersproject/units';
import '@nomiclabs/hardhat-ethers';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import { FollowNFT__factory, UpdatableOwnableFeeCollectModule__factory } from '../../../typechain';
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
  freeCollectModule,
  lensHub,
  makeSuiteCleanRoom,
  MOCK_FOLLOW_NFT_URI,
  MOCK_PROFILE_HANDLE,
  MOCK_URI,
  moduleGlobals,
  anotherUser,
  REFERRAL_FEE_BPS,
  user,
  FIRST_FOLLOW_NFT_ID,
  deployer,
  thirdUser,
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

export let UPDATE_MODULE_PARAMETERS_WITH_SIG_DOMAIN: Domain;

makeSuiteCleanRoom('UpdatableOwnableFeeCollectModule', function () {
  const FIRST_TOKEN_ID = ethers.constants.One;

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
  });
});
