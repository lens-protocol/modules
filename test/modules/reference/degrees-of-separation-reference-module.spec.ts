import { BigNumber } from '@ethersproject/bignumber';
import '@nomiclabs/hardhat-ethers';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import {
  DegreesOfSeparationReferenceModule__factory,
  FollowNFT__factory,
} from '../../../typechain';
import { ERRORS } from '../../helpers/errors';
import {
  abiCoder,
  chainId,
  FIRST_PROFILE_ID,
  FIRST_PUB_ID,
  lensHub,
  makeSuiteCleanRoom,
  MOCK_FOLLOW_NFT_URI,
  MOCK_URI,
  anotherUser,
  user,
  deployer,
  degreesOfSeparationReferenceModule,
  thirdUser,
  freeCollectModule,
  FIRST_FOLLOW_NFT_ID,
  profileFollowModule,
} from './../../__setup.spec';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { publisher } from '../../__setup.spec';
import { getTimestamp, matchEvent, waitForTx } from '../../helpers/utils';
import { Domain } from '../../helpers/signatures/utils';
import { signUpdateModuleParametersWithSigMessage } from '../../helpers/signatures/modules/reference/degrees-of-separation-reference-module';

export let UPDATE_MODULE_PARAMETERS_WITH_SIG_DOMAIN: Domain;
export let DEFAULT_DEGREES_OF_SEPARATION: number;

makeSuiteCleanRoom('DegreesOfSeparationReferenceModule', function () {
  let ownerOfMirrorAuthor: SignerWithAddress;
  let ownerOfCommentAuthor: SignerWithAddress;
  let ownerOfFirstDegreeProfile: SignerWithAddress;
  let ownerOfSecondDegreeProfile: SignerWithAddress;
  const ROOT_AUTHOR_PROFILE: BigNumber = BigNumber.from(1);
  const FIRST_DEGREE_PROFILE: BigNumber = BigNumber.from(2);
  const SECOND_DEGREE_PROFILE: BigNumber = BigNumber.from(3);
  const COMMENTER_PROFILE: BigNumber = BigNumber.from(4);
  const MIRRORER_PROFILE: BigNumber = BigNumber.from(4);

  interface DegreesOfSeparationReferenceModuleInitData {
    commentsRestricted?: boolean;
    mirrorsRestricted?: boolean;
    degreesOfSeparation?: number;
  }

  async function getDegreesOfSeparationReferenceModuleInitData({
    commentsRestricted = true,
    mirrorsRestricted = true,
    degreesOfSeparation = DEFAULT_DEGREES_OF_SEPARATION,
  }: DegreesOfSeparationReferenceModuleInitData): Promise<string> {
    return abiCoder.encode(
      ['bool', 'bool', 'uint8'],
      [commentsRestricted, mirrorsRestricted, degreesOfSeparation]
    );
  }

  beforeEach(async function () {
    ownerOfMirrorAuthor = user;
    ownerOfCommentAuthor = user;
    ownerOfFirstDegreeProfile = anotherUser;
    ownerOfSecondDegreeProfile = thirdUser;
    UPDATE_MODULE_PARAMETERS_WITH_SIG_DOMAIN = {
      name: 'DegreesOfSeparationReferenceModule',
      version: '1',
      chainId: chainId,
      verifyingContract: degreesOfSeparationReferenceModule.address,
    };
    DEFAULT_DEGREES_OF_SEPARATION = 3;
    await expect(
      lensHub.createProfile({
        to: publisher.address,
        handle: 'rootpubauthor.lens',
        imageURI: MOCK_URI,
        followModule: ethers.constants.AddressZero,
        followModuleInitData: [],
        followNFTURI: MOCK_FOLLOW_NFT_URI,
      })
    ).to.not.be.reverted;
    await expect(
      lensHub.createProfile({
        to: ownerOfFirstDegreeProfile.address,
        handle: 'firstdegree.lens',
        imageURI: MOCK_URI,
        followModule: profileFollowModule.address,
        followModuleInitData: [],
        followNFTURI: MOCK_FOLLOW_NFT_URI,
      })
    ).to.not.be.reverted;
    await expect(
      lensHub.createProfile({
        to: ownerOfSecondDegreeProfile.address,
        handle: 'seconddegree.lens',
        imageURI: MOCK_URI,
        followModule: ethers.constants.AddressZero,
        followModuleInitData: [],
        followNFTURI: MOCK_FOLLOW_NFT_URI,
      })
    ).to.not.be.reverted;
    await expect(
      lensHub.createProfile({
        to: ownerOfCommentAuthor.address,
        handle: 'commentormirrorauthor.lens',
        imageURI: MOCK_URI,
        followModule: ethers.constants.AddressZero,
        followModuleInitData: [],
        followNFTURI: MOCK_FOLLOW_NFT_URI,
      })
    ).to.not.be.reverted;
  });

  context('DegreesOfSeparationReferenceModule', function () {
    context('Publication creation', function () {
      context('Negatives', function () {
        it('Initialization should fail if it is not called by the hub', async function () {
          await expect(
            degreesOfSeparationReferenceModule
              .connect(publisher)
              .initializeReferenceModule(
                FIRST_PROFILE_ID,
                FIRST_PUB_ID,
                await getDegreesOfSeparationReferenceModuleInitData({})
              )
          ).to.be.revertedWith(ERRORS.NOT_HUB);
        });

        it('User should fail to post if using wrong degrees of separation as init value', async function () {
          const invalidDegreesOfSeparation = 5;
          await expect(
            lensHub.connect(publisher).post({
              profileId: FIRST_PROFILE_ID,
              contentURI: MOCK_URI,
              collectModule: freeCollectModule.address,
              collectModuleInitData: abiCoder.encode(['bool'], [false]),
              referenceModule: degreesOfSeparationReferenceModule.address,
              referenceModuleInitData: await getDegreesOfSeparationReferenceModuleInitData({
                degreesOfSeparation: invalidDegreesOfSeparation,
              }),
            })
          ).to.be.revertedWith(ERRORS.INVALID_DEGREES_OF_SEPARATION);
        });

        it('User should fail to post passing data with wrong format', async function () {
          const wrongFormattedReferenceModuleInitData = abiCoder.encode(
            ['bool', 'uint8'],
            [true, DEFAULT_DEGREES_OF_SEPARATION]
          );
          await expect(
            lensHub.connect(publisher).post({
              profileId: FIRST_PROFILE_ID,
              contentURI: MOCK_URI,
              collectModule: freeCollectModule.address,
              collectModuleInitData: abiCoder.encode(['bool'], [false]),
              referenceModule: degreesOfSeparationReferenceModule.address,
              referenceModuleInitData: wrongFormattedReferenceModuleInitData,
            })
          ).to.be.reverted;
        });
      });

      context('Scenarios', function () {
        it('User should be able to create a publication when passing a valid data with valid degrees of separation number', async function () {
          const degreesOfSeparation = 4;
          await expect(
            lensHub.connect(publisher).post({
              profileId: FIRST_PROFILE_ID,
              contentURI: MOCK_URI,
              collectModule: freeCollectModule.address,
              collectModuleInitData: abiCoder.encode(['bool'], [false]),
              referenceModule: degreesOfSeparationReferenceModule.address,
              referenceModuleInitData: await getDegreesOfSeparationReferenceModuleInitData({
                degreesOfSeparation: degreesOfSeparation,
              }),
            })
          ).to.not.be.reverted;
          expect(
            await degreesOfSeparationReferenceModule.getModuleConfig(FIRST_PROFILE_ID, FIRST_PUB_ID)
          ).to.eqls([true, true, true, degreesOfSeparation]);
        });

        it('User should be able to create a publication even using zero as degrees of separation', async function () {
          const degreesOfSeparation = 0;
          await expect(
            lensHub.connect(publisher).post({
              profileId: FIRST_PROFILE_ID,
              contentURI: MOCK_URI,
              collectModule: freeCollectModule.address,
              collectModuleInitData: abiCoder.encode(['bool'], [false]),
              referenceModule: degreesOfSeparationReferenceModule.address,
              referenceModuleInitData: await getDegreesOfSeparationReferenceModuleInitData({
                degreesOfSeparation: degreesOfSeparation,
              }),
            })
          ).to.not.be.reverted;
          expect(
            await degreesOfSeparationReferenceModule.getModuleConfig(FIRST_PROFILE_ID, FIRST_PUB_ID)
          ).to.eqls([true, true, true, degreesOfSeparation]);
        });
      });
    });

    context('Update module parameters', function () {
      beforeEach(async function () {
        await expect(
          lensHub.connect(publisher).post({
            profileId: ROOT_AUTHOR_PROFILE,
            contentURI: MOCK_URI,
            collectModule: freeCollectModule.address,
            collectModuleInitData: abiCoder.encode(['bool'], [false]),
            referenceModule: degreesOfSeparationReferenceModule.address,
            referenceModuleInitData: await getDegreesOfSeparationReferenceModuleInitData({}),
          })
        ).not.be.reverted;
      });

      context('Negatives', function () {
        it('User should fail to update module parameters if he does not own the profile authoring the publication', async function () {
          await expect(
            degreesOfSeparationReferenceModule
              .connect(anotherUser)
              .updateModuleParameters(
                ROOT_AUTHOR_PROFILE,
                FIRST_PUB_ID,
                true,
                true,
                DEFAULT_DEGREES_OF_SEPARATION
              )
          ).to.be.revertedWith(ERRORS.NOT_PROFILE_OWNER);
        });

        it('User should fail to update module parameters if the publication is not using the degrees of separation reference module', async function () {
          await expect(
            degreesOfSeparationReferenceModule
              .connect(publisher)
              .updateModuleParameters(
                ROOT_AUTHOR_PROFILE,
                FIRST_PUB_ID + 1,
                true,
                true,
                DEFAULT_DEGREES_OF_SEPARATION
              )
          ).to.be.revertedWith(ERRORS.PUBLICATION_NOT_SET_UP);
        });

        it('User should fail to update module parameters if the passed degrees of separation exceeds the maximum allowed one', async function () {
          await expect(
            degreesOfSeparationReferenceModule
              .connect(publisher)
              .updateModuleParameters(ROOT_AUTHOR_PROFILE, FIRST_PUB_ID, true, true, 5)
          ).to.be.revertedWith(ERRORS.INVALID_DEGREES_OF_SEPARATION);
        });
      });

      context('Scenarios', function () {
        it('User should be able to update module parameters turning every restriction off', async function () {
          const tx = degreesOfSeparationReferenceModule
            .connect(publisher)
            .updateModuleParameters(ROOT_AUTHOR_PROFILE, FIRST_PUB_ID, false, false, 0);
          const txReceipt = await waitForTx(tx);
          // Verifies the expected event has been emited
          matchEvent(
            txReceipt,
            'ModuleParametersUpdated',
            [FIRST_PROFILE_ID, FIRST_PUB_ID, false, false, 0],
            degreesOfSeparationReferenceModule
          );
          expect(
            await degreesOfSeparationReferenceModule.getModuleConfig(FIRST_PROFILE_ID, FIRST_PUB_ID)
          ).to.eqls([true, false, false, 0]);
        });

        it('User should be able to update module parameters using maximum valid degree of separation', async function () {
          const maxDegreesOfSeparation = 4;
          const tx = degreesOfSeparationReferenceModule
            .connect(publisher)
            .updateModuleParameters(
              ROOT_AUTHOR_PROFILE,
              FIRST_PUB_ID,
              true,
              true,
              maxDegreesOfSeparation
            );
          const txReceipt = await waitForTx(tx);
          // Verifies the expected event has been emited
          matchEvent(
            txReceipt,
            'ModuleParametersUpdated',
            [FIRST_PROFILE_ID, FIRST_PUB_ID, true, true, maxDegreesOfSeparation],
            degreesOfSeparationReferenceModule
          );
          expect(
            await degreesOfSeparationReferenceModule.getModuleConfig(FIRST_PROFILE_ID, FIRST_PUB_ID)
          ).to.eqls([true, true, true, maxDegreesOfSeparation]);
        });
      });
    });

    context('Update module parameters with sig', function () {
      beforeEach(async function () {
        await expect(
          lensHub.connect(publisher).post({
            profileId: ROOT_AUTHOR_PROFILE,
            contentURI: MOCK_URI,
            collectModule: freeCollectModule.address,
            collectModuleInitData: abiCoder.encode(['bool'], [false]),
            referenceModule: degreesOfSeparationReferenceModule.address,
            referenceModuleInitData: await getDegreesOfSeparationReferenceModuleInitData({}),
          })
        ).not.be.reverted;
      });

      context('Negatives', function () {
        it('User should fail to update module params with sig if recovered signer does not match the expected one', async function () {
          const signature = await signUpdateModuleParametersWithSigMessage({
            signer: anotherUser,
          });
          await expect(
            degreesOfSeparationReferenceModule.updateModuleParametersWithSig(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID,
              true,
              true,
              COMMENTER_PROFILE,
              ownerOfCommentAuthor.address,
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
            degreesOfSeparationReferenceModule.updateModuleParametersWithSig(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID,
              true,
              true,
              DEFAULT_DEGREES_OF_SEPARATION,
              publisher.address,
              signature
            )
          ).to.be.revertedWith(ERRORS.SIGNATURE_EXPIRED);
        });

        it('User should fail to update module params with sig if signed message had wrong nonce', async function () {
          const currentNonce = await degreesOfSeparationReferenceModule.nonces(publisher.address);
          const invalidNonce = await currentNonce.add(5);
          const signature = await signUpdateModuleParametersWithSigMessage({
            signer: publisher,
            nonce: invalidNonce,
          });
          await expect(
            degreesOfSeparationReferenceModule.updateModuleParametersWithSig(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID,
              true,
              true,
              DEFAULT_DEGREES_OF_SEPARATION,
              publisher.address,
              signature
            )
          ).to.be.revertedWith(ERRORS.SIGNATURE_INVALID);
        });

        it('User should fail to update module params with sig if signed message domain had wrong version', async function () {
          const invalidVersion = '0';
          const invalidDomain: Domain = {
            name: 'DegreesOfSeparationReferenceModule',
            version: invalidVersion,
            chainId: chainId,
            verifyingContract: degreesOfSeparationReferenceModule.address,
          };
          const signature = await signUpdateModuleParametersWithSigMessage({
            signer: publisher,
            domain: invalidDomain,
          });
          await expect(
            degreesOfSeparationReferenceModule.updateModuleParametersWithSig(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID,
              true,
              true,
              DEFAULT_DEGREES_OF_SEPARATION,
              publisher.address,
              signature
            )
          ).to.be.revertedWith(ERRORS.SIGNATURE_INVALID);
        });

        it('User should fail to update module params with sig if signed message domain had wrong chain ID', async function () {
          const invalidChainId = 69;
          expect(chainId).to.not.equals(invalidChainId);
          const invalidDomain: Domain = {
            name: 'DegreesOfSeparationReferenceModule',
            version: '1',
            chainId: invalidChainId,
            verifyingContract: degreesOfSeparationReferenceModule.address,
          };
          const signature = await signUpdateModuleParametersWithSigMessage({
            signer: publisher,
            domain: invalidDomain,
          });
          await expect(
            degreesOfSeparationReferenceModule.updateModuleParametersWithSig(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID,
              true,
              true,
              DEFAULT_DEGREES_OF_SEPARATION,
              publisher.address,
              signature
            )
          ).to.be.revertedWith(ERRORS.SIGNATURE_INVALID);
        });

        it('User should fail to update module params with sig if signed message domain had wrong verifying contract', async function () {
          const invalidVerifyingContract = (
            await new DegreesOfSeparationReferenceModule__factory(deployer).deploy(lensHub.address)
          ).address;
          const invalidDomain: Domain = {
            name: 'DegreesOfSeparationReferenceModule',
            version: '1',
            chainId: chainId,
            verifyingContract: invalidVerifyingContract,
          };
          const signature = await signUpdateModuleParametersWithSigMessage({
            signer: publisher,
            domain: invalidDomain,
          });
          await expect(
            degreesOfSeparationReferenceModule.updateModuleParametersWithSig(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID,
              true,
              true,
              DEFAULT_DEGREES_OF_SEPARATION,
              publisher.address,
              signature
            )
          ).to.be.revertedWith(ERRORS.SIGNATURE_INVALID);
        });

        it('User should fail to update module params with sig if signed message domain had wrong name', async function () {
          const invalidName = 'Degrees Of Separation Reference Module';
          const invalidDomain: Domain = {
            name: invalidName,
            version: '1',
            chainId: chainId,
            verifyingContract: degreesOfSeparationReferenceModule.address,
          };
          const signature = await signUpdateModuleParametersWithSigMessage({
            signer: publisher,
            domain: invalidDomain,
          });
          await expect(
            degreesOfSeparationReferenceModule.updateModuleParametersWithSig(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID,
              true,
              true,
              DEFAULT_DEGREES_OF_SEPARATION,
              publisher.address,
              signature
            )
          ).to.be.revertedWith(ERRORS.SIGNATURE_INVALID);
        });

        it('User should fail to update module parameters if he does not own the profile authoring the publication', async function () {
          const signature = await signUpdateModuleParametersWithSigMessage({
            signer: anotherUser,
          });
          await expect(
            degreesOfSeparationReferenceModule.updateModuleParametersWithSig(
              ROOT_AUTHOR_PROFILE,
              FIRST_PUB_ID,
              true,
              true,
              DEFAULT_DEGREES_OF_SEPARATION,
              anotherUser.address,
              signature
            )
          ).to.be.revertedWith(ERRORS.NOT_PROFILE_OWNER);
        });

        it('User should fail to update module parameters if the publication is not using the degrees of separation reference module', async function () {
          const signature = await signUpdateModuleParametersWithSigMessage({
            signer: publisher,
            pubId: FIRST_PUB_ID + 1,
          });
          await expect(
            degreesOfSeparationReferenceModule.updateModuleParametersWithSig(
              ROOT_AUTHOR_PROFILE,
              FIRST_PUB_ID + 1,
              true,
              true,
              DEFAULT_DEGREES_OF_SEPARATION,
              publisher.address,
              signature
            )
          ).to.be.revertedWith(ERRORS.PUBLICATION_NOT_SET_UP);
        });

        it('User should fail to update module parameters if the passed degrees of separation exceeds the maximum allowed one', async function () {
          const signature = await signUpdateModuleParametersWithSigMessage({
            signer: publisher,
            degreesOfSeparation: 5,
          });
          await expect(
            degreesOfSeparationReferenceModule.updateModuleParametersWithSig(
              ROOT_AUTHOR_PROFILE,
              FIRST_PUB_ID,
              true,
              true,
              5,
              publisher.address,
              signature
            )
          ).to.be.revertedWith(ERRORS.INVALID_DEGREES_OF_SEPARATION);
        });
      });

      context('Scenarios', function () {
        it('User should be able to update module parameters turning every restriction off', async function () {
          const signature = await signUpdateModuleParametersWithSigMessage({
            signer: publisher,
            commentsRestricted: false,
            mirrorsRestricted: false,
            degreesOfSeparation: 0,
          });
          const tx = degreesOfSeparationReferenceModule.updateModuleParametersWithSig(
            ROOT_AUTHOR_PROFILE,
            FIRST_PUB_ID,
            false,
            false,
            0,
            publisher.address,
            signature
          );
          const txReceipt = await waitForTx(tx);
          // Verifies the expected event has been emited
          matchEvent(
            txReceipt,
            'ModuleParametersUpdated',
            [FIRST_PROFILE_ID, FIRST_PUB_ID, false, false, 0],
            degreesOfSeparationReferenceModule
          );
          expect(
            await degreesOfSeparationReferenceModule.getModuleConfig(FIRST_PROFILE_ID, FIRST_PUB_ID)
          ).to.eqls([true, false, false, 0]);
        });

        it('User should be able to update module parameters using maximum valid degree of separation', async function () {
          const maxDegreesOfSeparation = 4;
          const signature = await signUpdateModuleParametersWithSigMessage({
            signer: publisher,
            degreesOfSeparation: maxDegreesOfSeparation,
          });
          const tx = degreesOfSeparationReferenceModule.updateModuleParametersWithSig(
            ROOT_AUTHOR_PROFILE,
            FIRST_PUB_ID,
            true,
            true,
            maxDegreesOfSeparation,
            publisher.address,
            signature
          );
          const txReceipt = await waitForTx(tx);
          // Verifies the expected event has been emited
          matchEvent(
            txReceipt,
            'ModuleParametersUpdated',
            [FIRST_PROFILE_ID, FIRST_PUB_ID, true, true, maxDegreesOfSeparation],
            degreesOfSeparationReferenceModule
          );
          expect(
            await degreesOfSeparationReferenceModule.getModuleConfig(FIRST_PROFILE_ID, FIRST_PUB_ID)
          ).to.eqls([true, true, true, maxDegreesOfSeparation]);
        });
      });
    });

    context('Process comment', function () {
      beforeEach(async function () {
        await expect(
          lensHub
            .connect(publisher)
            .follow([FIRST_DEGREE_PROFILE], [abiCoder.encode(['uint256'], [ROOT_AUTHOR_PROFILE])])
        ).to.not.be.reverted;
        await expect(
          lensHub.connect(ownerOfFirstDegreeProfile).follow([SECOND_DEGREE_PROFILE], [[]])
        ).to.not.be.reverted;
        await expect(
          lensHub.connect(ownerOfSecondDegreeProfile).follow([COMMENTER_PROFILE], [[]])
        ).to.not.be.reverted;
        await expect(
          lensHub.connect(publisher).post({
            profileId: ROOT_AUTHOR_PROFILE,
            contentURI: MOCK_URI,
            collectModule: freeCollectModule.address,
            collectModuleInitData: abiCoder.encode(['bool'], [false]),
            referenceModule: degreesOfSeparationReferenceModule.address,
            referenceModuleInitData: await getDegreesOfSeparationReferenceModuleInitData({}),
          })
        ).not.be.reverted;
      });

      context('Negatives', function () {
        it('Process comment should fail if it is not called by the hub', async function () {
          await expect(
            degreesOfSeparationReferenceModule
              .connect(ownerOfFirstDegreeProfile)
              .processComment(
                FIRST_DEGREE_PROFILE,
                FIRST_PROFILE_ID,
                FIRST_PUB_ID,
                await getDegreesOfSeparationReferenceModuleInitData({})
              )
          ).to.be.revertedWith(ERRORS.NOT_HUB);
        });

        it('User should fail to comment when degrees of separation is set as zero', async function () {
          await expect(
            degreesOfSeparationReferenceModule
              .connect(publisher)
              .updateModuleParameters(ROOT_AUTHOR_PROFILE, FIRST_PUB_ID, true, true, 0)
          ).to.not.be.reverted;
          await expect(
            lensHub.connect(ownerOfFirstDegreeProfile).comment({
              profileId: FIRST_DEGREE_PROFILE,
              contentURI: MOCK_URI,
              profileIdPointed: ROOT_AUTHOR_PROFILE,
              pubIdPointed: FIRST_PROFILE_ID,
              referenceModuleData: abiCoder.encode(['uint256[]'], [[]]),
              collectModule: freeCollectModule.address,
              collectModuleInitData: abiCoder.encode(['bool'], [false]),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.be.revertedWith(ERRORS.OPERATION_DISABLED);
        });

        it('User should fail to comment when passing a profile path which length exceeds the configured degrees of separation', async function () {
          await expect(
            degreesOfSeparationReferenceModule
              .connect(publisher)
              .updateModuleParameters(ROOT_AUTHOR_PROFILE, FIRST_PUB_ID, true, true, 1)
          ).to.not.be.reverted;
          await expect(
            lensHub.connect(ownerOfSecondDegreeProfile).comment({
              profileId: SECOND_DEGREE_PROFILE,
              contentURI: MOCK_URI,
              profileIdPointed: ROOT_AUTHOR_PROFILE,
              pubIdPointed: FIRST_PROFILE_ID,
              referenceModuleData: abiCoder.encode(['uint256[]'], [[FIRST_DEGREE_PROFILE]]),
              collectModule: freeCollectModule.address,
              collectModuleInitData: abiCoder.encode(['bool'], [false]),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.be.revertedWith(ERRORS.PROFILE_PATH_EXCEEDS_DEGREES_OF_SEPARATION);
        });

        it('User should fail to comment if the owner of the root publication author does not follow the first profile in the path', async function () {
          await expect(
            lensHub.connect(ownerOfCommentAuthor).comment({
              profileId: COMMENTER_PROFILE,
              contentURI: MOCK_URI,
              profileIdPointed: ROOT_AUTHOR_PROFILE,
              pubIdPointed: FIRST_PROFILE_ID,
              referenceModuleData: abiCoder.encode(['uint256[]'], [[SECOND_DEGREE_PROFILE]]),
              collectModule: freeCollectModule.address,
              collectModuleInitData: abiCoder.encode(['bool'], [false]),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.be.revertedWith(ERRORS.FOLLOW_INVALID);
        });

        it('User should fail to comment if the owner of the last profile in the path does not follow the profile authoring the comment', async function () {
          await expect(
            lensHub.connect(ownerOfCommentAuthor).comment({
              profileId: COMMENTER_PROFILE,
              contentURI: MOCK_URI,
              profileIdPointed: ROOT_AUTHOR_PROFILE,
              pubIdPointed: FIRST_PROFILE_ID,
              referenceModuleData: abiCoder.encode(['uint256[]'], [[FIRST_DEGREE_PROFILE]]),
              collectModule: freeCollectModule.address,
              collectModuleInitData: abiCoder.encode(['bool'], [false]),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.be.revertedWith(ERRORS.FOLLOW_INVALID);
        });

        it('User should fail to comment if at least one of the owners of one profile in the path is not following', async function () {
          const followNftAddress = await lensHub.getFollowNFT(SECOND_DEGREE_PROFILE);
          await expect(
            FollowNFT__factory.connect(followNftAddress, ownerOfFirstDegreeProfile).burn(
              FIRST_FOLLOW_NFT_ID
            )
          ).to.not.be.reverted;
          await expect(
            lensHub.connect(ownerOfCommentAuthor).comment({
              profileId: COMMENTER_PROFILE,
              contentURI: MOCK_URI,
              profileIdPointed: ROOT_AUTHOR_PROFILE,
              pubIdPointed: FIRST_PROFILE_ID,
              referenceModuleData: abiCoder.encode(
                ['uint256[]'],
                [[FIRST_DEGREE_PROFILE, SECOND_DEGREE_PROFILE]]
              ),
              collectModule: freeCollectModule.address,
              collectModuleInitData: abiCoder.encode(['bool'], [false]),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.be.revertedWith(ERRORS.FOLLOW_INVALID);
        });

        it('User should fail to comment if passed as one degree of separation but it is not followed by the author of root publication', async function () {
          await expect(
            lensHub.connect(ownerOfSecondDegreeProfile).mirror({
              profileId: SECOND_DEGREE_PROFILE,
              profileIdPointed: ROOT_AUTHOR_PROFILE,
              pubIdPointed: FIRST_PROFILE_ID,
              referenceModuleData: abiCoder.encode(['uint256[]'], [[]]),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.be.revertedWith(ERRORS.FOLLOW_INVALID);
        });
      });

      context('Scenarios', function () {
        it('User should be able to comment if restrictions are disabled for the comment operation', async function () {
          await expect(
            degreesOfSeparationReferenceModule
              .connect(publisher)
              .updateModuleParameters(
                ROOT_AUTHOR_PROFILE,
                FIRST_PUB_ID,
                false,
                true,
                DEFAULT_DEGREES_OF_SEPARATION
              )
          ).to.not.be.reverted;
          expect(await lensHub.getFollowNFT(ROOT_AUTHOR_PROFILE)).to.equal(
            ethers.constants.AddressZero
          );
          await expect(
            lensHub.connect(ownerOfCommentAuthor).comment({
              profileId: COMMENTER_PROFILE,
              contentURI: MOCK_URI,
              profileIdPointed: ROOT_AUTHOR_PROFILE,
              pubIdPointed: FIRST_PROFILE_ID,
              referenceModuleData: [],
              collectModule: freeCollectModule.address,
              collectModuleInitData: abiCoder.encode(['bool'], [false]),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.not.be.reverted;
        });

        it('User should be able to comment if he is the exact same degrees of separation as the configured restriction from the author of root publication', async function () {
          await expect(
            lensHub.connect(ownerOfCommentAuthor).comment({
              profileId: COMMENTER_PROFILE,
              contentURI: MOCK_URI,
              profileIdPointed: ROOT_AUTHOR_PROFILE,
              pubIdPointed: FIRST_PROFILE_ID,
              referenceModuleData: abiCoder.encode(
                ['uint256[]'],
                [[FIRST_DEGREE_PROFILE, SECOND_DEGREE_PROFILE]]
              ),
              collectModule: freeCollectModule.address,
              collectModuleInitData: abiCoder.encode(['bool'], [false]),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.not.be.reverted;
        });

        it('User should be able to comment if he is in less degrees of separation as the configured restriction from the author of root publication', async function () {
          await expect(
            lensHub.connect(ownerOfSecondDegreeProfile).comment({
              profileId: SECOND_DEGREE_PROFILE,
              contentURI: MOCK_URI,
              profileIdPointed: ROOT_AUTHOR_PROFILE,
              pubIdPointed: FIRST_PROFILE_ID,
              referenceModuleData: abiCoder.encode(['uint256[]'], [[FIRST_DEGREE_PROFILE]]),
              collectModule: freeCollectModule.address,
              collectModuleInitData: abiCoder.encode(['bool'], [false]),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.not.be.reverted;
        });

        it('User should be able to comment if he is one degree of separation from the author of root publication', async function () {
          await expect(
            lensHub.connect(ownerOfFirstDegreeProfile).comment({
              profileId: FIRST_DEGREE_PROFILE,
              contentURI: MOCK_URI,
              profileIdPointed: ROOT_AUTHOR_PROFILE,
              pubIdPointed: FIRST_PROFILE_ID,
              referenceModuleData: abiCoder.encode(['uint256[]'], [[]]),
              collectModule: freeCollectModule.address,
              collectModuleInitData: abiCoder.encode(['bool'], [false]),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.not.be.reverted;
        });

        it('User should be able to comment if he the author of root publication', async function () {
          await expect(
            lensHub.connect(publisher).comment({
              profileId: ROOT_AUTHOR_PROFILE,
              contentURI: MOCK_URI,
              profileIdPointed: ROOT_AUTHOR_PROFILE,
              pubIdPointed: FIRST_PROFILE_ID,
              referenceModuleData: abiCoder.encode(['uint256[]'], [[]]),
              collectModule: freeCollectModule.address,
              collectModuleInitData: abiCoder.encode(['bool'], [false]),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.not.be.reverted;
        });
      });
    });

    context('Process mirror', function () {
      beforeEach(async function () {
        await expect(
          lensHub
            .connect(publisher)
            .follow([FIRST_DEGREE_PROFILE], [abiCoder.encode(['uint256'], [ROOT_AUTHOR_PROFILE])])
        ).to.not.be.reverted;
        await expect(
          lensHub.connect(ownerOfFirstDegreeProfile).follow([SECOND_DEGREE_PROFILE], [[]])
        ).to.not.be.reverted;
        await expect(
          lensHub.connect(ownerOfSecondDegreeProfile).follow([MIRRORER_PROFILE], [[]])
        ).to.not.be.reverted;
        await expect(
          lensHub.connect(publisher).post({
            profileId: ROOT_AUTHOR_PROFILE,
            contentURI: MOCK_URI,
            collectModule: freeCollectModule.address,
            collectModuleInitData: abiCoder.encode(['bool'], [false]),
            referenceModule: degreesOfSeparationReferenceModule.address,
            referenceModuleInitData: await getDegreesOfSeparationReferenceModuleInitData({}),
          })
        ).not.be.reverted;
      });

      context('Negatives', function () {
        it('Process mirror should fail if it is not called by the hub', async function () {
          await expect(
            degreesOfSeparationReferenceModule
              .connect(ownerOfFirstDegreeProfile)
              .processComment(
                FIRST_DEGREE_PROFILE,
                FIRST_PROFILE_ID,
                FIRST_PUB_ID,
                await getDegreesOfSeparationReferenceModuleInitData({})
              )
          ).to.be.revertedWith(ERRORS.NOT_HUB);
        });

        it('User should fail to mirror when degrees of separation is set as zero', async function () {
          await expect(
            degreesOfSeparationReferenceModule
              .connect(publisher)
              .updateModuleParameters(ROOT_AUTHOR_PROFILE, FIRST_PUB_ID, true, true, 0)
          ).to.not.be.reverted;
          await expect(
            lensHub.connect(ownerOfFirstDegreeProfile).mirror({
              profileId: FIRST_DEGREE_PROFILE,
              profileIdPointed: ROOT_AUTHOR_PROFILE,
              pubIdPointed: FIRST_PROFILE_ID,
              referenceModuleData: abiCoder.encode(['uint256[]'], [[]]),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.be.revertedWith(ERRORS.OPERATION_DISABLED);
        });

        it('User should fail to mirror when passing a profile path which length exceeds the configured degrees of separation', async function () {
          await expect(
            degreesOfSeparationReferenceModule
              .connect(publisher)
              .updateModuleParameters(ROOT_AUTHOR_PROFILE, FIRST_PUB_ID, true, true, 1)
          ).to.not.be.reverted;
          await expect(
            lensHub.connect(ownerOfSecondDegreeProfile).mirror({
              profileId: SECOND_DEGREE_PROFILE,
              profileIdPointed: ROOT_AUTHOR_PROFILE,
              pubIdPointed: FIRST_PROFILE_ID,
              referenceModuleData: abiCoder.encode(['uint256[]'], [[FIRST_DEGREE_PROFILE]]),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.be.revertedWith(ERRORS.PROFILE_PATH_EXCEEDS_DEGREES_OF_SEPARATION);
        });

        it('User should fail to mirror if the owner of the root publication author does not follow the first profile in the path', async function () {
          await expect(
            lensHub.connect(ownerOfMirrorAuthor).mirror({
              profileId: MIRRORER_PROFILE,
              profileIdPointed: ROOT_AUTHOR_PROFILE,
              pubIdPointed: FIRST_PROFILE_ID,
              referenceModuleData: abiCoder.encode(['uint256[]'], [[SECOND_DEGREE_PROFILE]]),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.be.revertedWith(ERRORS.FOLLOW_INVALID);
        });

        it('User should fail to mirror if the owner of the last profile in the path does not follow the profile authoring the mirror', async function () {
          await expect(
            lensHub.connect(ownerOfMirrorAuthor).mirror({
              profileId: MIRRORER_PROFILE,
              profileIdPointed: ROOT_AUTHOR_PROFILE,
              pubIdPointed: FIRST_PROFILE_ID,
              referenceModuleData: abiCoder.encode(['uint256[]'], [[FIRST_DEGREE_PROFILE]]),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.be.revertedWith(ERRORS.FOLLOW_INVALID);
        });

        it('User should fail to mirror if at least one of the owners of one profile in the path is not following', async function () {
          const followNftAddress = await lensHub.getFollowNFT(SECOND_DEGREE_PROFILE);
          await expect(
            FollowNFT__factory.connect(followNftAddress, ownerOfFirstDegreeProfile).burn(
              FIRST_FOLLOW_NFT_ID
            )
          ).to.not.be.reverted;
          await expect(
            lensHub.connect(ownerOfMirrorAuthor).mirror({
              profileId: MIRRORER_PROFILE,
              profileIdPointed: ROOT_AUTHOR_PROFILE,
              pubIdPointed: FIRST_PROFILE_ID,
              referenceModuleData: abiCoder.encode(
                ['uint256[]'],
                [[FIRST_DEGREE_PROFILE, SECOND_DEGREE_PROFILE]]
              ),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.be.revertedWith(ERRORS.FOLLOW_INVALID);
        });

        it('User should fail to mirror if passed as one degree of separation but it is not followed by the author of root publication', async function () {
          await expect(
            lensHub.connect(ownerOfSecondDegreeProfile).mirror({
              profileId: SECOND_DEGREE_PROFILE,
              profileIdPointed: ROOT_AUTHOR_PROFILE,
              pubIdPointed: FIRST_PROFILE_ID,
              referenceModuleData: abiCoder.encode(['uint256[]'], [[]]),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.be.revertedWith(ERRORS.FOLLOW_INVALID);
        });
      });

      context('Scenarios', function () {
        it('User should be able to mirror if restrictions are disabled for the mirror operation', async function () {
          await expect(
            degreesOfSeparationReferenceModule
              .connect(publisher)
              .updateModuleParameters(
                ROOT_AUTHOR_PROFILE,
                FIRST_PUB_ID,
                true,
                false,
                DEFAULT_DEGREES_OF_SEPARATION
              )
          ).to.not.be.reverted;
          expect(await lensHub.getFollowNFT(ROOT_AUTHOR_PROFILE)).to.equal(
            ethers.constants.AddressZero
          );
          await expect(
            lensHub.connect(ownerOfMirrorAuthor).mirror({
              profileId: MIRRORER_PROFILE,
              profileIdPointed: ROOT_AUTHOR_PROFILE,
              pubIdPointed: FIRST_PROFILE_ID,
              referenceModuleData: [],
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.not.be.reverted;
        });

        it('User should be able to mirror if he is the exact same degrees of separation as the configured restriction from the author of root publication', async function () {
          await expect(
            lensHub.connect(ownerOfMirrorAuthor).mirror({
              profileId: MIRRORER_PROFILE,
              profileIdPointed: ROOT_AUTHOR_PROFILE,
              pubIdPointed: FIRST_PROFILE_ID,
              referenceModuleData: abiCoder.encode(
                ['uint256[]'],
                [[FIRST_DEGREE_PROFILE, SECOND_DEGREE_PROFILE]]
              ),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.not.be.reverted;
        });

        it('User should be able to mirror if he is in less degrees of separation as the configured restriction from the author of root publication', async function () {
          await expect(
            lensHub.connect(ownerOfSecondDegreeProfile).mirror({
              profileId: SECOND_DEGREE_PROFILE,
              profileIdPointed: ROOT_AUTHOR_PROFILE,
              pubIdPointed: FIRST_PROFILE_ID,
              referenceModuleData: abiCoder.encode(['uint256[]'], [[FIRST_DEGREE_PROFILE]]),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.not.be.reverted;
        });

        it('User should be able to mirror if he is one degree of separation from the author of root publication', async function () {
          await expect(
            lensHub.connect(ownerOfFirstDegreeProfile).mirror({
              profileId: FIRST_DEGREE_PROFILE,
              profileIdPointed: ROOT_AUTHOR_PROFILE,
              pubIdPointed: FIRST_PROFILE_ID,
              referenceModuleData: abiCoder.encode(['uint256[]'], [[]]),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.not.be.reverted;
        });

        it('User should be able to mirror if he is the author of root publication', async function () {
          await expect(
            lensHub.connect(publisher).mirror({
              profileId: ROOT_AUTHOR_PROFILE,
              profileIdPointed: ROOT_AUTHOR_PROFILE,
              pubIdPointed: FIRST_PROFILE_ID,
              referenceModuleData: abiCoder.encode(['uint256[]'], [[]]),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.not.be.reverted;
        });
      });
    });
  });
});
