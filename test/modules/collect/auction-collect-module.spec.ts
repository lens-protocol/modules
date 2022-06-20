import { BigNumber, BigNumberish } from '@ethersproject/bignumber';
import { parseEther } from '@ethersproject/units';
import '@nomiclabs/hardhat-ethers';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Currency, FollowNFT__factory } from '../../../typechain';
import { ERRORS } from '../../helpers/errors';
import {
  abiCoder,
  auctionCollectModule,
  BPS_MAX,
  chainId,
  currency,
  feeRecipient,
  FIRST_PROFILE_ID,
  FIRST_PUB_ID,
  freeCollectModule,
  governance,
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
} from './../../__setup.spec';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { publisher } from '../../__setup.spec';
import { getTimestamp, matchEvent, setNextBlockTimestamp, waitForTx } from '../../helpers/utils';
import { signBidWithSigMessage } from '../../helpers/signatures/modules/collect/auction-collect-module';
import { Domain } from '../../helpers/signatures/utils';
import { ERC20, ERC20Interface } from '../../../typechain/ERC20';
import { FAKE_PRIVATEKEY } from '../../helpers/constants';

export const DEFAULT_BID_AMOUNT = parseEther('2');
export let BID_WITH_SIG_DOMAIN: Domain;

makeSuiteCleanRoom('AuctionCollectModule', function () {
  const ONE_DAY_IN_SECONDS = BigNumber.from(24 * 3600);
  const TEN_MINUTES_IN_SECONDS = BigNumber.from(10 * 60);
  const DEFAULT_RESERVE_PRICE = parseEther('1');
  const DEFAULT_MIN_TIME_AFTER_BID = TEN_MINUTES_IN_SECONDS;
  const DEFAULT_MIN_BID_INCREMENT = parseEther('0.1');
  const DEFAULT_DURATION = ONE_DAY_IN_SECONDS;
  let bidder: SignerWithAddress;
  let anotherBidder: SignerWithAddress;

  interface AuctionCollectModuleInitData {
    availableSinceTimestamp?: BigNumber;
    duration?: BigNumber;
    minTimeAfterBid?: BigNumber;
    reservePrice?: BigNumber;
    minBidIncrement?: BigNumber;
    referralFee?: number;
    feeCurrency?: string;
    recipient?: string;
    onlyFollowers?: boolean;
  }

  async function getAuctionCollectModuleInitData({
    availableSinceTimestamp = ethers.constants.Zero,
    duration = DEFAULT_DURATION,
    minTimeAfterBid = DEFAULT_MIN_TIME_AFTER_BID,
    reservePrice = DEFAULT_RESERVE_PRICE,
    minBidIncrement = DEFAULT_MIN_BID_INCREMENT,
    referralFee = REFERRAL_FEE_BPS,
    feeCurrency = currency.address,
    recipient = feeRecipient.address,
    onlyFollowers = false,
  }: AuctionCollectModuleInitData): Promise<string> {
    return abiCoder.encode(
      [
        'uint256',
        'uint256',
        'uint256',
        'uint256',
        'uint256',
        'uint16',
        'address',
        'address',
        'bool',
      ],
      [
        availableSinceTimestamp,
        duration,
        minTimeAfterBid,
        reservePrice,
        minBidIncrement,
        referralFee,
        feeCurrency,
        recipient,
        onlyFollowers,
      ]
    );
  }

  interface AuctionEndSimulationData {
    profileId?: BigNumberish;
    pubId?: BigNumberish;
    secondsToBeElapsedAfterEnd?: BigNumberish;
  }

  async function simulateAuctionEnd({
    profileId = FIRST_PROFILE_ID,
    pubId = FIRST_PUB_ID,
    secondsToBeElapsedAfterEnd = 1,
  }: AuctionEndSimulationData) {
    const endTimestamp = (await auctionCollectModule.getAuctionData(profileId, pubId)).endTimestamp;
    setNextBlockTimestamp(endTimestamp.add(secondsToBeElapsedAfterEnd).toNumber());
  }

  interface MintAndApproveCurrency {
    owner?: SignerWithAddress;
    spender?: string;
    amountToMint?: BigNumberish;
    amountToApprove?: BigNumberish;
  }

  async function mintAndApproveCurrency({
    owner = bidder,
    spender = auctionCollectModule.address,
    amountToMint = parseEther('100000'),
    amountToApprove = ethers.constants.MaxUint256,
  }: MintAndApproveCurrency) {
    await currency.connect(owner).mint(owner.address, amountToMint);
    await currency.connect(owner).approve(spender, amountToApprove);
  }

  before(async function () {
    BID_WITH_SIG_DOMAIN = {
      name: 'AuctionCollectModule',
      version: '1',
      chainId: chainId,
      verifyingContract: auctionCollectModule.address,
    };
    bidder = user;
    anotherBidder = anotherUser;
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

  context('Publication creation', function () {
    context('Negatives', function () {
      it('User should fail to post setting zero duration', async function () {
        const collectModuleInitData = await getAuctionCollectModuleInitData({
          duration: ethers.constants.Zero,
          minTimeAfterBid: ethers.constants.Zero,
        });
        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: auctionCollectModule.address,
            collectModuleInitData: collectModuleInitData,
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: [],
          })
        ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
      });

      it('User should fail to post setting a duration less than min time after bid', async function () {
        const duration = ethers.constants.One;
        expect(duration.lt(DEFAULT_MIN_TIME_AFTER_BID)).to.be.true;
        const collectModuleInitData = await getAuctionCollectModuleInitData({
          duration: duration,
        });
        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: auctionCollectModule.address,
            collectModuleInitData: collectModuleInitData,
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: [],
          })
        ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
      });

      it('User should fail to post using unwhitelisted currency', async function () {
        const unwhitelistedCurrency = ethers.constants.AddressZero;
        expect(await moduleGlobals.isCurrencyWhitelisted(unwhitelistedCurrency)).to.be.false;
        const collectModuleInitData = await getAuctionCollectModuleInitData({
          feeCurrency: unwhitelistedCurrency,
        });
        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: auctionCollectModule.address,
            collectModuleInitData: collectModuleInitData,
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: [],
          })
        ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
      });

      it('User should fail to post using referral fee greater than max BPS', async function () {
        const referralFee = BPS_MAX + 1;
        expect(referralFee).to.be.greaterThan(BPS_MAX);
        const collectModuleInitData = await getAuctionCollectModuleInitData({
          referralFee: referralFee,
        });
        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: auctionCollectModule.address,
            collectModuleInitData: collectModuleInitData,
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: [],
          })
        ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
      });
    });

    context('Scenarios', function () {
      it('User should succeed to create a publication when all parameters are valid and tx should emit expected event', async function () {
        const collectModuleInitData = await getAuctionCollectModuleInitData({});
        const tx = lensHub.connect(publisher).post({
          profileId: FIRST_PROFILE_ID,
          contentURI: MOCK_URI,
          collectModule: auctionCollectModule.address,
          collectModuleInitData: collectModuleInitData,
          referenceModule: ethers.constants.AddressZero,
          referenceModuleInitData: [],
        });
        const txReceipt = await waitForTx(tx);
        matchEvent(
          txReceipt,
          'AuctionCreated',
          [
            FIRST_PROFILE_ID,
            FIRST_PUB_ID,
            ethers.constants.Zero,
            DEFAULT_DURATION,
            DEFAULT_MIN_TIME_AFTER_BID,
            DEFAULT_RESERVE_PRICE,
            DEFAULT_MIN_BID_INCREMENT,
            REFERRAL_FEE_BPS,
            currency.address,
            feeRecipient.address,
            false,
          ],
          auctionCollectModule
        );
      });

      it('User should succeed to create a publication that burns the fees', async function () {
        const collectModuleInitData = await getAuctionCollectModuleInitData({
          recipient: ethers.constants.AddressZero,
        });
        const tx = lensHub.connect(publisher).post({
          profileId: FIRST_PROFILE_ID,
          contentURI: MOCK_URI,
          collectModule: auctionCollectModule.address,
          collectModuleInitData: collectModuleInitData,
          referenceModule: ethers.constants.AddressZero,
          referenceModuleInitData: [],
        });
        const txReceipt = await waitForTx(tx);
        matchEvent(
          txReceipt,
          'AuctionCreated',
          [
            FIRST_PROFILE_ID,
            FIRST_PUB_ID,
            ethers.constants.Zero,
            DEFAULT_DURATION,
            DEFAULT_MIN_TIME_AFTER_BID,
            DEFAULT_RESERVE_PRICE,
            DEFAULT_MIN_BID_INCREMENT,
            REFERRAL_FEE_BPS,
            currency.address,
            ethers.constants.AddressZero,
            false,
          ],
          auctionCollectModule
        );
      });
    });

    context('Bid', function () {
      before(async function () {
        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: auctionCollectModule.address,
            collectModuleInitData: await getAuctionCollectModuleInitData({}),
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: [],
          })
        ).to.not.be.reverted;
      });

      context.only('Negatives', function () {
        it('User should fail to bid for an unexistent publication', async function () {
          const unexistentPubId = 69;
          await expect(
            auctionCollectModule
              .connect(bidder)
              .bid(FIRST_PROFILE_ID, unexistentPubId, DEFAULT_BID_AMOUNT, 0)
          ).to.be.revertedWith(ERRORS.PUBLICATION_DOES_NOT_EXIST);
        });

        it('User should fail to bid if the publication uses another collect module', async function () {
          await expect(
            lensHub.connect(publisher).post({
              profileId: FIRST_PROFILE_ID,
              contentURI: MOCK_URI,
              collectModule: freeCollectModule.address,
              collectModuleInitData: abiCoder.encode(['bool'], [false]),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.not.be.reverted;
          const pubId = FIRST_PUB_ID + 1;
          await expect(
            auctionCollectModule.connect(bidder).bid(FIRST_PROFILE_ID, pubId, DEFAULT_BID_AMOUNT, 0)
          ).to.be.revertedWith(ERRORS.UNAVAILABLE_AUCTION);
        });

        it('User should fail to bid if auction is not available yet', async function () {
          const currentTimestamp = BigNumber.from(await getTimestamp());
          await expect(
            lensHub.connect(publisher).post({
              profileId: FIRST_PROFILE_ID,
              contentURI: MOCK_URI,
              collectModule: auctionCollectModule.address,
              collectModuleInitData: await getAuctionCollectModuleInitData({
                availableSinceTimestamp: currentTimestamp.add(ONE_DAY_IN_SECONDS),
              }),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.not.be.reverted;
          const pubId = FIRST_PUB_ID + 1;
          const availableSinceTimestamp = (
            await auctionCollectModule.getAuctionData(FIRST_PROFILE_ID, pubId)
          ).availableSinceTimestamp;
          expect(availableSinceTimestamp.gt(currentTimestamp)).to.be.true;
          await expect(
            auctionCollectModule.connect(bidder).bid(FIRST_PROFILE_ID, pubId, DEFAULT_BID_AMOUNT, 0)
          ).to.be.revertedWith(ERRORS.UNAVAILABLE_AUCTION);
        });

        it('User should fail to bid if auction has already ended', async function () {
          let auction = await auctionCollectModule.getAuctionData(FIRST_PROFILE_ID, FIRST_PUB_ID);
          let currentTimestamp = BigNumber.from(await getTimestamp());
          expect(currentTimestamp.gt(auction.availableSinceTimestamp)).to.be.true;
          await mintAndApproveCurrency({});
          await expect(
            auctionCollectModule
              .connect(bidder)
              .bid(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_BID_AMOUNT, 0)
          ).to.not.be.reverted;
          auction = await auctionCollectModule.getAuctionData(FIRST_PROFILE_ID, FIRST_PUB_ID);
          expect(auction.startTimestamp.gte(currentTimestamp)).to.be.true;
          await simulateAuctionEnd({});

          // The tx below is just a dummy tx that does not affect the context of the test and, as a tx is needed to
          // update the block timestamp, being able to verify the precondition of block.timestamp > auction.endTimestamp
          // before doing the bid call.
          lensHub.connect(publisher).setDefaultProfile(FIRST_PROFILE_ID);

          auction = await auctionCollectModule.getAuctionData(FIRST_PROFILE_ID, FIRST_PUB_ID);
          currentTimestamp = BigNumber.from(await getTimestamp());
          expect(currentTimestamp.gt(auction.endTimestamp)).to.be.true;
          await expect(
            auctionCollectModule
              .connect(bidder)
              .bid(
                FIRST_PROFILE_ID,
                FIRST_PUB_ID,
                DEFAULT_BID_AMOUNT.add(DEFAULT_MIN_BID_INCREMENT),
                0
              )
          ).to.be.revertedWith(ERRORS.UNAVAILABLE_AUCTION);
        });

        it('User should fail to bid if bidder is address zero', async function () {
          await expect(
            auctionCollectModule
              .connect(ethers.constants.AddressZero)
              .bid(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_BID_AMOUNT, 0)
          ).to.be.revertedWith(ERRORS.INVALID_BIDDER);
        });

        it('User should fail to bid if does not have enough balance', async function () {
          await mintAndApproveCurrency({ amountToMint: 0 });
          await expect(
            auctionCollectModule
              .connect(bidder)
              .bid(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_BID_AMOUNT, 0)
          ).to.be.revertedWith(ERRORS.ERC20_TRANSFER_EXCEEDS_BALANCE);
        });

        it('User should fail to bid if does not have enough allowance', async function () {
          await mintAndApproveCurrency({ amountToApprove: 0 });
          await expect(
            auctionCollectModule
              .connect(bidder)
              .bid(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_BID_AMOUNT, 0)
          ).to.be.revertedWith(ERRORS.ERC20_INSUFFICIENT_ALLOWANCE);
        });

        it('User should fail to bid if placing the bid that starts the auction but it is below reserve price', async function () {
          const reservePrice = (
            await auctionCollectModule.getAuctionData(FIRST_PROFILE_ID, FIRST_PUB_ID)
          ).reservePrice;
          const bidAmountBelowReservePrice = parseEther('0.01');
          expect(reservePrice.gt(bidAmountBelowReservePrice)).to.be.true;
          await mintAndApproveCurrency({});
          await expect(
            auctionCollectModule
              .connect(bidder)
              .bid(FIRST_PROFILE_ID, FIRST_PUB_ID, bidAmountBelowReservePrice, 0)
          ).to.be.revertedWith(ERRORS.INSUFFICIENT_BID_AMOUNT);
        });

        it('User should fail to bid if auction already started but bid does not comply min increment requirement', async function () {
          await mintAndApproveCurrency({});
          await expect(
            auctionCollectModule
              .connect(bidder)
              .bid(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_BID_AMOUNT, 0)
          ).to.be.not.be.reverted;
          const auction = await auctionCollectModule.getAuctionData(FIRST_PROFILE_ID, FIRST_PUB_ID);
          const bidAmountWithoutEnoughIncrement = DEFAULT_BID_AMOUNT.add(1);
          expect(bidAmountWithoutEnoughIncrement.gt(DEFAULT_BID_AMOUNT)).to.be.true;
          expect(
            bidAmountWithoutEnoughIncrement.sub(DEFAULT_BID_AMOUNT).lt(auction.minBidIncrement)
          ).to.be.true;
          await expect(
            auctionCollectModule
              .connect(bidder)
              .bid(FIRST_PROFILE_ID, FIRST_PUB_ID, bidAmountWithoutEnoughIncrement, 0)
          ).to.be.revertedWith(ERRORS.INSUFFICIENT_BID_AMOUNT);
        });

        it('User should fail to bid if auction is only for followers and he is not following the publication owner', async function () {
          await expect(
            lensHub.connect(publisher).post({
              profileId: FIRST_PROFILE_ID,
              contentURI: MOCK_URI,
              collectModule: auctionCollectModule.address,
              collectModuleInitData: await getAuctionCollectModuleInitData({ onlyFollowers: true }),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.not.be.reverted;
          const pubId = FIRST_PUB_ID + 1;
          expect(
            (await auctionCollectModule.getAuctionData(FIRST_PROFILE_ID, pubId)).onlyFollowers
          ).to.be.true;
          await mintAndApproveCurrency({});
          await expect(
            auctionCollectModule.connect(bidder).bid(FIRST_PROFILE_ID, pubId, DEFAULT_BID_AMOUNT, 0)
          ).to.be.revertedWith(ERRORS.FOLLOW_INVALID);
        });

        it('User should fail to bid if auction is only for followers and he followed publication owner after auction started', async function () {
          await expect(
            lensHub.connect(publisher).post({
              profileId: FIRST_PROFILE_ID,
              contentURI: MOCK_URI,
              collectModule: auctionCollectModule.address,
              collectModuleInitData: await getAuctionCollectModuleInitData({ onlyFollowers: true }),
              referenceModule: ethers.constants.AddressZero,
              referenceModuleInitData: [],
            })
          ).to.not.be.reverted;
          const pubId = FIRST_PUB_ID + 1;
          expect(
            (await auctionCollectModule.getAuctionData(FIRST_PROFILE_ID, pubId)).onlyFollowers
          ).to.be.true;
          await mintAndApproveCurrency({});
          await mintAndApproveCurrency({ owner: anotherBidder });
          await expect(
            lensHub.connect(anotherBidder).follow([FIRST_PROFILE_ID], [[]])
          ).to.not.be.reverted;
          await expect(
            auctionCollectModule
              .connect(anotherBidder)
              .bid(FIRST_PROFILE_ID, pubId, DEFAULT_BID_AMOUNT, FIRST_FOLLOW_NFT_ID)
          ).to.not.be.reverted;
          await expect(lensHub.connect(bidder).follow([FIRST_PROFILE_ID], [[]])).to.not.be.reverted;
          const followNftAddress = await lensHub.getFollowNFT(FIRST_PROFILE_ID);
          const bidderFollowNftBalance = await FollowNFT__factory.connect(
            followNftAddress,
            bidder
          ).balanceOf(bidder.address);
          expect(bidderFollowNftBalance.gt(ethers.constants.Zero)).to.be.true;
          await expect(
            auctionCollectModule
              .connect(bidder)
              .bid(
                FIRST_PROFILE_ID,
                pubId,
                DEFAULT_BID_AMOUNT.add(DEFAULT_MIN_BID_INCREMENT),
                FIRST_FOLLOW_NFT_ID + 1
              )
          ).to.be.revertedWith(ERRORS.FOLLOW_INVALID);
        });
      });

      context('Scenarios', function () {
        it('User should succeed...', async function () {
          // TODO: Scenario test!
        });
      });
    });

    /// --------------------------------------

    /// Template for next test context below

    /// --------------------------------------

    context('Context', function () {
      context('Negatives', function () {
        it('User should fail...', async function () {
          // TODO: Negative test!
        });
      });

      context('Scenarios', function () {
        it('User should succeed...', async function () {
          // TODO: Scenario test!
        });
      });
    });
  });
});
