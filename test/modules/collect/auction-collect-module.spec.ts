import { BigNumber, BigNumberish } from '@ethersproject/bignumber';
import { parseEther } from '@ethersproject/units';
import '@nomiclabs/hardhat-ethers';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import { AuctionCollectModule__factory, FollowNFT__factory } from '../../../typechain';
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
import { signBidWithSigMessage } from '../../helpers/signatures/modules/collect/auction-collect-module';
import { Domain } from '../../helpers/signatures/utils';

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
      ['uint64', 'uint32', 'uint32', 'uint256', 'uint256', 'uint16', 'address', 'address', 'bool'],
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

  beforeEach(async function () {
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
  });

  context('Bid', function () {
    beforeEach(async function () {
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

    context('Negatives', function () {
      it('User should fail to bid for an unexistent publication', async function () {
        const unexistentPubId = 69;
        await expect(
          auctionCollectModule
            .connect(bidder)
            .bid(FIRST_PROFILE_ID, unexistentPubId, DEFAULT_AMOUNT, 0)
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
          auctionCollectModule.connect(bidder).bid(FIRST_PROFILE_ID, pubId, DEFAULT_AMOUNT, 0)
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
          auctionCollectModule.connect(bidder).bid(FIRST_PROFILE_ID, pubId, DEFAULT_AMOUNT, 0)
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
            .bid(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_AMOUNT, 0)
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
            .bid(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_AMOUNT.add(DEFAULT_MIN_BID_INCREMENT), 0)
        ).to.be.revertedWith(ERRORS.UNAVAILABLE_AUCTION);
      });

      it('User should fail to bid if does not have enough balance', async function () {
        await mintAndApproveCurrency({ amountToMint: 0 });
        await expect(
          auctionCollectModule
            .connect(bidder)
            .bid(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_AMOUNT, 0)
        ).to.be.revertedWith(ERRORS.ERC20_TRANSFER_EXCEEDS_BALANCE);
      });

      it('User should fail to bid if does not have enough allowance', async function () {
        await mintAndApproveCurrency({ amountToApprove: 0 });
        await expect(
          auctionCollectModule
            .connect(bidder)
            .bid(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_AMOUNT, 0)
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
            .bid(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_AMOUNT, 0)
        ).to.be.not.be.reverted;
        const auction = await auctionCollectModule.getAuctionData(FIRST_PROFILE_ID, FIRST_PUB_ID);
        const bidAmountWithoutEnoughIncrement = DEFAULT_AMOUNT.add(1);
        expect(bidAmountWithoutEnoughIncrement.gt(DEFAULT_AMOUNT)).to.be.true;
        expect(
          bidAmountWithoutEnoughIncrement.sub(DEFAULT_AMOUNT).lt(auction.minBidIncrement)
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
          auctionCollectModule.connect(bidder).bid(FIRST_PROFILE_ID, pubId, DEFAULT_AMOUNT, 0)
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
            .bid(FIRST_PROFILE_ID, pubId, DEFAULT_AMOUNT, FIRST_FOLLOW_NFT_ID)
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
              DEFAULT_AMOUNT.add(DEFAULT_MIN_BID_INCREMENT),
              FIRST_FOLLOW_NFT_ID + 1
            )
        ).to.be.revertedWith(ERRORS.FOLLOW_INVALID);
      });
    });

    context('Scenarios', function () {
      beforeEach(async function () {
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
        await mintAndApproveCurrency({});
        await mintAndApproveCurrency({ owner: anotherBidder });
      });

      it('Funds should be deposited into the contract when a bid is placed', async function () {
        const bidderBalanceBeforeBid = await currency.balanceOf(bidder.address);
        const moduleBalanceBeforeBid = await currency.balanceOf(auctionCollectModule.address);
        expect(moduleBalanceBeforeBid.isZero()).to.be.true;
        const tx = auctionCollectModule
          .connect(bidder)
          .bid(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_AMOUNT, 0);
        const txReceipt = await waitForTx(tx);
        const txTimestamp = await getTimestamp();
        const endTimestamp = DEFAULT_DURATION.add(txTimestamp);
        matchEvent(
          txReceipt,
          'BidPlaced',
          [
            FIRST_PROFILE_ID,
            FIRST_PUB_ID,
            0,
            DEFAULT_AMOUNT,
            0,
            bidder.address,
            endTimestamp,
            txTimestamp,
          ],
          auctionCollectModule
        );
        const bidderBalanceAfterBid = await currency.balanceOf(bidder.address);
        const moduleBalanceAfterBid = await currency.balanceOf(auctionCollectModule.address);
        expect(moduleBalanceAfterBid.eq(DEFAULT_AMOUNT)).to.be.true;
        expect(bidderBalanceAfterBid.eq(bidderBalanceBeforeBid.sub(DEFAULT_AMOUNT))).to.be.true;
      });

      it('Funds should be returned to previous winner when a better bid is placed by another bidder', async function () {
        const bidderBalanceBeforeBids = await currency.balanceOf(bidder.address);
        const anotherBidderBalanceBeforeBids = await currency.balanceOf(anotherBidder.address);
        const moduleBalanceBeforeBids = await currency.balanceOf(auctionCollectModule.address);
        expect(moduleBalanceBeforeBids.isZero()).to.be.true;
        await expect(
          auctionCollectModule
            .connect(bidder)
            .bid(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_AMOUNT, 0)
        ).to.not.be.reverted;
        const bidderBalanceAfter1stBid = await currency.balanceOf(bidder.address);
        const anotherBidderAfter1stBid = await currency.balanceOf(anotherBidder.address);
        const moduleBalanceAfter1stBid = await currency.balanceOf(auctionCollectModule.address);
        expect(anotherBidderBalanceBeforeBids.eq(anotherBidderAfter1stBid)).to.be.true;
        expect(moduleBalanceAfter1stBid.eq(DEFAULT_AMOUNT)).to.be.true;
        expect(bidderBalanceAfter1stBid.eq(bidderBalanceBeforeBids.sub(DEFAULT_AMOUNT))).to.be.true;
        const secondBidAmount = DEFAULT_AMOUNT.add(DEFAULT_MIN_BID_INCREMENT);
        await expect(
          auctionCollectModule
            .connect(anotherBidder)
            .bid(FIRST_PROFILE_ID, FIRST_PUB_ID, secondBidAmount, 0)
        ).to.not.be.reverted;
        const bidderBalanceAfterBids = await currency.balanceOf(bidder.address);
        const anotherBidderBalanceAfterBids = await currency.balanceOf(anotherBidder.address);
        const moduleBalanceAfterBids = await currency.balanceOf(auctionCollectModule.address);
        expect(bidderBalanceAfterBids.eq(bidderBalanceAfterBids)).to.be.true;
        expect(moduleBalanceAfterBids.eq(secondBidAmount)).to.be.true;
        expect(
          anotherBidderBalanceAfterBids.eq(anotherBidderBalanceBeforeBids.sub(secondBidAmount))
        ).to.be.true;
      });

      it('Auction should be extended by time set up by publisher in case of a bid placed when less than that time is left', async function () {
        const oneMinuteInSeconds = BigNumber.from(60);
        const fiveMinutes = oneMinuteInSeconds.mul(5);
        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: auctionCollectModule.address,
            collectModuleInitData: await getAuctionCollectModuleInitData({
              minTimeAfterBid: fiveMinutes,
            }),
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: [],
          })
        ).to.not.be.reverted;
        const pubId = FIRST_PUB_ID + 1;
        await expect(
          auctionCollectModule.connect(bidder).bid(FIRST_PROFILE_ID, pubId, DEFAULT_AMOUNT, 0)
        ).to.not.be.reverted;
        let auction = await auctionCollectModule.getAuctionData(FIRST_PROFILE_ID, pubId);
        expect(auction.endTimestamp.eq(auction.startTimestamp.add(auction.duration)));
        const endTimestampAfterFirstBid = auction.endTimestamp;
        const secondBidTimestamp = endTimestampAfterFirstBid.sub(oneMinuteInSeconds).toNumber();
        await setNextBlockTimestamp(secondBidTimestamp);
        await expect(
          auctionCollectModule
            .connect(anotherBidder)
            .bid(FIRST_PROFILE_ID, pubId, DEFAULT_AMOUNT.add(DEFAULT_MIN_BID_INCREMENT), 0)
        ).to.not.be.reverted;
        auction = await auctionCollectModule.getAuctionData(FIRST_PROFILE_ID, pubId);
        expect(auction.endTimestamp.eq(auction.minTimeAfterBid + secondBidTimestamp)).to.be.true;
      });

      it('Referrer profile ID should be set properly and only at first bid of each one', async function () {
        let bidAmount = DEFAULT_AMOUNT;
        await lensHub.createProfile({
          to: anotherBidder.address,
          handle: 'referrer.lens',
          imageURI: MOCK_URI,
          followModule: ethers.constants.AddressZero,
          followModuleInitData: [],
          followNFTURI: MOCK_FOLLOW_NFT_URI,
        });
        const mirrorerProfileId = FIRST_PROFILE_ID + 1;
        await expect(
          lensHub.connect(anotherBidder).mirror({
            profileId: mirrorerProfileId,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: FIRST_PUB_ID,
            referenceModuleData: [],
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: [],
          })
        ).to.not.be.reverted;
        const mirrorPubId = FIRST_PUB_ID;
        // Bidder places his first bid through original publication
        await expect(
          auctionCollectModule.connect(bidder).bid(FIRST_PUB_ID, FIRST_PUB_ID, bidAmount, 0)
        ).to.not.be.reverted;
        // Bidder's referrer profile ID should be 0, which means no referrer
        expect(
          await auctionCollectModule.getReferrerProfileIdOf(
            FIRST_PROFILE_ID,
            FIRST_PUB_ID,
            bidder.address
          )
        ).to.be.equals(0);
        // Another bidder places his first bid through its own mirror publication
        bidAmount = bidAmount.add(DEFAULT_MIN_BID_INCREMENT);
        await expect(
          auctionCollectModule
            .connect(anotherBidder)
            .bid(mirrorerProfileId, mirrorPubId, bidAmount, 0)
        ).to.not.be.reverted;
        // Another bidder's referrer profile ID should be his own profile
        expect(
          await auctionCollectModule.getReferrerProfileIdOf(
            FIRST_PROFILE_ID,
            FIRST_PUB_ID,
            anotherBidder.address
          )
        ).to.be.equals(mirrorerProfileId);
        // Bidder places his second bid through another bidder's mirror
        bidAmount = bidAmount.add(DEFAULT_MIN_BID_INCREMENT);
        await expect(
          auctionCollectModule.connect(bidder).bid(mirrorerProfileId, mirrorPubId, bidAmount, 0)
        ).to.not.be.reverted;
        // Bidder's referrer profile ID should still be 0, as referrer is set only through first bid of each bidder
        expect(
          await auctionCollectModule.getReferrerProfileIdOf(
            FIRST_PROFILE_ID,
            FIRST_PUB_ID,
            bidder.address
          )
        ).to.be.equals(0);
      });
    });
  });

  context('Bid with signature', function () {
    beforeEach(async function () {
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
      await mintAndApproveCurrency({});
      await mintAndApproveCurrency({ owner: anotherBidder });
    });

    context('Negatives', function () {
      it('User should fail to bid if bidder does not match signer', async function () {
        const signature = await signBidWithSigMessage({ signer: anotherBidder });
        await expect(
          auctionCollectModule.bidWithSig(
            FIRST_PROFILE_ID,
            FIRST_PUB_ID,
            DEFAULT_AMOUNT,
            FIRST_FOLLOW_NFT_ID,
            bidder.address,
            signature
          )
        ).to.be.revertedWith(ERRORS.SIGNATURE_INVALID);
      });

      it('User should fail to bid if signed message deadline was exceeded', async function () {
        const expiredDeadline = ethers.constants.One;
        const signature = await signBidWithSigMessage({
          signer: bidder,
          deadline: expiredDeadline,
        });
        expect(expiredDeadline.lt(await getTimestamp())).to.be.true;
        await expect(
          auctionCollectModule.bidWithSig(
            FIRST_PROFILE_ID,
            FIRST_PUB_ID,
            DEFAULT_AMOUNT,
            FIRST_FOLLOW_NFT_ID,
            bidder.address,
            signature
          )
        ).to.be.revertedWith(ERRORS.SIGNATURE_EXPIRED);
      });

      it('User should fail to bid if signed message had wrong nonce', async function () {
        const currentNonce = await auctionCollectModule.nonces(bidder.address);
        const invalidNonce = await currentNonce.add(5);
        const signature = await signBidWithSigMessage({ signer: bidder, nonce: invalidNonce });
        await expect(
          auctionCollectModule.bidWithSig(
            FIRST_PROFILE_ID,
            FIRST_PUB_ID,
            DEFAULT_AMOUNT,
            FIRST_FOLLOW_NFT_ID,
            bidder.address,
            signature
          )
        ).to.be.revertedWith(ERRORS.SIGNATURE_INVALID);
      });

      it('User should fail to bid if signed message domain had wrong version', async function () {
        const invalidVersion = '0';
        const invalidDomain: Domain = {
          name: 'AuctionCollectModule',
          version: invalidVersion,
          chainId: chainId,
          verifyingContract: auctionCollectModule.address,
        };
        const signature = await signBidWithSigMessage({ signer: bidder, domain: invalidDomain });
        await expect(
          auctionCollectModule.bidWithSig(
            FIRST_PROFILE_ID,
            FIRST_PUB_ID,
            DEFAULT_AMOUNT,
            FIRST_FOLLOW_NFT_ID,
            bidder.address,
            signature
          )
        ).to.be.revertedWith(ERRORS.SIGNATURE_INVALID);
      });

      it('User should fail to bid if signed message domain had wrong chain ID', async function () {
        const invalidChainId = 69;
        expect(chainId).to.not.equals(invalidChainId);
        const invalidDomain: Domain = {
          name: 'AuctionCollectModule',
          version: '1',
          chainId: invalidChainId,
          verifyingContract: auctionCollectModule.address,
        };
        const signature = await signBidWithSigMessage({ signer: bidder, domain: invalidDomain });
        await expect(
          auctionCollectModule.bidWithSig(
            FIRST_PROFILE_ID,
            FIRST_PUB_ID,
            DEFAULT_AMOUNT,
            FIRST_FOLLOW_NFT_ID,
            bidder.address,
            signature
          )
        ).to.be.revertedWith(ERRORS.SIGNATURE_INVALID);
      });

      it('User should fail to bid if signed message domain had wrong verifying contract', async function () {
        const invalidVerifyingContract = (
          await new AuctionCollectModule__factory(deployer).deploy(
            lensHub.address,
            moduleGlobals.address
          )
        ).address;
        const invalidDomain: Domain = {
          name: 'AuctionCollectModule',
          version: '1',
          chainId: chainId,
          verifyingContract: invalidVerifyingContract,
        };
        const signature = await signBidWithSigMessage({ signer: bidder, domain: invalidDomain });
        await expect(
          auctionCollectModule.bidWithSig(
            FIRST_PROFILE_ID,
            FIRST_PUB_ID,
            DEFAULT_AMOUNT,
            FIRST_FOLLOW_NFT_ID,
            bidder.address,
            signature
          )
        ).to.be.revertedWith(ERRORS.SIGNATURE_INVALID);
      });

      it('User should fail to bid if signed message domain had wrong name', async function () {
        const invalidName = 'Auction Collect Module';
        const invalidDomain: Domain = {
          name: invalidName,
          version: '1',
          chainId: chainId,
          verifyingContract: auctionCollectModule.address,
        };
        const signature = await signBidWithSigMessage({ signer: bidder, domain: invalidDomain });
        await expect(
          auctionCollectModule.bidWithSig(
            FIRST_PROFILE_ID,
            FIRST_PUB_ID,
            DEFAULT_AMOUNT,
            FIRST_FOLLOW_NFT_ID,
            bidder.address,
            signature
          )
        ).to.be.revertedWith(ERRORS.SIGNATURE_INVALID);
      });
    });

    context('Scenarios', function () {
      beforeEach(async function () {
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
        await mintAndApproveCurrency({});
        await mintAndApproveCurrency({ owner: anotherBidder });
      });

      it('Funds should be deposited into the contract when a signature-based bid is placed', async function () {
        const bidderBalanceBeforeBid = await currency.balanceOf(bidder.address);
        const moduleBalanceBeforeBid = await currency.balanceOf(auctionCollectModule.address);
        expect(moduleBalanceBeforeBid.isZero()).to.be.true;
        const signature = await signBidWithSigMessage({ signer: bidder });
        const tx = auctionCollectModule
          .connect(anotherUser)
          .bidWithSig(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_AMOUNT, 0, bidder.address, signature);
        const txReceipt = await waitForTx(tx);
        const txTimestamp = await getTimestamp();
        const endTimestamp = DEFAULT_DURATION.add(txTimestamp);
        matchEvent(
          txReceipt,
          'BidPlaced',
          [
            FIRST_PROFILE_ID,
            FIRST_PUB_ID,
            0,
            DEFAULT_AMOUNT,
            0,
            bidder.address,
            endTimestamp,
            txTimestamp,
          ],
          auctionCollectModule
        );
        const bidderBalanceAfterBid = await currency.balanceOf(bidder.address);
        const moduleBalanceAfterBid = await currency.balanceOf(auctionCollectModule.address);
        expect(moduleBalanceAfterBid.eq(DEFAULT_AMOUNT)).to.be.true;
        expect(bidderBalanceAfterBid.eq(bidderBalanceBeforeBid.sub(DEFAULT_AMOUNT))).to.be.true;
      });

      it('Funds should be returned to previous winner when a better bid is placed by another bidder', async function () {
        const bidderBalanceBeforeBids = await currency.balanceOf(bidder.address);
        const anotherBidderBalanceBeforeBids = await currency.balanceOf(anotherBidder.address);
        const moduleBalanceBeforeBids = await currency.balanceOf(auctionCollectModule.address);
        expect(moduleBalanceBeforeBids.isZero()).to.be.true;
        let signature = await signBidWithSigMessage({ signer: bidder });
        await expect(
          auctionCollectModule
            .connect(anotherUser)
            .bidWithSig(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID,
              DEFAULT_AMOUNT,
              0,
              bidder.address,
              signature
            )
        ).to.not.be.reverted;
        const bidderBalanceAfter1stBid = await currency.balanceOf(bidder.address);
        const anotherBidderAfter1stBid = await currency.balanceOf(anotherBidder.address);
        const moduleBalanceAfter1stBid = await currency.balanceOf(auctionCollectModule.address);
        expect(anotherBidderBalanceBeforeBids.eq(anotherBidderAfter1stBid)).to.be.true;
        expect(moduleBalanceAfter1stBid.eq(DEFAULT_AMOUNT)).to.be.true;
        expect(bidderBalanceAfter1stBid.eq(bidderBalanceBeforeBids.sub(DEFAULT_AMOUNT))).to.be.true;
        const secondBidAmount = DEFAULT_AMOUNT.add(DEFAULT_MIN_BID_INCREMENT);
        signature = await signBidWithSigMessage({
          signer: anotherBidder,
          amount: secondBidAmount,
        });
        await expect(
          auctionCollectModule
            .connect(anotherUser)
            .bidWithSig(
              FIRST_PROFILE_ID,
              FIRST_PUB_ID,
              secondBidAmount,
              0,
              anotherBidder.address,
              signature
            )
        ).to.not.be.reverted;
        const bidderBalanceAfterBids = await currency.balanceOf(bidder.address);
        const anotherBidderBalanceAfterBids = await currency.balanceOf(anotherBidder.address);
        const moduleBalanceAfterBids = await currency.balanceOf(auctionCollectModule.address);
        expect(bidderBalanceAfterBids.eq(bidderBalanceAfterBids)).to.be.true;
        expect(moduleBalanceAfterBids.eq(secondBidAmount)).to.be.true;
        expect(
          anotherBidderBalanceAfterBids.eq(anotherBidderBalanceBeforeBids.sub(secondBidAmount))
        ).to.be.true;
      });

      it('Auction should be extended by time set up by publisher in case of a bid placed when less than that time is left', async function () {
        const oneMinuteInSeconds = BigNumber.from(60);
        const fiveMinutes = oneMinuteInSeconds.mul(5);
        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: auctionCollectModule.address,
            collectModuleInitData: await getAuctionCollectModuleInitData({
              minTimeAfterBid: fiveMinutes,
            }),
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: [],
          })
        ).to.not.be.reverted;
        const pubId = FIRST_PUB_ID + 1;
        let signature = await signBidWithSigMessage({ signer: bidder, pubId: pubId });
        await expect(
          auctionCollectModule
            .connect(anotherUser)
            .bidWithSig(FIRST_PROFILE_ID, pubId, DEFAULT_AMOUNT, 0, bidder.address, signature)
        ).to.not.be.reverted;
        let auction = await auctionCollectModule.getAuctionData(FIRST_PROFILE_ID, pubId);
        expect(auction.endTimestamp.eq(auction.startTimestamp.add(auction.duration)));
        const endTimestampAfterFirstBid = auction.endTimestamp;
        const secondBidTimestamp = endTimestampAfterFirstBid.sub(oneMinuteInSeconds).toNumber();
        const secondBidAmount = DEFAULT_AMOUNT.add(DEFAULT_MIN_BID_INCREMENT);
        await setNextBlockTimestamp(secondBidTimestamp);
        signature = await signBidWithSigMessage({
          signer: anotherBidder,
          pubId: pubId,
          amount: secondBidAmount,
        });
        await expect(
          auctionCollectModule
            .connect(anotherUser)
            .bidWithSig(
              FIRST_PROFILE_ID,
              pubId,
              secondBidAmount,
              0,
              anotherBidder.address,
              signature
            )
        ).to.not.be.reverted;
        auction = await auctionCollectModule.getAuctionData(FIRST_PROFILE_ID, pubId);
        expect(auction.endTimestamp.eq(auction.minTimeAfterBid + secondBidTimestamp)).to.be.true;
      });

      it('Referrer profile ID should be set properly and only at first bid of each one', async function () {
        let bidAmount = DEFAULT_AMOUNT;
        await lensHub.createProfile({
          to: anotherBidder.address,
          handle: 'referrer.lens',
          imageURI: MOCK_URI,
          followModule: ethers.constants.AddressZero,
          followModuleInitData: [],
          followNFTURI: MOCK_FOLLOW_NFT_URI,
        });
        const mirrorerProfileId = FIRST_PROFILE_ID + 1;
        await expect(
          lensHub.connect(anotherBidder).mirror({
            profileId: mirrorerProfileId,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: FIRST_PUB_ID,
            referenceModuleData: [],
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: [],
          })
        ).to.not.be.reverted;
        const mirrorPubId = FIRST_PUB_ID;
        // Bidder places his first bid through original publication
        let signature = await signBidWithSigMessage({ signer: bidder, amount: bidAmount });
        await expect(
          auctionCollectModule
            .connect(anotherUser)
            .bidWithSig(FIRST_PUB_ID, FIRST_PUB_ID, bidAmount, 0, bidder.address, signature)
        ).to.not.be.reverted;
        // Bidder's referrer profile ID should be 0, which means no referrer
        expect(
          await auctionCollectModule.getReferrerProfileIdOf(
            FIRST_PROFILE_ID,
            FIRST_PUB_ID,
            bidder.address
          )
        ).to.be.equals(0);
        // Another bidder places his first bid through its own mirror publication
        bidAmount = bidAmount.add(DEFAULT_MIN_BID_INCREMENT);
        signature = await signBidWithSigMessage({
          signer: anotherBidder,
          profileId: mirrorerProfileId,
          pubId: mirrorPubId,
          amount: bidAmount,
        });
        await expect(
          auctionCollectModule
            .connect(anotherUser)
            .bidWithSig(
              mirrorerProfileId,
              mirrorPubId,
              bidAmount,
              0,
              anotherBidder.address,
              signature
            )
        ).to.not.be.reverted;
        // Another bidder's referrer profile ID should be his own profile
        expect(
          await auctionCollectModule.getReferrerProfileIdOf(
            FIRST_PROFILE_ID,
            FIRST_PUB_ID,
            anotherBidder.address
          )
        ).to.be.equals(mirrorerProfileId);
        // Bidder places his second bid through another bidder's mirror
        bidAmount = bidAmount.add(DEFAULT_MIN_BID_INCREMENT);
        signature = await signBidWithSigMessage({
          signer: bidder,
          profileId: mirrorerProfileId,
          pubId: mirrorPubId,
          amount: bidAmount,
        });
        await expect(
          auctionCollectModule
            .connect(anotherUser)
            .bidWithSig(mirrorerProfileId, mirrorPubId, bidAmount, 0, bidder.address, signature)
        ).to.not.be.reverted;
        // Bidder's referrer profile ID should still be 0, as referrer is set only through first bid of each bidder
        expect(
          await auctionCollectModule.getReferrerProfileIdOf(
            FIRST_PROFILE_ID,
            FIRST_PUB_ID,
            bidder.address
          )
        ).to.be.equals(0);
      });
    });
  });

  context('Process collect and fees', function () {
    beforeEach(async function () {
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
      await mintAndApproveCurrency({});
      await mintAndApproveCurrency({ owner: anotherBidder });
    });

    context('Negatives', function () {
      it('Process collect call should fail if caller is not the hub', async function () {
        await expect(
          auctionCollectModule
            .connect(bidder)
            .processCollect(0, bidder.address, FIRST_PROFILE_ID, FIRST_PUB_ID, [])
        ).to.be.revertedWith(ERRORS.NOT_HUB);
      });

      it('User should fail to process collect over unexistent publication', async function () {
        const unexistentPubId = 69;
        await expect(
          lensHub.connect(bidder).collect(FIRST_PROFILE_ID, unexistentPubId, [])
        ).to.be.revertedWith(ERRORS.PUBLICATION_DOES_NOT_EXIST);
      });

      it('User should fail to process collect over existent yet unavailable auction', async function () {
        const futureTimestamp = (await getTimestamp()) + ONE_DAY_IN_SECONDS;
        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: auctionCollectModule.address,
            collectModuleInitData: await getAuctionCollectModuleInitData({
              availableSinceTimestamp: futureTimestamp,
            }),
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: [],
          })
        ).to.not.be.reverted;
        const pubId = FIRST_PUB_ID + 1;
        await expect(
          lensHub.connect(bidder).collect(FIRST_PROFILE_ID, pubId, [])
        ).to.be.revertedWith(ERRORS.UNAVAILABLE_AUCTION);
      });

      it('User should fail to process collect over existent available but unstarted auction', async function () {
        await expect(
          lensHub.connect(bidder).collect(FIRST_PROFILE_ID, FIRST_PUB_ID, [])
        ).to.be.revertedWith(ERRORS.ONGOING_AUCTION);
      });

      it('User should fail to process collect over active auction', async function () {
        await expect(
          auctionCollectModule
            .connect(bidder)
            .bid(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_AMOUNT, 0)
        ).to.not.be.reverted;
        await expect(
          lensHub.connect(bidder).collect(FIRST_PROFILE_ID, FIRST_PUB_ID, [])
        ).to.be.revertedWith(ERRORS.ONGOING_AUCTION);
      });

      it('User should fail to process collect if he is not the auction winner', async function () {
        await expect(
          auctionCollectModule
            .connect(bidder)
            .bid(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_AMOUNT, 0)
        ).to.not.be.reverted;
        await simulateAuctionEnd({});
        const auction = await auctionCollectModule.getAuctionData(FIRST_PROFILE_ID, FIRST_PUB_ID);
        expect(auction.winner).to.be.equals(bidder.address);
        expect(bidder.address).to.not.be.equal(anotherUser.address);
        await expect(
          lensHub.connect(anotherUser).collect(FIRST_PROFILE_ID, FIRST_PUB_ID, [])
        ).to.be.revertedWith(ERRORS.MODULE_DATA_MISMATCH);
      });

      it('User should fail to process collect if collects through a publication that makes lens hub pass a wrong referrer profile ID', async function () {
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
        const referrerProfileId = FIRST_PROFILE_ID + 1;
        await expect(
          lensHub.connect(anotherUser).mirror({
            profileId: referrerProfileId,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: FIRST_PUB_ID,
            referenceModuleData: [],
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: [],
          })
        ).to.not.be.reverted;
        const mirrorPubId = FIRST_PUB_ID;
        await expect(
          auctionCollectModule
            .connect(bidder)
            .bid(referrerProfileId, mirrorPubId, DEFAULT_AMOUNT, 0)
        ).to.not.be.reverted;
        await simulateAuctionEnd({});
        const auction = await auctionCollectModule.getAuctionData(FIRST_PROFILE_ID, FIRST_PUB_ID);
        expect(auction.winner).to.be.equals(bidder.address);
        const referrerProfileIdOfWinner = await auctionCollectModule.getReferrerProfileIdOf(
          FIRST_PROFILE_ID,
          FIRST_PUB_ID,
          auction.winner
        );
        expect(referrerProfileIdOfWinner).to.be.equals(referrerProfileId);
        await expect(
          lensHub.connect(bidder).collect(FIRST_PROFILE_ID, FIRST_PUB_ID, [])
        ).to.be.revertedWith(ERRORS.MODULE_DATA_MISMATCH);
      });

      it('User should fail to process collect if publication was already collected', async function () {
        await expect(
          auctionCollectModule
            .connect(bidder)
            .bid(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_AMOUNT, 0)
        ).to.not.be.reverted;
        await simulateAuctionEnd({});
        await expect(
          lensHub.connect(bidder).collect(FIRST_PROFILE_ID, FIRST_PUB_ID, [])
        ).to.not.be.reverted;
        const auction = await auctionCollectModule.getAuctionData(FIRST_PROFILE_ID, FIRST_PUB_ID);
        expect(auction.collected).to.be.true;
        await expect(
          lensHub.connect(bidder).collect(FIRST_PROFILE_ID, FIRST_PUB_ID, [])
        ).to.be.revertedWith(ERRORS.COLLECT_ALREADY_PROCESSED);
      });

      it('User should fail to process collect if is only for followers and and he is not following the publication owner', async function () {
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
        await expect(lensHub.connect(bidder).follow([FIRST_PROFILE_ID], [[]])).to.not.be.reverted;
        await expect(
          auctionCollectModule
            .connect(bidder)
            .bid(FIRST_PROFILE_ID, pubId, DEFAULT_AMOUNT, FIRST_FOLLOW_NFT_ID)
        ).to.not.be.reverted;
        await simulateAuctionEnd({
          pubId: pubId,
        });
        const followNftAddress = await lensHub.getFollowNFT(FIRST_PROFILE_ID);
        const followNft = await FollowNFT__factory.connect(followNftAddress, bidder);
        await expect(
          followNft.transferFrom(bidder.address, anotherUser.address, FIRST_FOLLOW_NFT_ID)
        ).to.not.be.reverted;
        await expect(
          lensHub
            .connect(bidder)
            .collect(FIRST_PROFILE_ID, pubId, abiCoder.encode(['uint256'], [FIRST_FOLLOW_NFT_ID]))
        ).to.be.revertedWith(ERRORS.FOLLOW_INVALID);
      });

      it('User should fail to process collect if is only for followers and and he followed publication owner after auction started', async function () {
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
        await expect(lensHub.connect(bidder).follow([FIRST_PROFILE_ID], [[]])).to.not.be.reverted;
        await expect(
          auctionCollectModule
            .connect(bidder)
            .bid(FIRST_PROFILE_ID, pubId, DEFAULT_AMOUNT, FIRST_FOLLOW_NFT_ID)
        ).to.not.be.reverted;
        await simulateAuctionEnd({
          pubId: pubId,
        });
        const followNftAddress = await lensHub.getFollowNFT(FIRST_PROFILE_ID);
        const followNft = await FollowNFT__factory.connect(followNftAddress, bidder);
        await expect(followNft.burn(FIRST_FOLLOW_NFT_ID)).to.not.be.reverted;
        await expect(lensHub.connect(bidder).follow([FIRST_PROFILE_ID], [[]])).to.not.be.reverted;
        const newFollowNftId = FIRST_FOLLOW_NFT_ID + 1;
        await expect(
          lensHub
            .connect(bidder)
            .collect(FIRST_PROFILE_ID, pubId, abiCoder.encode(['uint256'], [newFollowNftId]))
        ).to.be.revertedWith(ERRORS.FOLLOW_INVALID);
      });

      it('User should fail to process collect if auction was open for everyone and he passed any arbitrary data', async function () {
        await expect(
          auctionCollectModule
            .connect(bidder)
            .bid(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_AMOUNT, 0)
        ).to.not.be.reverted;
        await simulateAuctionEnd({});
        const dataThatShouldNotBePassed = abiCoder.encode(['uint256'], [FIRST_FOLLOW_NFT_ID]);
        await expect(
          lensHub.connect(bidder).collect(FIRST_PROFILE_ID, FIRST_PUB_ID, dataThatShouldNotBePassed)
        ).to.be.revertedWith(ERRORS.MODULE_DATA_MISMATCH);
      });

      it('User should fail to process fees over unexistent publication', async function () {
        const unexistentPubId = 69;
        await expect(
          auctionCollectModule.connect(bidder).processCollectFee(FIRST_PROFILE_ID, unexistentPubId)
        ).to.be.revertedWith(ERRORS.UNAVAILABLE_AUCTION);
      });

      it('User should fail to process fees over publication that uses another collect module', async function () {
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
          auctionCollectModule.connect(bidder).processCollectFee(FIRST_PROFILE_ID, pubId)
        ).to.be.revertedWith(ERRORS.UNAVAILABLE_AUCTION);
      });

      it('User should fail to process fees over unstarted auction', async function () {
        await expect(
          auctionCollectModule.connect(bidder).processCollectFee(FIRST_PROFILE_ID, FIRST_PUB_ID)
        ).to.be.revertedWith(ERRORS.ONGOING_AUCTION);
      });

      it('User should fail to process fees over active auction', async function () {
        await expect(
          auctionCollectModule
            .connect(bidder)
            .bid(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_AMOUNT, 0)
        ).to.not.be.reverted;
        await expect(
          auctionCollectModule.connect(bidder).processCollectFee(FIRST_PROFILE_ID, FIRST_PUB_ID)
        ).to.be.revertedWith(ERRORS.ONGOING_AUCTION);
      });

      it('User should fail to process fees over auction that already processed fees through process collect call', async function () {
        await expect(
          auctionCollectModule
            .connect(bidder)
            .bid(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_AMOUNT, 0)
        ).to.not.be.reverted;
        await simulateAuctionEnd({});
        const auctionBeforeCollect = await auctionCollectModule.getAuctionData(
          FIRST_PROFILE_ID,
          FIRST_PUB_ID
        );
        expect(auctionBeforeCollect.collected).to.be.false;
        expect(auctionBeforeCollect.feeProcessed).to.be.false;
        await expect(
          lensHub.connect(bidder).collect(FIRST_PROFILE_ID, FIRST_PUB_ID, [])
        ).to.not.be.reverted;
        const auctionAfterCollect = await auctionCollectModule.getAuctionData(
          FIRST_PROFILE_ID,
          FIRST_PUB_ID
        );
        expect(auctionAfterCollect.collected).to.be.true;
        expect(auctionAfterCollect.feeProcessed).to.be.true;
        await expect(
          auctionCollectModule.connect(bidder).processCollectFee(FIRST_PROFILE_ID, FIRST_PUB_ID)
        ).to.be.revertedWith(ERRORS.FEE_ALREADY_PROCESSED);
      });

      it('User should fail to process fees over auction that already processed fee through process fees call', async function () {
        await expect(
          auctionCollectModule
            .connect(bidder)
            .bid(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_AMOUNT, 0)
        ).to.not.be.reverted;
        await simulateAuctionEnd({});
        const auctionBeforeCollectFee = await auctionCollectModule.getAuctionData(
          FIRST_PROFILE_ID,
          FIRST_PUB_ID
        );
        expect(auctionBeforeCollectFee.collected).to.be.false;
        expect(auctionBeforeCollectFee.feeProcessed).to.be.false;
        await expect(
          auctionCollectModule.connect(bidder).processCollectFee(FIRST_PROFILE_ID, FIRST_PUB_ID)
        ).to.not.be.reverted;
        const auctionAfterCollectFee = await auctionCollectModule.getAuctionData(
          FIRST_PROFILE_ID,
          FIRST_PUB_ID
        );
        expect(auctionAfterCollectFee.collected).to.be.false;
        expect(auctionAfterCollectFee.feeProcessed).to.be.true;
        await expect(
          auctionCollectModule.connect(bidder).processCollectFee(FIRST_PROFILE_ID, FIRST_PUB_ID)
        ).to.be.revertedWith(ERRORS.FEE_ALREADY_PROCESSED);
      });
    });

    context('Scenarios', function () {
      it('User should win and collect an only followers auction borrowing different follow NFTs through the entire process', async function () {
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
        // Two different users follow publisher profile before the auction starts
        await expect(
          lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
        ).to.not.be.reverted;
        await expect(
          lensHub.connect(thirdUser).follow([FIRST_PROFILE_ID], [[]])
        ).to.not.be.reverted;
        const secondFollowNftId = FIRST_FOLLOW_NFT_ID + 1;
        const followNftAddress = await lensHub.getFollowNFT(FIRST_PROFILE_ID);
        const followNft = await FollowNFT__factory.connect(followNftAddress, bidder);
        // We verify the users has a follow NFT now but the bidder does not
        expect((await followNft.balanceOf(bidder.address)).isZero()).to.be.true;
        expect((await followNft.balanceOf(anotherUser.address)).isZero()).to.be.false;
        expect((await followNft.balanceOf(thirdUser.address)).isZero()).to.be.false;
        // Bidder takes follow NFT from anotherUser, places a bid and return it back
        await expect(
          followNft
            .connect(anotherUser)
            .transferFrom(anotherUser.address, bidder.address, FIRST_FOLLOW_NFT_ID)
        ).to.not.be.reverted;
        await expect(
          auctionCollectModule
            .connect(bidder)
            .bid(FIRST_PROFILE_ID, pubId, DEFAULT_AMOUNT, FIRST_FOLLOW_NFT_ID)
        ).to.not.be.reverted;
        await expect(
          followNft
            .connect(bidder)
            .transferFrom(bidder.address, anotherUser.address, FIRST_FOLLOW_NFT_ID)
        ).to.not.be.reverted;
        // Auction ends, bidder becomes the winner
        await simulateAuctionEnd({
          pubId: pubId,
        });
        // Bidder takes follow NFT from thirdUser to be able to collect
        await expect(
          followNft
            .connect(thirdUser)
            .transferFrom(thirdUser.address, bidder.address, secondFollowNftId)
        ).to.not.be.reverted;
        await expect(
          lensHub
            .connect(bidder)
            .collect(FIRST_PROFILE_ID, pubId, abiCoder.encode(['uint256'], [secondFollowNftId]))
        ).to.not.be.reverted;
      });

      it('Anoyone should succeed to trigger collect fees processing after auction finishes before the winner collects', async function () {
        await expect(
          auctionCollectModule
            .connect(bidder)
            .bid(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_AMOUNT, 0)
        ).to.not.be.reverted;
        await simulateAuctionEnd({});
        const treasuryBalanceBeforeFees = await currency.balanceOf(treasury.address);
        const recipientBalanceBeforeFees = await currency.balanceOf(feeRecipient.address);
        const tx = auctionCollectModule
          .connect(anotherUser)
          .processCollectFee(FIRST_PROFILE_ID, FIRST_PUB_ID);
        const txReceipt = await waitForTx(tx);
        matchEvent(
          txReceipt,
          'FeeProcessed',
          [FIRST_PROFILE_ID, FIRST_PUB_ID, await getTimestamp()],
          auctionCollectModule
        );
        const treasuryBalanceAfterFees = await currency.balanceOf(treasury.address);
        const recipientBalanceAfterFees = await currency.balanceOf(feeRecipient.address);
        await expect(
          lensHub.connect(bidder).collect(FIRST_PROFILE_ID, FIRST_PUB_ID, [])
        ).to.not.be.reverted;
        const treasuryBalanceAfterCollect = await currency.balanceOf(treasury.address);
        const recipientBalanceAfterCollect = await currency.balanceOf(feeRecipient.address);
        const expectedTreausyFee = DEFAULT_AMOUNT.mul(TREASURY_FEE_BPS).div(BPS_MAX);
        const expectedRecipientFee = DEFAULT_AMOUNT.sub(expectedTreausyFee);
        expect(treasuryBalanceBeforeFees.isZero()).to.be.true;
        expect(recipientBalanceBeforeFees.isZero()).to.be.true;
        expect(treasuryBalanceAfterFees).to.be.equals(expectedTreausyFee);
        expect(recipientBalanceAfterFees).to.be.equals(expectedRecipientFee);
        expect(treasuryBalanceAfterCollect).to.be.equals(treasuryBalanceAfterFees);
        expect(recipientBalanceAfterCollect).to.be.equals(recipientBalanceAfterFees);
      });

      it('Owner of referrer profile should receive a cut of the collect fees', async function () {
        const treasuryBalanceBeforeCollect = await currency.balanceOf(treasury.address);
        const referrerBalanceBeforeCollect = await currency.balanceOf(anotherUser.address);
        const recipientBalanceBeforeCollect = await currency.balanceOf(feeRecipient.address);
        // Creates referrer profile who mirrors publication
        await lensHub.createProfile({
          to: anotherUser.address,
          handle: 'referrer.lens',
          imageURI: MOCK_URI,
          followModule: ethers.constants.AddressZero,
          followModuleInitData: [],
          followNFTURI: MOCK_FOLLOW_NFT_URI,
        });
        const referrerProfileId = FIRST_PROFILE_ID + 1;
        await expect(
          lensHub.connect(anotherUser).mirror({
            profileId: referrerProfileId,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: FIRST_PUB_ID,
            referenceModuleData: [],
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: [],
          })
        ).to.not.be.reverted;
        // Bidder places a bid through mirrored publication
        await expect(
          auctionCollectModule
            .connect(bidder)
            .bid(referrerProfileId, FIRST_PUB_ID, DEFAULT_AMOUNT, 0)
        ).to.not.be.reverted;
        // Auction finishes
        await simulateAuctionEnd({});
        // Collects through same mirrored publication as it is required
        await expect(
          lensHub.connect(bidder).collect(referrerProfileId, FIRST_PUB_ID, [])
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

      it('Owner of referrer profile should not receive collect fees if referrer fee was set to zero', async function () {
        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: auctionCollectModule.address,
            collectModuleInitData: await getAuctionCollectModuleInitData({ referralFee: 0 }),
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: [],
          })
        ).to.not.be.reverted;
        const pubId = FIRST_PUB_ID + 1;
        const treasuryBalanceBeforeCollect = await currency.balanceOf(treasury.address);
        const referrerBalanceBeforeCollect = await currency.balanceOf(anotherUser.address);
        const recipientBalanceBeforeCollect = await currency.balanceOf(feeRecipient.address);
        // Creates referrer profile who mirrors publication
        await lensHub.createProfile({
          to: anotherUser.address,
          handle: 'referrer.lens',
          imageURI: MOCK_URI,
          followModule: ethers.constants.AddressZero,
          followModuleInitData: [],
          followNFTURI: MOCK_FOLLOW_NFT_URI,
        });
        const referrerProfileId = FIRST_PROFILE_ID + 1;
        await expect(
          lensHub.connect(anotherUser).mirror({
            profileId: referrerProfileId,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: pubId,
            referenceModuleData: [],
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: [],
          })
        ).to.not.be.reverted;
        // Bidder places a bid through mirrored publication
        await expect(
          auctionCollectModule
            .connect(bidder)
            .bid(referrerProfileId, FIRST_PUB_ID, DEFAULT_AMOUNT, 0)
        ).to.not.be.reverted;
        // Auction finishes
        await simulateAuctionEnd({ pubId: pubId });
        // Collects through same mirrored publication as it is required
        await expect(
          lensHub.connect(bidder).collect(referrerProfileId, FIRST_PUB_ID, [])
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

      it('Fee recipient should receive all collect fees when publication is collected through original publication and treasury fee was set to zero', async function () {
        await expect(moduleGlobals.connect(governance).setTreasuryFee(0)).to.not.be.reverted;
        const treasuryBalanceBeforeCollect = await currency.balanceOf(treasury.address);
        const recipientBalanceBeforeCollect = await currency.balanceOf(feeRecipient.address);
        await expect(
          auctionCollectModule
            .connect(bidder)
            .bid(FIRST_PROFILE_ID, FIRST_PUB_ID, DEFAULT_AMOUNT, 0)
        ).to.not.be.reverted;
        await simulateAuctionEnd({});
        await expect(
          lensHub.connect(bidder).collect(FIRST_PUB_ID, FIRST_PUB_ID, [])
        ).to.not.be.reverted;
        const treasuryBalanceAfterCollect = await currency.balanceOf(treasury.address);
        const recipientBalanceAfterCollect = await currency.balanceOf(feeRecipient.address);
        expect(treasuryBalanceAfterCollect).to.be.equals(treasuryBalanceBeforeCollect);
        expect(recipientBalanceAfterCollect).to.be.equals(
          recipientBalanceBeforeCollect.add(DEFAULT_AMOUNT)
        );
      });

      it('Fee recipient and referrer profile owners should share the entire fees between them if treasury feet was set to zero', async function () {
        await expect(moduleGlobals.connect(governance).setTreasuryFee(0)).to.not.be.reverted;
        const treasuryBalanceBeforeCollect = await currency.balanceOf(treasury.address);
        const referrerBalanceBeforeCollect = await currency.balanceOf(anotherUser.address);
        const recipientBalanceBeforeCollect = await currency.balanceOf(feeRecipient.address);
        // Creates referrer profile who mirrors publication
        await lensHub.createProfile({
          to: anotherUser.address,
          handle: 'referrer.lens',
          imageURI: MOCK_URI,
          followModule: ethers.constants.AddressZero,
          followModuleInitData: [],
          followNFTURI: MOCK_FOLLOW_NFT_URI,
        });
        const referrerProfileId = FIRST_PROFILE_ID + 1;
        await expect(
          lensHub.connect(anotherUser).mirror({
            profileId: referrerProfileId,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: FIRST_PUB_ID,
            referenceModuleData: [],
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: [],
          })
        ).to.not.be.reverted;
        // Bidder places a bid through mirrored publication
        await expect(
          auctionCollectModule
            .connect(bidder)
            .bid(referrerProfileId, FIRST_PUB_ID, DEFAULT_AMOUNT, 0)
        ).to.not.be.reverted;
        // Auction finishes
        await simulateAuctionEnd({});
        // Collects through same mirrored publication as it is required
        await expect(
          lensHub.connect(bidder).collect(referrerProfileId, FIRST_PUB_ID, [])
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

      it('Publication owner should get the entire collect fees if referrer and treasury fees were set to zero', async function () {
        await expect(moduleGlobals.connect(governance).setTreasuryFee(0)).to.not.be.reverted;
        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: auctionCollectModule.address,
            collectModuleInitData: await getAuctionCollectModuleInitData({ referralFee: 0 }),
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: [],
          })
        ).to.not.be.reverted;
        const pubId = FIRST_PUB_ID + 1;
        const treasuryBalanceBeforeCollect = await currency.balanceOf(treasury.address);
        const referrerBalanceBeforeCollect = await currency.balanceOf(anotherUser.address);
        const recipientBalanceBeforeCollect = await currency.balanceOf(feeRecipient.address);
        // Creates referrer profile who mirrors publication
        await lensHub.createProfile({
          to: anotherUser.address,
          handle: 'referrer.lens',
          imageURI: MOCK_URI,
          followModule: ethers.constants.AddressZero,
          followModuleInitData: [],
          followNFTURI: MOCK_FOLLOW_NFT_URI,
        });
        const referrerProfileId = FIRST_PROFILE_ID + 1;
        await expect(
          lensHub.connect(anotherUser).mirror({
            profileId: referrerProfileId,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: pubId,
            referenceModuleData: [],
            referenceModule: ethers.constants.AddressZero,
            referenceModuleInitData: [],
          })
        ).to.not.be.reverted;
        // Bidder places a bid through mirrored publication
        await expect(
          auctionCollectModule
            .connect(bidder)
            .bid(referrerProfileId, FIRST_PUB_ID, DEFAULT_AMOUNT, 0)
        ).to.not.be.reverted;
        // Auction finishes
        await simulateAuctionEnd({ pubId: pubId });
        // Collects through same mirrored publication as it is required
        await expect(
          lensHub.connect(bidder).collect(referrerProfileId, FIRST_PUB_ID, [])
        ).to.not.be.reverted;
        const treasuryBalanceAfterCollect = await currency.balanceOf(treasury.address);
        const referrerBalanceAfterCollect = await currency.balanceOf(anotherUser.address);
        const recipientBalanceAfterCollect = await currency.balanceOf(feeRecipient.address);
        expect(treasuryBalanceAfterCollect).to.be.equals(treasuryBalanceBeforeCollect);
        expect(referrerBalanceAfterCollect).to.be.equals(referrerBalanceBeforeCollect);
        expect(recipientBalanceAfterCollect).to.be.equals(
          recipientBalanceBeforeCollect.add(DEFAULT_AMOUNT)
        );
      });
    });
  });
});
