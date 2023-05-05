import { BigNumber } from '@ethersproject/bignumber';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import { ERRORS } from '../../helpers/errors';
import {
  lensHub,
  abiCoder,
  makeSuiteCleanRoom,
  user,
  anotherUser,
  publisher,
  deployer,
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
import {
  CAMPAIGN_MERKLE_LEAF,
  CAMPAIGN_MERKLE_LEAF_TWO,
  CAMPAIGN_MERKLE_LEAF_THREE
} from '../../helpers/constants';

makeSuiteCleanRoom('TargetedCampaignReferenceModule', function () {
  const SECOND_PROFILE_ID = FIRST_PROFILE_ID + 1;
  const THIRD_PROFILE_ID = FIRST_PROFILE_ID + 2;
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
    context('context: with a valid merkle tree', () => {
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

      it('does not distribute the reward again on a successive mirror from the same profile', async () => {
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

        // again
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

        // balance reflects only one reward distribution
        expect(
          (await currencyContract.balanceOf(publisher.address)).toString()
        ).to.equal(parseEther(DEFAULT_BUDGET_PER_PROFILE).toString());

        // sanity check, budget remaining reflects only one reward distribution
        const budgetRemaining = await referenceModule.getBudgetRemainingForPublication(FIRST_PROFILE_ID, FIRST_PUB_ID);
        const expected = parseEther(DEFAULT_BUDGET).sub(parseEther(DEFAULT_BUDGET_PER_PROFILE));
        expect(budgetRemaining.toString()).to.equal(expected.toString());
      });

      it('does not distribute the reward for another profile submitting a proof for another tree', async () => {
        // the user has profileId = 0x02, which we a the merkle proof for - but it's a different tree
        const { proof, index } = CAMPAIGN_MERKLE_LEAF_TWO;
        const referenceModuleData = abiCoder.encode(['bytes32[]', 'uint256'], [proof, index]);
        await expect(
          lensHub.connect(user).mirror({
            profileId: SECOND_PROFILE_ID,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: FIRST_PUB_ID,
            referenceModuleData,
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: '0x',
          })
        ).to.not.be.reverted;

        expect(
          (await currencyContract.balanceOf(user.address)).toString()
        ).to.equal('0');

        // sanity check, budget did not change
        const budgetRemaining = await referenceModule.getBudgetRemainingForPublication(FIRST_PROFILE_ID, FIRST_PUB_ID);
        const expected = parseEther(DEFAULT_BUDGET);
        expect(budgetRemaining.toString()).to.equal(expected.toString());

        expect(
          await referenceModule.campaignRewardClaimed(FIRST_PROFILE_ID, FIRST_PUB_ID, SECOND_PROFILE_ID)
        ).to.equal(false);
      });

      it('does not distribute the reward when given empty data', async () => {
        await expect(
          lensHub.connect(user).mirror({
            profileId: SECOND_PROFILE_ID,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: FIRST_PUB_ID,
            referenceModuleData: '0x',
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: '0x',
          })
        ).to.not.be.reverted;

        expect(
          (await currencyContract.balanceOf(user.address)).toString()
        ).to.equal('0');

        // sanity check, budget did not change
        const budgetRemaining = await referenceModule.getBudgetRemainingForPublication(FIRST_PROFILE_ID, FIRST_PUB_ID);
        const expected = parseEther(DEFAULT_BUDGET);
        expect(budgetRemaining.toString()).to.equal(expected.toString());

        expect(
          await referenceModule.campaignRewardClaimed(FIRST_PROFILE_ID, FIRST_PUB_ID, SECOND_PROFILE_ID)
        ).to.equal(false);
      });

      it('reverts when given malformed data', async () => {
        const referenceModuleData = abiCoder.encode(['uint256', 'address'], [1, user.address]);
        await expect(
          lensHub.connect(user).mirror({
            profileId: SECOND_PROFILE_ID,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: FIRST_PUB_ID,
            referenceModuleData,
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: '0x',
          })
        ).to.be.reverted;
      });
    });

    context('context: with enough budget for two mirrors', () => {
      const budget = parseEther('2');
      const budgetPerProfile = parseEther('1');
      let closingTxReceipt;

      beforeEach(async () => {
        const referenceModuleInitData = getTargetedCampaignReferenceModuleInitData({
          merkleRoot: CAMPAIGN_MERKLE_LEAF_TWO.root, // we have two leaves for this root
          budget,
          totalProfiles: 2,
          budgetPerProfile
        });

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

        // need another profile
        await expect(
          lensHub.createProfile({
            to: anotherUser.address,
            handle: 'anotheruser',
            imageURI: OTHER_MOCK_URI,
            followModule: ethers.constants.AddressZero,
            followModuleInitData: [],
            followNFTURI: MOCK_FOLLOW_NFT_URI,
          })
        ).to.not.be.reverted;

        // user mirrors
        const referenceModuleData = abiCoder.encode(
          ['bytes32[]', 'uint256'],
          [CAMPAIGN_MERKLE_LEAF_TWO.proof, CAMPAIGN_MERKLE_LEAF_TWO.index]
        );
        await expect(
          lensHub.connect(user).mirror({
            profileId: SECOND_PROFILE_ID,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: FIRST_PUB_ID,
            referenceModuleData,
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: '0x',
          })
        ).to.not.be.reverted;

        // another user mirrors
        const referenceModuleDataTwo = abiCoder.encode(
          ['bytes32[]', 'uint256'],
          [CAMPAIGN_MERKLE_LEAF_THREE.proof, CAMPAIGN_MERKLE_LEAF_THREE.index]
        );

        const tx = lensHub.connect(anotherUser).mirror({
          profileId: THIRD_PROFILE_ID,
          profileIdPointed: FIRST_PROFILE_ID,
          pubIdPointed: FIRST_PUB_ID,
          referenceModuleData: referenceModuleDataTwo,
          referenceModule: ethers.constants.AddressZero,
          referenceModuleInitData: '0x',
        });

        closingTxReceipt = await waitForTx(tx);
      });

      it('distributes the rewards for both profiles', async () => {
        expect(
          (await currencyContract.balanceOf(user.address)).toString()
        ).to.equal(budgetPerProfile.toString());

        expect(
          (await currencyContract.balanceOf(anotherUser.address)).toString()
        ).to.equal(budgetPerProfile.toString());

        expect(
          await referenceModule.campaignRewardClaimed(FIRST_PROFILE_ID, FIRST_PUB_ID, SECOND_PROFILE_ID)
        ).to.equal(true);
        expect(
          await referenceModule.campaignRewardClaimed(FIRST_PROFILE_ID, FIRST_PUB_ID, THIRD_PROFILE_ID)
        ).to.equal(true);
      });

      it('closes the campaign and emits an event', async () => {
        const budgetRemaining = await referenceModule.getBudgetRemainingForPublication(FIRST_PROFILE_ID, FIRST_PUB_ID);
        expect(budgetRemaining.toString()).to.equal('0');

        matchEvent(
          closingTxReceipt,
          'TargetedCampaignReferencePublicationClosed',
          [FIRST_PROFILE_ID, FIRST_PUB_ID, parseEther('0')],
          referenceModule
        );
      });

      it('allows another mirror but does not distribute more rewards', async () => {
        const referenceModuleData = abiCoder.encode(
          ['bytes32[]', 'uint256'],
          [CAMPAIGN_MERKLE_LEAF_TWO.proof, CAMPAIGN_MERKLE_LEAF_TWO.index]
        );
        await expect(
          lensHub.connect(user).mirror({
            profileId: SECOND_PROFILE_ID,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: FIRST_PUB_ID,
            referenceModuleData,
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: '0x',
          })
        ).to.not.be.reverted;

        expect(
          (await currencyContract.balanceOf(user.address)).toString()
        ).to.equal(budgetPerProfile.toString());
      });
    });
  });

  describe('#withdrawBudgetForPublication', () => {
    it('reverts when the caller is not the profile owner', async () => {
      await expect(
        referenceModule.connect(user).withdrawBudgetForPublication(FIRST_PROFILE_ID, FIRST_PUB_ID)
      ).to.be.revertedWith(ERRORS.NOT_PROFILE_OWNER);
    });

    it('reverts when an active campaign is not found', async () => {
      await expect(
        referenceModule.connect(publisher).withdrawBudgetForPublication(FIRST_PROFILE_ID, FIRST_PUB_ID)
      ).to.be.revertedWith('NotFound');
    });

    context('context: with an active campaign', async () => {
      beforeEach(async () => {
        const referenceModuleInitData = getTargetedCampaignReferenceModuleInitData({
          merkleRoot: CAMPAIGN_MERKLE_LEAF_TWO.root, // for user to mirror
        });
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

        // user mirrors
        const referenceModuleData = abiCoder.encode(
          ['bytes32[]', 'uint256'],
          [CAMPAIGN_MERKLE_LEAF_TWO.proof, CAMPAIGN_MERKLE_LEAF_TWO.index]
        );
        await expect(
          lensHub.connect(user).mirror({
            profileId: SECOND_PROFILE_ID,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: FIRST_PUB_ID,
            referenceModuleData,
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: '0x',
          })
        ).to.not.be.reverted;
      });

      it('closes the campaign and transfers the remaining budget back to the creator', async () => {
        await referenceModule.connect(publisher).withdrawBudgetForPublication(FIRST_PROFILE_ID, FIRST_PUB_ID);
        const expected = parseEther(DEFAULT_BUDGET).sub(parseEther(DEFAULT_BUDGET_PER_PROFILE));
        expect(
          (await currencyContract.balanceOf(publisher.address)).toString()
        ).to.equal(expected.toString());

        const budgetRemaining = await referenceModule.getBudgetRemainingForPublication(FIRST_PROFILE_ID, FIRST_PUB_ID);
        expect(budgetRemaining.toString()).to.equal('0');
      });

      it('emits an event', async () => {
        const tx = referenceModule.connect(publisher).withdrawBudgetForPublication(FIRST_PROFILE_ID, FIRST_PUB_ID);
        const txReceipt = await waitForTx(tx);

        matchEvent(
          txReceipt,
          'TargetedCampaignReferencePublicationClosed',
          [FIRST_PROFILE_ID, FIRST_PUB_ID, parseEther(DEFAULT_BUDGET).sub(parseEther(DEFAULT_BUDGET_PER_PROFILE))],
          referenceModule
        );
      });
    });
  });

  describe('#setProtocolFeeBps', () => {
    it('reverts when the caller is not the contract owner', async () => {
      await expect(
        referenceModule.connect(user).setProtocolFeeBps(100)
      ).to.be.revertedWith('Ownable: caller is not the owner');
    });

    it('reverts when setting a value above the allowed max', async () => {
      const max = await referenceModule.PROTOCOL_FEE_BPS_MAX();
      await expect(
        referenceModule.setProtocolFeeBps(max+1)
      ).to.be.revertedWith('AboveMax');
    });

    it('updates storage and emits an event', async () => {
      const value = 100;
      const tx = referenceModule.setProtocolFeeBps(value);
      const txReceipt = await waitForTx(tx);

      expect((await referenceModule.protocolFeeBps()).toString()).to.equal(value.toString());

      matchEvent(
        txReceipt,
        'SetProtocolFeeBps',
        [BigNumber.from(value.toString())],
        referenceModule
      );
    });
  });

  describe('#withdrawProtocolFees', () => {
    it('reverts when the caller is not the contract owner', async () => {
      await expect(
        referenceModule.connect(user).withdrawProtocolFees(currencyContract.address)
      ).to.be.revertedWith('Ownable: caller is not the owner');
    });

    it('does nothing when there is no balance to withdraw', async () => {
      await expect(
        referenceModule.withdrawProtocolFees(currencyContract.address)
      ).to.not.be.reverted;

      expect((await currencyContract.balanceOf(deployer.address)).toString()).to.equal('0');
    });

    context('context: when there are fees accrued', async () => {
      let protocolFee;

      beforeEach(async () => {
        const referenceModuleInitData = getTargetedCampaignReferenceModuleInitData({
          merkleRoot: CAMPAIGN_MERKLE_LEAF_TWO.root, // for user to mirror
        });
        const budget = parseEther(DEFAULT_BUDGET);
        protocolFee = await referenceModule.getProtocolFee(budget);
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

        // user mirrors
        const referenceModuleData = abiCoder.encode(
          ['bytes32[]', 'uint256'],
          [CAMPAIGN_MERKLE_LEAF_TWO.proof, CAMPAIGN_MERKLE_LEAF_TWO.index]
        );
        await expect(
          lensHub.connect(user).mirror({
            profileId: SECOND_PROFILE_ID,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: FIRST_PUB_ID,
            referenceModuleData,
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: '0x',
          })
        ).to.not.be.reverted;
      });

      it('transfers the fees without affecting the remaining budget, and emits an event', async () => {
        const tx = referenceModule.withdrawProtocolFees(currencyContract.address);
        const txReceipt = await waitForTx(tx);

        expect(
          (await currencyContract.balanceOf(deployer.address)).toString()
        ).to.equal(protocolFee.toString());

        expect(
          (await referenceModule.getBudgetRemainingForPublication(FIRST_PROFILE_ID, FIRST_PUB_ID)).toString()
        ).to.equal(parseEther(DEFAULT_BUDGET).sub(parseEther(DEFAULT_BUDGET_PER_PROFILE)).toString());

        matchEvent(
          txReceipt,
          'WithdrawProtocolFees',
          [currencyContract.address, protocolFee],
          referenceModule
        );
      });
    });
  });

  describe('#processComment', () => {
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

    it('does nothing, does not revert', async () => {
      await expect(
        lensHub.connect(publisher).comment({
          profileId: FIRST_PROFILE_ID,
          contentURI: MOCK_URI,
          profileIdPointed: FIRST_PROFILE_ID,
          pubIdPointed: FIRST_PUB_ID,
          collectModule: freeCollectModule.address,
          collectModuleInitData: abiCoder.encode(['bool'], [true]),
          referenceModuleData: '0x',
          referenceModule: ethers.constants.AddressZero,
          referenceModuleInitData: '0x',
        })
      ).to.not.be.reverted;
    });
  });
});
