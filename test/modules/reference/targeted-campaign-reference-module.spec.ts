import { BigNumber } from '@ethersproject/bignumber';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import { ERRORS } from '../../helpers/errors';
import {
  lensHub,
  abiCoder,
  makeSuiteCleanRoom,
  user,
  publisher,
  MOCK_PROFILE_HANDLE,
  MOCK_URI,
  MOCK_FOLLOW_NFT_URI,
  FIRST_PROFILE_ID,
  FIRST_PUB_ID,
  targetedCampaignReferenceModule as referenceModule,
  freeCollectModule,
  currency as currencyContract,
  OTHER_MOCK_URI,
  CAMPAIGN_FEE_BPS,
} from '../../__setup.spec';
import { matchEvent, waitForTx } from '../../helpers/utils';
import { parseEther } from '@ethersproject/units';
import { CAMPAIGN_MERKLE_LEAF } from '../../helpers/constants';

makeSuiteCleanRoom('TargetedCampaignReferenceModule', function () {
  const SECOND_PROFILE_ID = FIRST_PROFILE_ID + 1;
  const DEFAULT_BUDGET = '10';
  const DEFAULT_TOTAL_PROFILES = 10;
  const DEFAULT_BUDGET_PER_PROFILE = '1';

  interface TargetedCampaignModuleInitData {
    merkleRoot: string
    currency: string;
    budget: BigNumber;
    totalProfiles: number;
    budgetPerProfile: BigNumber;
  }

  async function getTargetedCampaignReferenceModuleInitData({
    merkleRoot = CAMPAIGN_MERKLE_LEAF.root,
    currency = currencyContract.address,
    budget = parseEther(DEFAULT_BUDGET),
    totalProfiles = DEFAULT_TOTAL_PROFILES,
    budgetPerProfile = parseEther(DEFAULT_BUDGET_PER_PROFILE)
  }: TargetedCampaignModuleInitData): Promise<string> {
    return abiCoder.encode(
      ['bytes32', 'address', 'uint256', 'uint256', 'uint256'],
      [merkleRoot, currency, budget, totalProfiles, budgetPerProfile]
    );
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

  describe('constructor', () => {
    it('sets storage', async () => {
      expect(
        (await referenceModule.protocolFeeBps()).toNumber()
      ).to.equal(CAMPAIGN_FEE_BPS);
    });
  });

  describe('#initializeReferenceModule', () => {
    it('reverts when the caller is not LensHub', async () => {
      await expect(
        referenceModule.initializeReferenceModule(FIRST_PROFILE_ID, FIRST_PUB_ID, '0x')
      ).to.be.revertedWith(ERRORS.NOT_HUB);
    });

    context('context: with invalid params', () => {
      it('reverts when the currency provided is not whitelisted', async () => {
        const referenceModuleInitData = getTargetedCampaignReferenceModuleInitData({
          currency: ethers.constants.AddressZero
        });

        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: freeCollectModule.address,
            collectModuleInitData: abiCoder.encode(['bool'], [true]),
            referenceModule: referenceModule.address,
            referenceModuleInitData,
          })
        ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
      });

      it('reverts when the budget is 0', async () => {
        const referenceModuleInitData = getTargetedCampaignReferenceModuleInitData({
          budget: BigNumber.from('0')
        });

        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: freeCollectModule.address,
            collectModuleInitData: abiCoder.encode(['bool'], [true]),
            referenceModule: referenceModule.address,
            referenceModuleInitData,
          })
        ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
      });

      it('reverts with bad math on budget, totalProfiles, and budgetPerProfile values', async () => {
        const referenceModuleInitData = getTargetedCampaignReferenceModuleInitData({
          budget: BigNumber.from('10'),
          totalProfiles: 10,
          budgetPerProfile: BigNumber.from('10'), // should be 1
        });

        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: freeCollectModule.address,
            collectModuleInitData: abiCoder.encode(['bool'], [true]),
            referenceModule: referenceModule.address,
            referenceModuleInitData,
          })
        ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
      });

      it('reverts when the merkle root is empty bytes', async () => {
        const referenceModuleInitData = getTargetedCampaignReferenceModuleInitData({
          merkleRoot: ethers.constants.HashZero
        });

        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: freeCollectModule.address,
            collectModuleInitData: abiCoder.encode(['bool'], [true]),
            referenceModule: referenceModule.address,
            referenceModuleInitData,
          })
        ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
      });

      it('reverts when the caller does not have enough balance to cover the budget plus fee', async () => {
        const referenceModuleInitData = getTargetedCampaignReferenceModuleInitData({});
        await currencyContract.mint(publisher.address, parseEther(DEFAULT_BUDGET));

        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: freeCollectModule.address,
            collectModuleInitData: abiCoder.encode(['bool'], [true]),
            referenceModule: referenceModule.address,
            referenceModuleInitData,
          })
        ).to.be.revertedWith('NotEnoughBalance');
      });

      it('reverts when the caller has not approved the transfer of the budget plus fee', async () => {
        const referenceModuleInitData = getTargetedCampaignReferenceModuleInitData({});
        const budget = parseEther(DEFAULT_BUDGET);
        const protocolFee = await referenceModule.getProtocolFee(budget);
        await currencyContract.mint(publisher.address, budget.add(protocolFee));
        await currencyContract.connect(publisher).approve(referenceModule.address, budget);

        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: freeCollectModule.address,
            collectModuleInitData: abiCoder.encode(['bool'], [true]),
            referenceModule: referenceModule.address,
            referenceModuleInitData,
          })
        ).to.be.revertedWith('NotEnoughAllowance');
      });
    });

    context('context: with valid params', () => {
      let referenceModuleInitData;
      let protocolFee;
      let totalAmount;

      beforeEach(async () => {
        referenceModuleInitData = getTargetedCampaignReferenceModuleInitData({});
        const budget = parseEther(DEFAULT_BUDGET);
        protocolFee = await referenceModule.getProtocolFee(budget);
        totalAmount = budget.add(protocolFee);
        await currencyContract.mint(publisher.address, totalAmount);
        await currencyContract.connect(publisher).approve(referenceModule.address, totalAmount);
      });

      it('initializes the module, transfers the budget + fee to the contract, and accrues fees', async () => {
        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: freeCollectModule.address,
            collectModuleInitData: abiCoder.encode(['bool'], [true]),
            referenceModule: referenceModule.address,
            referenceModuleInitData,
          })
        ).to.not.be.reverted;

        expect(
          (await currencyContract.balanceOf(referenceModule.address)).toString()
        ).to.equal(totalAmount.toString());

        expect(
          (await referenceModule.protocolFeesPerCurrency(currencyContract.address)).toString()
        ).to.equal(protocolFee.toString());
      });

      it('emits an event', async () => {
        const tx = lensHub.connect(publisher).post({
          profileId: FIRST_PROFILE_ID,
          contentURI: MOCK_URI,
          collectModule: freeCollectModule.address,
          collectModuleInitData: abiCoder.encode(['bool'], [true]),
          referenceModule: referenceModule.address,
          referenceModuleInitData,
        });
        const txReceipt = await waitForTx(tx);
        matchEvent(
          txReceipt,
          'TargetedCampaignReferencePublicationCreated',
          [
            FIRST_PROFILE_ID,
            FIRST_PUB_ID,
            currencyContract.address,
            parseEther(DEFAULT_BUDGET),
            parseEther(DEFAULT_BUDGET_PER_PROFILE)
          ],
          referenceModule
        );
      });
    });
  });

  describe('#processMirror', () => {
    beforeEach(async () => {
      const referenceModuleInitData = getTargetedCampaignReferenceModuleInitData({});
      const budget = parseEther(DEFAULT_BUDGET);
      const protocolFee = await referenceModule.getProtocolFee(budget);
      const totalAmount = budget.add(protocolFee);

      await currencyContract.mint(publisher.address, totalAmount);
      await currencyContract.connect(publisher).approve(referenceModule.address, totalAmount);

      await expect(
        lensHub.connect(publisher).post({
          profileId: FIRST_PROFILE_ID,
          contentURI: MOCK_URI,
          collectModule: freeCollectModule.address,
          collectModuleInitData: abiCoder.encode(['bool'], [true]),
          referenceModule: referenceModule.address,
          referenceModuleInitData,
        })
      ).to.not.be.reverted;
    });

    context.only('context: for a valid merkle proof', () => {
      it('mirrors the post, distributes from the reward pool, and updates storage', async () => {
        // the publisher has profileId = 0x01, which we have the merkle proof for
        const { proof, index } = CAMPAIGN_MERKLE_LEAF;
        const referenceModuleData = abiCoder.encode(['bytes32[]', 'uint256'], [proof, index]);
        await expect(
          lensHub.connect(publisher).mirror({
            profileId: FIRST_PROFILE_ID, // we can mirror our own pub
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: FIRST_PUB_ID,
            referenceModuleData,
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: '0x',
          })
        ).to.not.be.reverted;

        expect(
          (await currencyContract.balanceOf(publisher.address)).toString()
        ).to.equal(parseEther(DEFAULT_BUDGET_PER_PROFILE).toString());

        // sanity check, budget remaining
        const budgetRemaining = await referenceModule.getBudgetRemainingForPublication(FIRST_PROFILE_ID, FIRST_PUB_ID);
        const expected = parseEther(DEFAULT_BUDGET).sub(parseEther(DEFAULT_BUDGET_PER_PROFILE));
        expect(budgetRemaining.toString()).to.equal(expected.toString());

        expect(
          await referenceModule.campaignRewardClaimed(FIRST_PROFILE_ID, FIRST_PUB_ID, FIRST_PROFILE_ID)
        ).to.equal(true);
      });
    })
  });
});
