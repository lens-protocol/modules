import { BigNumber } from '@ethersproject/bignumber';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import { ERRORS } from '../../helpers/errors';
import {
  lensHub,
  abiCoder,
  makeSuiteCleanRoom,
  nft,
  user,
  publisher,
  MOCK_PROFILE_HANDLE,
  MOCK_URI,
  MOCK_FOLLOW_NFT_URI,
  FIRST_PROFILE_ID,
  FIRST_PUB_ID,
  tokenGatedReferenceModule,
  freeCollectModule,
  currency,
  OTHER_MOCK_URI,
} from '../../__setup.spec';
import { matchEvent, waitForTx } from '../../helpers/utils';
import { parseEther } from '@ethersproject/units';

makeSuiteCleanRoom('TokenGatedReferenceModule', function () {
  const SECOND_PROFILE_ID = FIRST_PROFILE_ID + 1;

  interface TokenGatedReferenceModuleInitData {
    tokenAddress: string;
    minThreshold: BigNumber;
  }

  async function getTokenGatedReferenceModuleInitData({
    tokenAddress = nft.address,
    minThreshold = BigNumber.from(1),
  }: TokenGatedReferenceModuleInitData): Promise<string> {
    return abiCoder.encode(['address', 'uint256'], [tokenAddress, minThreshold]);
  }

  beforeEach(async function () {
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
    await expect(
      lensHub.createProfile({
        to: user.address,
        handle: 'user',
        imageURI: OTHER_MOCK_URI,
        followModule: ethers.constants.AddressZero,
        followModuleInitData: [],
        followNFTURI: MOCK_FOLLOW_NFT_URI,
      })
    ).to.not.be.reverted;
  });

  context('Publication creation', function () {
    context('Negatives', function () {
      it('User should fail to post setting zero token address', async function () {
        const referenceModuleInitData = await getTokenGatedReferenceModuleInitData({
          tokenAddress: ethers.constants.AddressZero,
          minThreshold: BigNumber.from(1),
        });
        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: freeCollectModule.address,
            collectModuleInitData: abiCoder.encode(['bool'], [true]),
            referenceModule: tokenGatedReferenceModule.address,
            referenceModuleInitData: referenceModuleInitData,
          })
        ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
      });
      it('User should fail to post setting zero minThreshold', async function () {
        const referenceModuleInitData = await getTokenGatedReferenceModuleInitData({
          tokenAddress: currency.address,
          minThreshold: ethers.constants.Zero,
        });
        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: freeCollectModule.address,
            collectModuleInitData: abiCoder.encode(['bool'], [true]),
            referenceModule: tokenGatedReferenceModule.address,
            referenceModuleInitData: referenceModuleInitData,
          })
        ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
      });
    });

    context('Scenarios', function () {
      it('User should succeed to create a publication when all parameters are valid and tx should emit expected event', async function () {
        const referenceModuleInitData = await getTokenGatedReferenceModuleInitData({
          tokenAddress: currency.address,
          minThreshold: BigNumber.from(1),
        });
        const tx = lensHub.connect(publisher).post({
          profileId: FIRST_PROFILE_ID,
          contentURI: MOCK_URI,
          collectModule: freeCollectModule.address,
          collectModuleInitData: abiCoder.encode(['bool'], [true]),
          referenceModule: tokenGatedReferenceModule.address,
          referenceModuleInitData: referenceModuleInitData,
        });
        const txReceipt = await waitForTx(tx);
        matchEvent(
          txReceipt,
          'TokenGatedReferencePublicationCreated',
          [FIRST_PROFILE_ID, FIRST_PUB_ID, currency.address, BigNumber.from(1)],
          tokenGatedReferenceModule
        );
      });
    });
  });

  context('ERC20 Gated Reference', function () {
    let referenceModuleInitData;
    const minThreshold = parseEther('10');

    beforeEach(async function () {
      referenceModuleInitData = await getTokenGatedReferenceModuleInitData({
        tokenAddress: currency.address,
        minThreshold,
      });
      await expect(
        lensHub.connect(publisher).post({
          profileId: FIRST_PROFILE_ID,
          contentURI: MOCK_URI,
          collectModule: freeCollectModule.address,
          collectModuleInitData: abiCoder.encode(['bool'], [true]),
          referenceModule: tokenGatedReferenceModule.address,
          referenceModuleInitData: referenceModuleInitData,
        })
      ).to.not.be.reverted;
    });

    context('Negatives', function () {
      it('User should fail to mirror if they dont hold enough gating tokens', async function () {
        expect(await currency.balanceOf(user.address)).to.be.lt(minThreshold);

        await expect(
          lensHub.connect(user).mirror({
            profileId: SECOND_PROFILE_ID,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: FIRST_PUB_ID,
            referenceModuleData: '0x',
            referenceModule: tokenGatedReferenceModule.address,
            referenceModuleInitData: referenceModuleInitData,
          })
        ).to.be.revertedWith(ERRORS.NOT_ENOUGH_BALANCE);
      });

      it('User should fail to comment if they dont hold enough gating tokens', async function () {
        expect(await currency.balanceOf(user.address)).to.be.lt(minThreshold);
        await expect(
          lensHub.connect(user).comment({
            profileId: SECOND_PROFILE_ID,
            contentURI: MOCK_URI,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: FIRST_PUB_ID,
            collectModule: freeCollectModule.address,
            collectModuleInitData: abiCoder.encode(['bool'], [true]),
            referenceModuleData: '0x',
            referenceModule: tokenGatedReferenceModule.address,
            referenceModuleInitData: referenceModuleInitData,
          })
        ).to.be.revertedWith(ERRORS.NOT_ENOUGH_BALANCE);
      });
    });

    context('Scenarios', function () {
      it('Mirroring should work if mirrorer holds enough gating tokens', async function () {
        await currency.mint(user.address, minThreshold);
        expect(await currency.balanceOf(user.address)).to.be.gte(minThreshold);

        await expect(
          lensHub.connect(user).mirror({
            profileId: SECOND_PROFILE_ID,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: FIRST_PUB_ID,
            referenceModuleData: '0x',
            referenceModule: tokenGatedReferenceModule.address,
            referenceModuleInitData: referenceModuleInitData,
          })
        ).to.not.be.reverted;
      });

      it('Commenting should work if commenter holds enough gating tokens', async function () {
        await currency.mint(user.address, minThreshold);
        expect(await currency.balanceOf(user.address)).to.be.gte(minThreshold);

        await expect(
          lensHub.connect(user).comment({
            profileId: SECOND_PROFILE_ID,
            contentURI: MOCK_URI,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: FIRST_PUB_ID,
            collectModule: freeCollectModule.address,
            collectModuleInitData: abiCoder.encode(['bool'], [true]),
            referenceModuleData: '0x',
            referenceModule: tokenGatedReferenceModule.address,
            referenceModuleInitData: referenceModuleInitData,
          })
        ).to.not.be.reverted;
      });
    });
  });

  context('ERC721 Gated Reference', function () {
    let referenceModuleInitData;
    const minThreshold = BigNumber.from(1);

    beforeEach(async function () {
      referenceModuleInitData = await getTokenGatedReferenceModuleInitData({
        tokenAddress: nft.address,
        minThreshold,
      });
      await expect(
        lensHub.connect(publisher).post({
          profileId: FIRST_PROFILE_ID,
          contentURI: MOCK_URI,
          collectModule: freeCollectModule.address,
          collectModuleInitData: abiCoder.encode(['bool'], [true]),
          referenceModule: tokenGatedReferenceModule.address,
          referenceModuleInitData: referenceModuleInitData,
        })
      ).to.not.be.reverted;
    });

    context('Negatives', function () {
      it('User should fail to mirror if they dont hold enough gating tokens', async function () {
        expect(await nft.balanceOf(user.address)).to.be.lt(minThreshold);

        await expect(
          lensHub.connect(user).mirror({
            profileId: SECOND_PROFILE_ID,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: FIRST_PUB_ID,
            referenceModuleData: '0x',
            referenceModule: tokenGatedReferenceModule.address,
            referenceModuleInitData: referenceModuleInitData,
          })
        ).to.be.revertedWith(ERRORS.NOT_ENOUGH_BALANCE);
      });

      it('User should fail to comment if they dont hold enough gating tokens', async function () {
        expect(await nft.balanceOf(user.address)).to.be.lt(minThreshold);

        await expect(
          lensHub.connect(user).comment({
            profileId: SECOND_PROFILE_ID,
            contentURI: MOCK_URI,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: FIRST_PUB_ID,
            collectModule: freeCollectModule.address,
            collectModuleInitData: abiCoder.encode(['bool'], [true]),
            referenceModuleData: '0x',
            referenceModule: tokenGatedReferenceModule.address,
            referenceModuleInitData: referenceModuleInitData,
          })
        ).to.be.revertedWith(ERRORS.NOT_ENOUGH_BALANCE);
      });
    });

    context('Scenarios', function () {
      it('Mirroring should work if mirrorer holds enough gating tokens', async function () {
        await nft.mint(user.address, 1);

        expect(await nft.balanceOf(user.address)).to.be.gte(minThreshold);

        await expect(
          lensHub.connect(user).mirror({
            profileId: SECOND_PROFILE_ID,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: FIRST_PUB_ID,
            referenceModuleData: '0x',
            referenceModule: tokenGatedReferenceModule.address,
            referenceModuleInitData: referenceModuleInitData,
          })
        ).to.not.be.reverted;
      });

      it('Commenting should work if commenter holds enough gating tokens', async function () {
        await nft.mint(user.address, 1);

        expect(await nft.balanceOf(user.address)).to.be.gte(minThreshold);

        await expect(
          lensHub.connect(user).comment({
            profileId: SECOND_PROFILE_ID,
            contentURI: MOCK_URI,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: FIRST_PUB_ID,
            collectModule: freeCollectModule.address,
            collectModuleInitData: abiCoder.encode(['bool'], [true]),
            referenceModuleData: '0x',
            referenceModule: tokenGatedReferenceModule.address,
            referenceModuleInitData: referenceModuleInitData,
          })
        ).to.not.be.reverted;
      });
    });
  });
});
