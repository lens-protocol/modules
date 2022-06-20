import { BigNumber, BigNumberish } from '@ethersproject/bignumber';
import { parseEther } from '@ethersproject/units';
import '@nomiclabs/hardhat-ethers';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import { FollowNFT__factory } from '../../../typechain';
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
} from './../../__setup.spec';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { publisher } from '../../__setup.spec';
import { getTimestamp, setNextBlockTimestamp } from '../../helpers/utils';
import { signBidWithSigMessage } from '../../helpers/signatures/modules/collect/auction-collect-module';
import { Domain } from '../../helpers/signatures/utils';

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

  context('Negatives', function () {
    context('Publication creation', function () {
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
  });
});
