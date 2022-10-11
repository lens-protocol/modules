import { BigNumber } from '@ethersproject/bignumber';
import { parseEther } from '@ethersproject/units';
import '@nomiclabs/hardhat-ethers';
import { expect } from 'chai';
import { MAX_UINT256, ONE_DAY, ZERO_ADDRESS } from '../../helpers/constants';
import { ERRORS } from '../../helpers/errors';
import { getTimestamp, matchEvent, setNextBlockTimestamp, waitForTx } from '../../helpers/utils';
import {
  abiCoder,
  BPS_MAX,
  currency,
  currencyTwo,
  FIRST_PROFILE_ID,
  governance,
  lensHub,
  makeSuiteCleanRoom,
  MOCK_FOLLOW_NFT_URI,
  MOCK_PROFILE_HANDLE,
  MOCK_PROFILE_URI,
  MOCK_URI,
  moduleGlobals,
  REFERRAL_FEE_BPS,
  TREASURY_FEE_BPS,
  user,
  anotherUser,
  treasury,
  mockVault,
  mockVaultTwo,
  erc4626FeeCollectModule,
} from '../../__setup.spec';

makeSuiteCleanRoom('ERC4626 Collect Module', function () {
  const DEFAULT_COLLECT_PRICE = parseEther('10');
  const DEFAULT_COLLECT_LIMIT = 3;
  const DEFAULT_FOLLOWER_ONLY = true;
  const DEFAULT_END_TIMESTAMP = 0; // no endtime

  beforeEach(async function () {
    await expect(
      lensHub.createProfile({
        to: user.address,
        handle: MOCK_PROFILE_HANDLE,
        imageURI: MOCK_PROFILE_URI,
        followModule: ZERO_ADDRESS,
        followModuleInitData: [],
        followNFTURI: MOCK_FOLLOW_NFT_URI,
      })
    ).to.not.be.reverted;

    await expect(
      lensHub.connect(governance).whitelistCollectModule(erc4626FeeCollectModule.address, true)
    ).to.not.be.reverted;
    await expect(
      moduleGlobals.connect(governance).whitelistCurrency(currency.address, true)
    ).to.not.be.reverted;
    // currencyTwo must NOT be on the whitelist
    await expect(
      moduleGlobals.connect(governance).whitelistCurrency(currencyTwo.address, false)
    ).to.not.be.reverted;
  });

  context('Negatives', function () {
    context('Publication Creation', function () {
      it('user should fail to post with ERC4626 fee collect module using a vault with an unwhitelisted currency', async function () {
        const collectModuleInitData = abiCoder.encode(
          ['uint96', 'uint256', 'address', 'address', 'uint16', 'bool', 'uint72'],
          [
            DEFAULT_COLLECT_LIMIT,
            DEFAULT_COLLECT_PRICE,
            mockVaultTwo.address,
            user.address,
            REFERRAL_FEE_BPS,
            DEFAULT_FOLLOWER_ONLY,
            DEFAULT_END_TIMESTAMP,
          ]
        );
        await expect(
          lensHub.connect(user).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: erc4626FeeCollectModule.address,
            collectModuleInitData: collectModuleInitData,
            referenceModule: ZERO_ADDRESS,
            referenceModuleInitData: [],
          })
        ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
      });

      it('user should fail to post with ERC4626 fee collect module if not called via the Hub', async function () {
        const collectModuleInitData = abiCoder.encode(
          ['uint96', 'uint256', 'address', 'address', 'uint16', 'bool', 'uint72'],
          [
            DEFAULT_COLLECT_LIMIT,
            DEFAULT_COLLECT_PRICE,
            mockVaultTwo.address,
            user.address,
            REFERRAL_FEE_BPS,
            DEFAULT_FOLLOWER_ONLY,
            DEFAULT_END_TIMESTAMP,
          ]
        );
        await expect(
          erc4626FeeCollectModule
            .connect(user)
            .initializePublicationCollectModule(FIRST_PROFILE_ID, 1, collectModuleInitData)
        ).to.be.revertedWith(ERRORS.NOT_HUB);
      });

      it('user should fail to post with ERC4626 fee collect module using zero recipient', async function () {
        const collectModuleInitData = abiCoder.encode(
          ['uint96', 'uint256', 'address', 'address', 'uint16', 'bool', 'uint72'],
          [
            DEFAULT_COLLECT_LIMIT,
            DEFAULT_COLLECT_PRICE,
            mockVault.address,
            ZERO_ADDRESS,
            REFERRAL_FEE_BPS,
            DEFAULT_FOLLOWER_ONLY,
            DEFAULT_END_TIMESTAMP,
          ]
        );
        await expect(
          lensHub.connect(user).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: erc4626FeeCollectModule.address,
            collectModuleInitData: collectModuleInitData,
            referenceModule: ZERO_ADDRESS,
            referenceModuleInitData: [],
          })
        ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
      });

      it('user should fail to post with ERC4626 fee collect module using referral fee greater than max BPS', async function () {
        const collectModuleInitData = abiCoder.encode(
          ['uint96', 'uint256', 'address', 'address', 'uint16', 'bool', 'uint72'],
          [
            DEFAULT_COLLECT_LIMIT,
            DEFAULT_COLLECT_PRICE,
            mockVault.address,
            user.address,
            10001,
            DEFAULT_FOLLOWER_ONLY,
            DEFAULT_END_TIMESTAMP,
          ]
        );
        await expect(
          lensHub.connect(user).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: erc4626FeeCollectModule.address,
            collectModuleInitData: collectModuleInitData,
            referenceModule: ZERO_ADDRESS,
            referenceModuleInitData: [],
          })
        ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
      });

      it('user should fail to post with ERC4626 fee collect module using end timestamp in the past', async function () {
        const collectModuleInitData = abiCoder.encode(
          ['uint96', 'uint256', 'address', 'address', 'uint16', 'bool', 'uint72'],
          [
            DEFAULT_COLLECT_LIMIT,
            9999,
            mockVault.address,
            user.address,
            REFERRAL_FEE_BPS,
            DEFAULT_FOLLOWER_ONLY,
            1,
          ]
        );
        await expect(
          lensHub.connect(user).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: erc4626FeeCollectModule.address,
            collectModuleInitData: collectModuleInitData,
            referenceModule: ZERO_ADDRESS,
            referenceModuleInitData: [],
          })
        ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
      });
    });

    context('Collecting', function () {
      beforeEach(async function () {
        const currentTimePlus1Day = BigNumber.from(await getTimestamp()).add(ONE_DAY);
        const collectModuleInitData = abiCoder.encode(
          ['uint96', 'uint256', 'address', 'address', 'uint16', 'bool', 'uint72'],
          [
            DEFAULT_COLLECT_LIMIT,
            DEFAULT_COLLECT_PRICE,
            mockVault.address,
            user.address,
            REFERRAL_FEE_BPS,
            DEFAULT_FOLLOWER_ONLY,
            currentTimePlus1Day,
          ]
        );
        await expect(
          lensHub.connect(user).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: erc4626FeeCollectModule.address,
            collectModuleInitData: collectModuleInitData,
            referenceModule: ZERO_ADDRESS,
            referenceModuleInitData: [],
          })
        ).to.not.be.reverted;
      });

      it('Second User should fail to collect without following if followerOnly is true', async function () {
        const data = abiCoder.encode(
          ['address', 'uint256'],
          [currency.address, DEFAULT_COLLECT_PRICE]
        );
        await expect(
          lensHub.connect(anotherUser).collect(FIRST_PROFILE_ID, 1, data)
        ).to.be.revertedWith(ERRORS.FOLLOW_INVALID);
      });

      it('Second User should be able to collect without following if followerOnly is false', async function () {
        // Post new publication with followerOnly == false
        const currentTimePlus1Day = BigNumber.from(await getTimestamp()).add(ONE_DAY);
        const collectModuleInitDataTwo = abiCoder.encode(
          ['uint96', 'uint256', 'address', 'address', 'uint16', 'bool', 'uint72'],
          [
            DEFAULT_COLLECT_LIMIT,
            DEFAULT_COLLECT_PRICE,
            mockVault.address,
            user.address,
            REFERRAL_FEE_BPS,
            false, // followerOnly = false
            currentTimePlus1Day,
          ]
        );
        await expect(
          lensHub.connect(user).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: erc4626FeeCollectModule.address,
            collectModuleInitData: collectModuleInitDataTwo,
            referenceModule: ZERO_ADDRESS,
            referenceModuleInitData: [],
          })
        ).to.not.be.reverted;

        const dataTwo = abiCoder.encode(
          ['address', 'uint256'],
          [currency.address, DEFAULT_COLLECT_PRICE]
        );
        await expect(currency.mint(anotherUser.address, MAX_UINT256)).to.not.be.reverted;
        await expect(
          currency.connect(anotherUser).approve(erc4626FeeCollectModule.address, MAX_UINT256)
        ).to.not.be.reverted;
        await expect(
          // PubID = 2 here to test the followerOnly = false pub
          lensHub.connect(anotherUser).collect(FIRST_PROFILE_ID, 2, dataTwo)
        ).to.not.be.reverted;
      });

      it('Second User should fail to collect passing a different expected price in data', async function () {
        await expect(
          lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
        ).to.not.be.reverted;

        const data = abiCoder.encode(
          ['address', 'uint256'],
          [currency.address, DEFAULT_COLLECT_PRICE.div(2)]
        );
        await expect(
          lensHub.connect(anotherUser).collect(FIRST_PROFILE_ID, 1, data)
        ).to.be.revertedWith(ERRORS.MODULE_DATA_MISMATCH);
      });

      it('Second User should fail to collect passing a different expected currency in data', async function () {
        await expect(
          lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
        ).to.not.be.reverted;

        const data = abiCoder.encode(['address', 'uint256'], [user.address, DEFAULT_COLLECT_PRICE]);
        await expect(
          lensHub.connect(anotherUser).collect(FIRST_PROFILE_ID, 1, data)
        ).to.be.revertedWith(ERRORS.MODULE_DATA_MISMATCH);
      });

      it('Second User should fail to collect without first approving module with currency', async function () {
        await expect(currency.mint(anotherUser.address, MAX_UINT256)).to.not.be.reverted;

        await expect(
          lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
        ).to.not.be.reverted;

        const data = abiCoder.encode(
          ['address', 'uint256'],
          [currency.address, DEFAULT_COLLECT_PRICE]
        );
        await expect(
          lensHub.connect(anotherUser).collect(FIRST_PROFILE_ID, 1, data)
        ).to.be.revertedWith(ERRORS.ERC20_INSUFFICIENT_ALLOWANCE);
      });

      it('Second User should fail to collect after publication has expired', async function () {
        await expect(currency.mint(anotherUser.address, MAX_UINT256)).to.not.be.reverted;

        await expect(
          lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
        ).to.not.be.reverted;

        const data = abiCoder.encode(
          ['address', 'uint256'],
          [currency.address, DEFAULT_COLLECT_PRICE]
        );

        // Fast forward 2 days, publication expired after 1 day
        await setNextBlockTimestamp(
          parseInt(BigNumber.from(await getTimestamp()).toString()) + ONE_DAY
        );

        await expect(
          lensHub.connect(anotherUser).collect(FIRST_PROFILE_ID, 1, data)
        ).to.be.revertedWith(ERRORS.COLLECT_EXPIRED);
      });

      it('Second User should mirror the original post, fail to collect from their mirror without following the original profile', async function () {
        const secondProfileId = FIRST_PROFILE_ID + 1;
        await expect(
          lensHub.createProfile({
            to: anotherUser.address,
            handle: 'usertwo',
            imageURI: MOCK_PROFILE_URI,
            followModule: ZERO_ADDRESS,
            followModuleInitData: [],
            followNFTURI: MOCK_FOLLOW_NFT_URI,
          })
        ).to.not.be.reverted;

        await expect(
          lensHub.connect(anotherUser).mirror({
            profileId: secondProfileId,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: 1,
            referenceModule: ZERO_ADDRESS,
            referenceModuleData: [],
            referenceModuleInitData: [],
          })
        ).to.not.be.reverted;

        const data = abiCoder.encode(
          ['address', 'uint256'],
          [currency.address, DEFAULT_COLLECT_PRICE]
        );
        await expect(
          lensHub.connect(anotherUser).collect(secondProfileId, 1, data)
        ).to.be.revertedWith(ERRORS.FOLLOW_INVALID);
      });

      it('Second User should mirror the original post, fail to collect from their mirror passing a different expected price in data', async function () {
        const secondProfileId = FIRST_PROFILE_ID + 1;
        await expect(
          lensHub.createProfile({
            to: anotherUser.address,
            handle: 'usertwo',
            imageURI: MOCK_PROFILE_URI,
            followModule: ZERO_ADDRESS,
            followModuleInitData: [],
            followNFTURI: MOCK_FOLLOW_NFT_URI,
          })
        ).to.not.be.reverted;
        await expect(
          lensHub.connect(anotherUser).mirror({
            profileId: secondProfileId,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: 1,
            referenceModule: ZERO_ADDRESS,
            referenceModuleData: [],
            referenceModuleInitData: [],
          })
        ).to.not.be.reverted;

        await expect(
          lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
        ).to.not.be.reverted;
        const data = abiCoder.encode(
          ['address', 'uint256'],
          [currency.address, DEFAULT_COLLECT_PRICE.div(2)]
        );
        await expect(
          lensHub.connect(anotherUser).collect(secondProfileId, 1, data)
        ).to.be.revertedWith(ERRORS.MODULE_DATA_MISMATCH);
      });

      it('Second User should mirror the original post, fail to collect from their mirror passing a different expected currency in data', async function () {
        const secondProfileId = FIRST_PROFILE_ID + 1;
        await expect(
          lensHub.createProfile({
            to: anotherUser.address,
            handle: 'usertwo',
            imageURI: MOCK_PROFILE_URI,
            followModule: ZERO_ADDRESS,
            followModuleInitData: [],
            followNFTURI: MOCK_FOLLOW_NFT_URI,
          })
        ).to.not.be.reverted;
        await expect(
          lensHub.connect(anotherUser).mirror({
            profileId: secondProfileId,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: 1,
            referenceModule: ZERO_ADDRESS,
            referenceModuleData: [],
            referenceModuleInitData: [],
          })
        ).to.not.be.reverted;

        await expect(
          lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
        ).to.not.be.reverted;
        const data = abiCoder.encode(['address', 'uint256'], [user.address, DEFAULT_COLLECT_PRICE]);
        await expect(
          lensHub.connect(anotherUser).collect(secondProfileId, 1, data)
        ).to.be.revertedWith(ERRORS.MODULE_DATA_MISMATCH);
      });
    });
  });

  context('Scenarios', function () {
    it('User should post with ERC4626 fee collect module as the collect module and data, correct events should be emitted', async function () {
      const collectModuleInitData = abiCoder.encode(
        ['uint96', 'uint256', 'address', 'address', 'uint16', 'bool', 'uint72'],
        [
          DEFAULT_COLLECT_LIMIT,
          DEFAULT_COLLECT_PRICE,
          mockVault.address,
          user.address,
          REFERRAL_FEE_BPS,
          DEFAULT_FOLLOWER_ONLY,
          DEFAULT_END_TIMESTAMP,
        ]
      );
      const tx = lensHub.connect(user).post({
        profileId: FIRST_PROFILE_ID,
        contentURI: MOCK_URI,
        collectModule: erc4626FeeCollectModule.address,
        collectModuleInitData: collectModuleInitData,
        referenceModule: ZERO_ADDRESS,
        referenceModuleInitData: [],
      });

      const receipt = await waitForTx(tx);

      expect(receipt.logs.length).to.eq(1);
      matchEvent(receipt, 'PostCreated', [
        FIRST_PROFILE_ID,
        1,
        MOCK_URI,
        erc4626FeeCollectModule.address,
        collectModuleInitData,
        ZERO_ADDRESS,
        [],
        await getTimestamp(),
      ]);
    });

    it('User should post with ERC4626 fee collect module as the collect module and data, fetched publication data should be accurate', async function () {
      const collectModuleInitData = abiCoder.encode(
        ['uint96', 'uint256', 'address', 'address', 'uint16', 'bool', 'uint72'],
        [
          DEFAULT_COLLECT_LIMIT,
          DEFAULT_COLLECT_PRICE,
          mockVault.address,
          user.address,
          REFERRAL_FEE_BPS,
          DEFAULT_FOLLOWER_ONLY,
          DEFAULT_END_TIMESTAMP,
        ]
      );
      await expect(
        lensHub.connect(user).post({
          profileId: FIRST_PROFILE_ID,
          contentURI: MOCK_URI,
          collectModule: erc4626FeeCollectModule.address,
          collectModuleInitData: collectModuleInitData,
          referenceModule: ZERO_ADDRESS,
          referenceModuleInitData: [],
        })
      ).to.not.be.reverted;

      const fetchedData = await erc4626FeeCollectModule.getPublicationData(FIRST_PROFILE_ID, 1);
      expect(fetchedData.collectLimit).to.eq(DEFAULT_COLLECT_LIMIT);
      expect(fetchedData.amount).to.eq(DEFAULT_COLLECT_PRICE);
      expect(fetchedData.recipient).to.eq(user.address);
      expect(fetchedData.currency).to.eq(currency.address);
      expect(fetchedData.referralFee).to.eq(REFERRAL_FEE_BPS);
      expect(fetchedData.vault).to.eq(mockVault.address);
      expect(fetchedData.followerOnly).to.eq(DEFAULT_FOLLOWER_ONLY);
    });

    it('User should post with ERC4626 fee collect module as the collect module and data, user two follows, then collects and pays fee, fee distribution is valid', async function () {
      const collectModuleInitData = abiCoder.encode(
        ['uint96', 'uint256', 'address', 'address', 'uint16', 'bool', 'uint72'],
        [
          DEFAULT_COLLECT_LIMIT,
          DEFAULT_COLLECT_PRICE,
          mockVault.address,
          user.address,
          REFERRAL_FEE_BPS,
          DEFAULT_FOLLOWER_ONLY,
          DEFAULT_END_TIMESTAMP,
        ]
      );
      await expect(
        lensHub.connect(user).post({
          profileId: FIRST_PROFILE_ID,
          contentURI: MOCK_URI,
          collectModule: erc4626FeeCollectModule.address,
          collectModuleInitData: collectModuleInitData,
          referenceModule: ZERO_ADDRESS,
          referenceModuleInitData: [],
        })
      ).to.not.be.reverted;

      await expect(currency.mint(anotherUser.address, MAX_UINT256)).to.not.be.reverted;
      await expect(
        currency.connect(anotherUser).approve(erc4626FeeCollectModule.address, MAX_UINT256)
      ).to.not.be.reverted;
      await expect(
        lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
      ).to.not.be.reverted;
      const data = abiCoder.encode(
        ['address', 'uint256'],
        [currency.address, DEFAULT_COLLECT_PRICE]
      );
      await expect(
        lensHub.connect(anotherUser).collect(FIRST_PROFILE_ID, 1, data)
      ).to.not.be.reverted;

      const expectedTreasuryAmount = BigNumber.from(DEFAULT_COLLECT_PRICE)
        .mul(TREASURY_FEE_BPS)
        .div(BPS_MAX);
      const expectedRecipientAmount =
        BigNumber.from(DEFAULT_COLLECT_PRICE).sub(expectedTreasuryAmount);

      expect(await currency.balanceOf(anotherUser.address)).to.eq(
        BigNumber.from(MAX_UINT256).sub(DEFAULT_COLLECT_PRICE)
      );
      // Exchange rate is 1:1 assets:shares so same amount used
      expect(await mockVault.balanceOf(user.address)).to.eq(expectedRecipientAmount);
      expect(await currency.balanceOf(user.address)).to.eq(0); // no currency amount received
      expect(await currency.balanceOf(treasury.address)).to.eq(expectedTreasuryAmount);
    });

    it('User should post with ERC4626 fee collect module as the collect module and data, user two follows, then collects and pays fee, treasury fee is 0%', async function () {
      // Set treasury fee to 0% (0 bps)
      const NEW_TREASURY_FEE_BPS = 0;
      await moduleGlobals.connect(governance).setTreasuryFee(NEW_TREASURY_FEE_BPS);

      const collectModuleInitData = abiCoder.encode(
        ['uint96', 'uint256', 'address', 'address', 'uint16', 'bool', 'uint72'],
        [
          DEFAULT_COLLECT_LIMIT,
          DEFAULT_COLLECT_PRICE,
          mockVault.address,
          user.address,
          REFERRAL_FEE_BPS,
          DEFAULT_FOLLOWER_ONLY,
          DEFAULT_END_TIMESTAMP,
        ]
      );
      await expect(
        lensHub.connect(user).post({
          profileId: FIRST_PROFILE_ID,
          contentURI: MOCK_URI,
          collectModule: erc4626FeeCollectModule.address,
          collectModuleInitData: collectModuleInitData,
          referenceModule: ZERO_ADDRESS,
          referenceModuleInitData: [],
        })
      ).to.not.be.reverted;

      await expect(currency.mint(anotherUser.address, MAX_UINT256)).to.not.be.reverted;
      await expect(
        currency.connect(anotherUser).approve(erc4626FeeCollectModule.address, MAX_UINT256)
      ).to.not.be.reverted;
      await expect(
        lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
      ).to.not.be.reverted;
      const data = abiCoder.encode(
        ['address', 'uint256'],
        [currency.address, DEFAULT_COLLECT_PRICE]
      );
      await expect(
        lensHub.connect(anotherUser).collect(FIRST_PROFILE_ID, 1, data)
      ).to.not.be.reverted;

      const expectedTreasuryAmount = BigNumber.from(DEFAULT_COLLECT_PRICE)
        .mul(NEW_TREASURY_FEE_BPS)
        .div(BPS_MAX);
      const expectedRecipientAmount =
        BigNumber.from(DEFAULT_COLLECT_PRICE).sub(expectedTreasuryAmount);

      expect(await currency.balanceOf(anotherUser.address)).to.eq(
        BigNumber.from(MAX_UINT256).sub(DEFAULT_COLLECT_PRICE)
      );
      // Exchange rate is 1:1 assets:shares so same amount used
      expect(await mockVault.balanceOf(user.address)).to.eq(expectedRecipientAmount);
      expect(await currency.balanceOf(user.address)).to.eq(0); // no currency amount received
      expect(await currency.balanceOf(treasury.address)).to.eq(expectedTreasuryAmount);
    });

    it('User should post with ERC4626 fee collect module as the collect module and data, user two follows, then collects twice, fee distribution is valid', async function () {
      const collectModuleInitData = abiCoder.encode(
        ['uint96', 'uint256', 'address', 'address', 'uint16', 'bool', 'uint72'],
        [
          DEFAULT_COLLECT_LIMIT,
          DEFAULT_COLLECT_PRICE,
          mockVault.address,
          user.address,
          REFERRAL_FEE_BPS,
          DEFAULT_FOLLOWER_ONLY,
          DEFAULT_END_TIMESTAMP,
        ]
      );
      await expect(
        lensHub.connect(user).post({
          profileId: FIRST_PROFILE_ID,
          contentURI: MOCK_URI,
          collectModule: erc4626FeeCollectModule.address,
          collectModuleInitData: collectModuleInitData,
          referenceModule: ZERO_ADDRESS,
          referenceModuleInitData: [],
        })
      ).to.not.be.reverted;

      await expect(currency.mint(anotherUser.address, MAX_UINT256)).to.not.be.reverted;
      await expect(
        currency.connect(anotherUser).approve(erc4626FeeCollectModule.address, MAX_UINT256)
      ).to.not.be.reverted;
      await expect(
        lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
      ).to.not.be.reverted;
      const data = abiCoder.encode(
        ['address', 'uint256'],
        [currency.address, DEFAULT_COLLECT_PRICE]
      );
      await expect(
        lensHub.connect(anotherUser).collect(FIRST_PROFILE_ID, 1, data)
      ).to.not.be.reverted;
      await expect(
        lensHub.connect(anotherUser).collect(FIRST_PROFILE_ID, 1, data)
      ).to.not.be.reverted;

      const expectedTreasuryAmount = BigNumber.from(DEFAULT_COLLECT_PRICE)
        .mul(TREASURY_FEE_BPS)
        .div(BPS_MAX);
      const expectedRecipientAmount =
        BigNumber.from(DEFAULT_COLLECT_PRICE).sub(expectedTreasuryAmount);

      expect(await currency.balanceOf(anotherUser.address)).to.eq(
        BigNumber.from(MAX_UINT256).sub(BigNumber.from(DEFAULT_COLLECT_PRICE).mul(2))
      );
      // Exchange rate is 1:1 assets:shares so same amount used
      expect(await mockVault.balanceOf(user.address)).to.eq(expectedRecipientAmount.mul(2));
      expect(await currency.balanceOf(user.address)).to.eq(0); // no currency amount received
      expect(await currency.balanceOf(treasury.address)).to.eq(expectedTreasuryAmount.mul(2));
    });

    it('User should post with ERC4626 fee collect module as the collect module and data, user two mirrors, follows, then collects from their mirror and pays fee, fee distribution is valid', async function () {
      // Set treasury fee to 0% (0 bps)
      const NEW_TREASURY_FEE_BPS = 0;
      await moduleGlobals.connect(governance).setTreasuryFee(NEW_TREASURY_FEE_BPS);

      const secondProfileId = FIRST_PROFILE_ID + 1;
      const collectModuleInitData = abiCoder.encode(
        ['uint96', 'uint256', 'address', 'address', 'uint16', 'bool', 'uint72'],
        [
          DEFAULT_COLLECT_LIMIT,
          DEFAULT_COLLECT_PRICE,
          mockVault.address,
          user.address,
          REFERRAL_FEE_BPS,
          DEFAULT_FOLLOWER_ONLY,
          DEFAULT_END_TIMESTAMP,
        ]
      );

      await expect(
        lensHub.connect(user).post({
          profileId: FIRST_PROFILE_ID,
          contentURI: MOCK_URI,
          collectModule: erc4626FeeCollectModule.address,
          collectModuleInitData: collectModuleInitData,
          referenceModule: ZERO_ADDRESS,
          referenceModuleInitData: [],
        })
      ).to.not.be.reverted;

      await expect(
        lensHub.createProfile({
          to: anotherUser.address,
          handle: 'usertwo',
          imageURI: MOCK_PROFILE_URI,
          followModule: ZERO_ADDRESS,
          followModuleInitData: [],
          followNFTURI: MOCK_FOLLOW_NFT_URI,
        })
      ).to.not.be.reverted;

      await expect(
        lensHub.connect(anotherUser).mirror({
          profileId: secondProfileId,
          profileIdPointed: FIRST_PROFILE_ID,
          pubIdPointed: 1,
          referenceModule: ZERO_ADDRESS,
          referenceModuleData: [],
          referenceModuleInitData: [],
        })
      ).to.not.be.reverted;

      await expect(currency.mint(anotherUser.address, MAX_UINT256)).to.not.be.reverted;
      await expect(
        currency.connect(anotherUser).approve(erc4626FeeCollectModule.address, MAX_UINT256)
      ).to.not.be.reverted;
      await expect(
        lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
      ).to.not.be.reverted;
      const data = abiCoder.encode(
        ['address', 'uint256'],
        [currency.address, DEFAULT_COLLECT_PRICE]
      );
      await expect(
        lensHub.connect(anotherUser).collect(secondProfileId, 1, data)
      ).to.not.be.reverted;

      const expectedTreasuryAmount = BigNumber.from(DEFAULT_COLLECT_PRICE)
        .mul(NEW_TREASURY_FEE_BPS)
        .div(BPS_MAX);
      const expectedReferralAmount = BigNumber.from(DEFAULT_COLLECT_PRICE)
        .sub(expectedTreasuryAmount)
        .mul(REFERRAL_FEE_BPS)
        .div(BPS_MAX);
      const expectedReferrerAmount = BigNumber.from(MAX_UINT256)
        .sub(DEFAULT_COLLECT_PRICE)
        .add(expectedReferralAmount);
      const expectedRecipientAmount = BigNumber.from(DEFAULT_COLLECT_PRICE)
        .sub(expectedTreasuryAmount)
        .sub(expectedReferralAmount);

      expect(await currency.balanceOf(anotherUser.address)).to.eq(expectedReferrerAmount);
      expect(await mockVault.balanceOf(anotherUser.address)).to.eq(0); // referrer receives currency not shares
      // Exchange rate is 1:1 assets:shares so same amount used
      expect(await mockVault.balanceOf(user.address)).to.eq(expectedRecipientAmount);
      expect(await currency.balanceOf(user.address)).to.eq(0); // no currency amount received by recipient
      expect(await currency.balanceOf(treasury.address)).to.eq(expectedTreasuryAmount);
    });

    it('User should post with ERC4626 fee collect module as the collect module and data, with no referral fee, user two mirrors, follows, then collects from their mirror and pays fee, fee distribution is valid', async function () {
      const secondProfileId = FIRST_PROFILE_ID + 1;
      const collectModuleInitData = abiCoder.encode(
        ['uint96', 'uint256', 'address', 'address', 'uint16', 'bool', 'uint72'],
        [
          DEFAULT_COLLECT_LIMIT,
          DEFAULT_COLLECT_PRICE,
          mockVault.address,
          user.address,
          0,
          DEFAULT_FOLLOWER_ONLY,
          DEFAULT_END_TIMESTAMP,
        ]
      );
      await expect(
        lensHub.connect(user).post({
          profileId: FIRST_PROFILE_ID,
          contentURI: MOCK_URI,
          collectModule: erc4626FeeCollectModule.address,
          collectModuleInitData: collectModuleInitData,
          referenceModule: ZERO_ADDRESS,
          referenceModuleInitData: [],
        })
      ).to.not.be.reverted;

      await expect(
        lensHub.createProfile({
          to: anotherUser.address,
          handle: 'usertwo',
          imageURI: MOCK_PROFILE_URI,
          followModule: ZERO_ADDRESS,
          followModuleInitData: [],
          followNFTURI: MOCK_FOLLOW_NFT_URI,
        })
      ).to.not.be.reverted;
      await expect(
        lensHub.connect(anotherUser).mirror({
          profileId: secondProfileId,
          profileIdPointed: FIRST_PROFILE_ID,
          pubIdPointed: 1,
          referenceModule: ZERO_ADDRESS,
          referenceModuleData: [],
          referenceModuleInitData: [],
        })
      ).to.not.be.reverted;

      await expect(currency.mint(anotherUser.address, MAX_UINT256)).to.not.be.reverted;
      await expect(
        currency.connect(anotherUser).approve(erc4626FeeCollectModule.address, MAX_UINT256)
      ).to.not.be.reverted;
      await expect(
        lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
      ).to.not.be.reverted;
      const data = abiCoder.encode(
        ['address', 'uint256'],
        [currency.address, DEFAULT_COLLECT_PRICE]
      );
      await expect(
        lensHub.connect(anotherUser).collect(secondProfileId, 1, data)
      ).to.not.be.reverted;

      const expectedTreasuryAmount = BigNumber.from(DEFAULT_COLLECT_PRICE)
        .mul(TREASURY_FEE_BPS)
        .div(BPS_MAX);
      const expectedRecipientAmount =
        BigNumber.from(DEFAULT_COLLECT_PRICE).sub(expectedTreasuryAmount);

      expect(await currency.balanceOf(anotherUser.address)).to.eq(
        BigNumber.from(MAX_UINT256).sub(DEFAULT_COLLECT_PRICE)
      );
      // Exchange rate is 1:1 assets:shares so same amount used
      expect(await mockVault.balanceOf(user.address)).to.eq(expectedRecipientAmount);
      expect(await currency.balanceOf(user.address)).to.eq(0); // no currency amount received by recipient
      expect(await currency.balanceOf(treasury.address)).to.eq(expectedTreasuryAmount);
    });

    it('User should post with ERC4626 fee collect module as the collect module and data, user two mirrors, follows, then collects once from the original, twice from the mirror, and fails to collect a third time from either the mirror or the original', async function () {
      const secondProfileId = FIRST_PROFILE_ID + 1;
      const collectModuleInitData = abiCoder.encode(
        ['uint96', 'uint256', 'address', 'address', 'uint16', 'bool', 'uint72'],
        [
          DEFAULT_COLLECT_LIMIT,
          DEFAULT_COLLECT_PRICE,
          mockVault.address,
          user.address,
          REFERRAL_FEE_BPS,
          DEFAULT_FOLLOWER_ONLY,
          DEFAULT_END_TIMESTAMP,
        ]
      );
      await expect(
        lensHub.connect(user).post({
          profileId: FIRST_PROFILE_ID,
          contentURI: MOCK_URI,
          collectModule: erc4626FeeCollectModule.address,
          collectModuleInitData: collectModuleInitData,
          referenceModule: ZERO_ADDRESS,
          referenceModuleInitData: [],
        })
      ).to.not.be.reverted;

      await expect(
        lensHub.createProfile({
          to: anotherUser.address,
          handle: 'usertwo',
          imageURI: MOCK_PROFILE_URI,
          followModule: ZERO_ADDRESS,
          followModuleInitData: [],
          followNFTURI: MOCK_FOLLOW_NFT_URI,
        })
      ).to.not.be.reverted;
      await expect(
        lensHub.connect(anotherUser).mirror({
          profileId: secondProfileId,
          profileIdPointed: FIRST_PROFILE_ID,
          pubIdPointed: 1,
          referenceModule: ZERO_ADDRESS,
          referenceModuleData: [],
          referenceModuleInitData: [],
        })
      ).to.not.be.reverted;

      await expect(currency.mint(anotherUser.address, MAX_UINT256)).to.not.be.reverted;
      await expect(
        currency.connect(anotherUser).approve(erc4626FeeCollectModule.address, MAX_UINT256)
      ).to.not.be.reverted;
      await expect(
        lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
      ).to.not.be.reverted;
      const data = abiCoder.encode(
        ['address', 'uint256'],
        [currency.address, DEFAULT_COLLECT_PRICE]
      );
      await expect(
        lensHub.connect(anotherUser).collect(FIRST_PROFILE_ID, 1, data)
      ).to.not.be.reverted;
      await expect(
        lensHub.connect(anotherUser).collect(secondProfileId, 1, data)
      ).to.not.be.reverted;
      await expect(
        lensHub.connect(anotherUser).collect(secondProfileId, 1, data)
      ).to.not.be.reverted;

      await expect(
        lensHub.connect(anotherUser).collect(FIRST_PROFILE_ID, 1, data)
      ).to.be.revertedWith(ERRORS.MINT_LIMIT_EXCEEDED);
      await expect(
        lensHub.connect(anotherUser).collect(secondProfileId, 1, data)
      ).to.be.revertedWith(ERRORS.MINT_LIMIT_EXCEEDED);
    });
  });
});
