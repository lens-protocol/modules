import { BigNumber } from '@ethersproject/bignumber';
import { parseEther } from '@ethersproject/units';
import '@nomiclabs/hardhat-ethers';
import { expect } from 'chai';
import { MaxUint256, AddressZero } from '@ethersproject/constants';
import { ERRORS } from '../../helpers/errors';
import { getTimestamp, matchEvent, setNextBlockTimestamp, waitForTx } from '../../helpers/utils';
import {
  abiCoder,
  BPS_MAX,
  currency,
  FIRST_PROFILE_ID,
  governance,
  lensHub,
  stepwiseCollectModule,
  makeSuiteCleanRoom,
  MOCK_FOLLOW_NFT_URI,
  MOCK_PROFILE_HANDLE,
  OTHER_MOCK_URI,
  MOCK_URI,
  moduleGlobals,
  REFERRAL_FEE_BPS,
  treasury,
  TREASURY_FEE_BPS,
  user,
  anotherUser,
} from '../../__setup.spec';

import { publisher } from '../../__setup.spec';

makeSuiteCleanRoom('Limited Timed Fee Collect Module', function () {
  const DEFAULT_COLLECT_PRICE = parseEther('10');
  const DEFAULT_COLLECT_LIMIT = 3;

  beforeEach(async function () {
    await expect(
      lensHub.createProfile({
        to: publisher.address,
        handle: MOCK_PROFILE_HANDLE,
        imageURI: MOCK_URI,
        followModule: AddressZero,
        followModuleInitData: [],
        followNFTURI: MOCK_FOLLOW_NFT_URI,
      })
    ).to.not.be.reverted;
  });

  context('Negatives', function () {
    context('Publication Creation', function () {
      it('user should fail to post with limited timed fee collect module using zero collect limit', async function () {
        const collectModuleInitData = abiCoder.encode(
          [
            'uint256',
            'address',
            'address',
            'uint16',
            'bool',
            'uint40',
            'tuple(uint256, uint256, uint256)',
          ],
          [
            0,
            currency.address,
            user.address,
            REFERRAL_FEE_BPS,
            true,
            1099511627775,
            [0, 0, DEFAULT_COLLECT_PRICE],
          ]
        );
        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: stepwiseCollectModule.address,
            collectModuleInitData: collectModuleInitData,
            referenceModule: AddressZero,
            referenceModuleInitData: [],
          })
        ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
      });

      it('user should fail to post with limited timed fee collect module using unwhitelisted currency', async function () {
        const collectModuleInitData = abiCoder.encode(
          [
            'uint256',
            'address',
            'address',
            'uint16',
            'bool',
            'uint40',
            'tuple(uint256, uint256, uint256)',
          ],
          [
            DEFAULT_COLLECT_LIMIT,
            anotherUser.address,
            user.address,
            REFERRAL_FEE_BPS,
            true,
            1099511627775,
            [0, 0, DEFAULT_COLLECT_PRICE],
          ]
        );
        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: stepwiseCollectModule.address,
            collectModuleInitData: collectModuleInitData,
            referenceModule: AddressZero,
            referenceModuleInitData: [],
          })
        ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
      });

      it('user should fail to post with limited timed fee collect module using zero recipient', async function () {
        const collectModuleInitData = abiCoder.encode(
          [
            'uint256',
            'address',
            'address',
            'uint16',
            'bool',
            'uint40',
            'tuple(uint256, uint256, uint256)',
          ],
          [
            DEFAULT_COLLECT_LIMIT,
            currency.address,
            AddressZero,
            REFERRAL_FEE_BPS,
            true,
            1099511627775,
            [0, 0, DEFAULT_COLLECT_PRICE],
          ]
        );
        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: stepwiseCollectModule.address,
            collectModuleInitData: collectModuleInitData,
            referenceModule: AddressZero,
            referenceModuleInitData: [],
          })
        ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
      });

      it('user should fail to post with limited timed fee collect module using referral fee greater than max BPS', async function () {
        const collectModuleInitData = abiCoder.encode(
          [
            'uint256',
            'address',
            'address',
            'uint16',
            'bool',
            'uint40',
            'tuple(uint256, uint256, uint256)',
          ],
          [
            DEFAULT_COLLECT_LIMIT,
            currency.address,
            user.address,
            10001,
            true,
            1099511627775,
            [0, 0, DEFAULT_COLLECT_PRICE],
          ]
        );
        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: stepwiseCollectModule.address,
            collectModuleInitData: collectModuleInitData,
            referenceModule: AddressZero,
            referenceModuleInitData: [],
          })
        ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
      });

      it('user should fail to post with limited timed fee collect module using a past timestamp', async function () {
        const collectModuleInitData = abiCoder.encode(
          [
            'uint256',
            'address',
            'address',
            'uint16',
            'bool',
            'uint40',
            'tuple(uint256, uint256, uint256)',
          ],
          [
            DEFAULT_COLLECT_LIMIT,
            currency.address,
            user.address,
            REFERRAL_FEE_BPS,
            true,
            1660000000,
            [0, 0, 0],
          ]
        );
        await expect(
          lensHub.connect(publisher).post({
            profileId: FIRST_PROFILE_ID,
            contentURI: MOCK_URI,
            collectModule: stepwiseCollectModule.address,
            collectModuleInitData: collectModuleInitData,
            referenceModule: AddressZero,
            referenceModuleInitData: [],
          })
        ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
      });
    });

    // context('Collecting', function () {
    //   beforeEach(async function () {
    //     const collectModuleInitData = abiCoder.encode(
    //       [
    //         'uint256',
    //         'address',
    //         'address',
    //         'uint16',
    //         'bool',
    //         'uint40',
    //         'tuple(uint256, uint256, uint256)',
    //       ],
    //       [
    //         DEFAULT_COLLECT_LIMIT,
    //         currency.address,
    //         user.address,
    //         REFERRAL_FEE_BPS,
    //         true,
    //         1099511627775,
    //         [0, 0, DEFAULT_COLLECT_PRICE],
    //       ]
    //     );
    //     await expect(
    //       lensHub.connect(publisher).post({
    //         profileId: FIRST_PROFILE_ID,
    //         contentURI: MOCK_URI,
    //         collectModule: stepwiseCollectModule.address,
    //         collectModuleInitData: collectModuleInitData,
    //         referenceModule: AddressZero,
    //         referenceModuleInitData: [],
    //       })
    //     ).to.not.be.reverted;
    //   });

    //   it('anotherUser should fail to process collect without being the hub', async function () {
    //     await expect(
    //       stepwiseCollectModule
    //         .connect(anotherUser)
    //         .processCollect(0, anotherUser.address, FIRST_PROFILE_ID, 1, [])
    //     ).to.be.revertedWith(ERRORS.NOT_HUB);
    //   });

    //   it('Governance should set the treasury fee BPS to zero, anotherUser collecting should not emit a transfer event to the treasury', async function () {
    //     await expect(moduleGlobals.connect(governance).setTreasuryFee(0)).to.not.be.reverted;
    //     const data = abiCoder.encode(
    //       ['address', 'uint256'],
    //       [currency.address, DEFAULT_COLLECT_PRICE]
    //     );
    //     await expect(
    //       lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
    //     ).to.not.be.reverted;

    //     await expect(currency.mint(anotherUser.address, MaxUint256)).to.not.be.reverted;
    //     await expect(
    //       currency.connect(anotherUser).approve(stepwiseCollectModule.address, MaxUint256)
    //     ).to.not.be.reverted;

    //     const tx = lensHub.connect(anotherUser).collect(FIRST_PROFILE_ID, 1, data);
    //     const receipt = await waitForTx(tx);

    //     let currencyEventCount = 0;
    //     for (let log of receipt.logs) {
    //       if (log.address == currency.address) {
    //         currencyEventCount++;
    //       }
    //     }
    //     expect(currencyEventCount).to.eq(1);
    //     matchEvent(
    //       receipt,
    //       'Transfer',
    //       [anotherUser.address, user.address, DEFAULT_COLLECT_PRICE],
    //       currency
    //     );
    //   });

    //   it('anotherUser should mirror the original post, governance should set the treasury fee BPS to zero, anotherUser collecting their mirror should not emit a transfer event to the treasury', async function () {
    //     const secondProfileId = FIRST_PROFILE_ID + 1;
    //     await expect(
    //       lensHub.connect(anotherUser).createProfile({
    //         to: anotherUser.address,
    //         handle: 'anotherUser',
    //         imageURI: OTHER_MOCK_URI,
    //         followModule: AddressZero,
    //         followModuleInitData: [],
    //         followNFTURI: MOCK_FOLLOW_NFT_URI,
    //       })
    //     ).to.not.be.reverted;
    //     await expect(
    //       lensHub.connect(anotherUser).mirror({
    //         profileId: secondProfileId,
    //         profileIdPointed: FIRST_PROFILE_ID,
    //         pubIdPointed: 1,
    //         referenceModuleData: [],
    //         referenceModule: AddressZero,
    //         referenceModuleInitData: [],
    //       })
    //     ).to.not.be.reverted;

    //     await expect(moduleGlobals.connect(governance).setTreasuryFee(0)).to.not.be.reverted;
    //     const data = abiCoder.encode(
    //       ['address', 'uint256'],
    //       [currency.address, DEFAULT_COLLECT_PRICE]
    //     );
    //     await expect(
    //       lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
    //     ).to.not.be.reverted;

    //     await expect(currency.mint(anotherUser.address, MaxUint256)).to.not.be.reverted;
    //     await expect(
    //       currency.connect(anotherUser).approve(stepwiseCollectModule.address, MaxUint256)
    //     ).to.not.be.reverted;

    //     const tx = lensHub.connect(anotherUser).collect(secondProfileId, 1, data);
    //     const receipt = await waitForTx(tx);

    //     let currencyEventCount = 0;
    //     for (let log of receipt.logs) {
    //       if (log.address == currency.address) {
    //         currencyEventCount++;
    //       }
    //     }
    //     expect(currencyEventCount).to.eq(2);

    //     const expectedReferralAmount = BigNumber.from(DEFAULT_COLLECT_PRICE)
    //       .mul(REFERRAL_FEE_BPS)
    //       .div(BPS_MAX);
    //     const amount = DEFAULT_COLLECT_PRICE.sub(expectedReferralAmount);

    //     matchEvent(receipt, 'Transfer', [anotherUser.address, user.address, amount], currency);

    //     matchEvent(
    //       receipt,
    //       'Transfer',
    //       [anotherUser.address, anotherUser.address, expectedReferralAmount],
    //       currency
    //     );
    //   });

    //   it('anotherUser should fail to collect without following', async function () {
    //     const data = abiCoder.encode(
    //       ['address', 'uint256'],
    //       [currency.address, DEFAULT_COLLECT_PRICE]
    //     );
    //     await expect(
    //       lensHub.connect(anotherUser).collect(FIRST_PROFILE_ID, 1, data)
    //     ).to.be.revertedWith(ERRORS.FOLLOW_INVALID);
    //   });

    //   it('anotherUser should fail to collect after the collect end timestmap', async function () {
    //     await expect(
    //       lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
    //     ).to.not.be.reverted;

    //     const currentTimestamp = await getTimestamp();
    //     await setNextBlockTimestamp(Number(currentTimestamp) + 24 * 60 * 60);

    //     const data = abiCoder.encode(
    //       ['address', 'uint256'],
    //       [currency.address, DEFAULT_COLLECT_PRICE]
    //     );
    //     await expect(
    //       lensHub.connect(anotherUser).collect(FIRST_PROFILE_ID, 1, data)
    //     ).to.be.revertedWith(ERRORS.COLLECT_EXPIRED);
    //   });

    //   it('anotherUser should fail to collect passing a different expected price in data', async function () {
    //     await expect(
    //       lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
    //     ).to.not.be.reverted;

    //     const data = abiCoder.encode(
    //       ['address', 'uint256'],
    //       [currency.address, DEFAULT_COLLECT_PRICE.div(2)]
    //     );
    //     await expect(
    //       lensHub.connect(anotherUser).collect(FIRST_PROFILE_ID, 1, data)
    //     ).to.be.revertedWith(ERRORS.MODULE_DATA_MISMATCH);
    //   });

    //   it('anotherUser should fail to collect passing a different expected currency in data', async function () {
    //     await expect(
    //       lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
    //     ).to.not.be.reverted;

    //     const data = abiCoder.encode(['address', 'uint256'], [user.address, DEFAULT_COLLECT_PRICE]);
    //     await expect(
    //       lensHub.connect(anotherUser).collect(FIRST_PROFILE_ID, 1, data)
    //     ).to.be.revertedWith(ERRORS.MODULE_DATA_MISMATCH);
    //   });

    //   it('anotherUser should fail to collect without first approving module with currency', async function () {
    //     await expect(currency.mint(anotherUser.address, MaxUint256)).to.not.be.reverted;

    //     await expect(
    //       lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
    //     ).to.not.be.reverted;

    //     const data = abiCoder.encode(
    //       ['address', 'uint256'],
    //       [currency.address, DEFAULT_COLLECT_PRICE]
    //     );
    //     await expect(
    //       lensHub.connect(anotherUser).collect(FIRST_PROFILE_ID, 1, data)
    //     ).to.be.revertedWith(ERRORS.ERC20_INSUFFICIENT_ALLOWANCE);
    //   });

    //   it('anotherUser should mirror the original post, fail to collect from their mirror without following the original profile', async function () {
    //     const secondProfileId = FIRST_PROFILE_ID + 1;
    //     await expect(
    //       lensHub.connect(anotherUser).createProfile({
    //         to: anotherUser.address,
    //         handle: 'anotherUser',
    //         imageURI: OTHER_MOCK_URI,
    //         followModule: AddressZero,
    //         followModuleInitData: [],
    //         followNFTURI: MOCK_FOLLOW_NFT_URI,
    //       })
    //     ).to.not.be.reverted;
    //     await expect(
    //       lensHub.connect(anotherUser).mirror({
    //         profileId: secondProfileId,
    //         profileIdPointed: FIRST_PROFILE_ID,
    //         pubIdPointed: 1,
    //         referenceModuleData: [],
    //         referenceModule: AddressZero,
    //         referenceModuleInitData: [],
    //       })
    //     ).to.not.be.reverted;

    //     const data = abiCoder.encode(
    //       ['address', 'uint256'],
    //       [currency.address, DEFAULT_COLLECT_PRICE]
    //     );
    //     await expect(
    //       lensHub.connect(anotherUser).collect(secondProfileId, 1, data)
    //     ).to.be.revertedWith(ERRORS.FOLLOW_INVALID);
    //   });

    //   it('anotherUser should mirror the original post, fail to collect from their mirror after the collect end timestamp', async function () {
    //     const secondProfileId = FIRST_PROFILE_ID + 1;
    //     await expect(
    //       lensHub.connect(anotherUser).createProfile({
    //         to: anotherUser.address,
    //         handle: 'anotherUser',
    //         imageURI: OTHER_MOCK_URI,
    //         followModule: AddressZero,
    //         followModuleInitData: [],
    //         followNFTURI: MOCK_FOLLOW_NFT_URI,
    //       })
    //     ).to.not.be.reverted;
    //     await expect(
    //       lensHub.connect(anotherUser).mirror({
    //         profileId: secondProfileId,
    //         profileIdPointed: FIRST_PROFILE_ID,
    //         pubIdPointed: 1,
    //         referenceModuleData: [],
    //         referenceModule: AddressZero,
    //         referenceModuleInitData: [],
    //       })
    //     ).to.not.be.reverted;

    //     await expect(
    //       lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
    //     ).to.not.be.reverted;

    //     const currentTimestamp = await getTimestamp();
    //     await setNextBlockTimestamp(Number(currentTimestamp) + 24 * 60 * 60);

    //     const data = abiCoder.encode(
    //       ['address', 'uint256'],
    //       [currency.address, DEFAULT_COLLECT_PRICE]
    //     );
    //     await expect(
    //       lensHub.connect(anotherUser).collect(secondProfileId, 1, data)
    //     ).to.be.revertedWith(ERRORS.COLLECT_EXPIRED);
    //   });

    //   it('anotherUser should mirror the original post, fail to collect from their mirror passing a different expected price in data', async function () {
    //     const secondProfileId = FIRST_PROFILE_ID + 1;
    //     await expect(
    //       lensHub.connect(anotherUser).createProfile({
    //         to: anotherUser.address,
    //         handle: 'anotherUser',
    //         imageURI: OTHER_MOCK_URI,
    //         followModule: AddressZero,
    //         followModuleInitData: [],
    //         followNFTURI: MOCK_FOLLOW_NFT_URI,
    //       })
    //     ).to.not.be.reverted;
    //     await expect(
    //       lensHub.connect(anotherUser).mirror({
    //         profileId: secondProfileId,
    //         profileIdPointed: FIRST_PROFILE_ID,
    //         pubIdPointed: 1,
    //         referenceModuleData: [],
    //         referenceModule: AddressZero,
    //         referenceModuleInitData: [],
    //       })
    //     ).to.not.be.reverted;

    //     await expect(
    //       lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
    //     ).to.not.be.reverted;

    //     const data = abiCoder.encode(
    //       ['address', 'uint256'],
    //       [currency.address, DEFAULT_COLLECT_PRICE.div(2)]
    //     );
    //     await expect(
    //       lensHub.connect(anotherUser).collect(secondProfileId, 1, data)
    //     ).to.be.revertedWith(ERRORS.MODULE_DATA_MISMATCH);
    //   });

    //   it('anotherUser should mirror the original post, fail to collect from their mirror passing a different expected currency in data', async function () {
    //     const secondProfileId = FIRST_PROFILE_ID + 1;
    //     await expect(
    //       lensHub.connect(anotherUser).createProfile({
    //         to: anotherUser.address,
    //         handle: 'anotherUser',
    //         imageURI: OTHER_MOCK_URI,
    //         followModule: AddressZero,
    //         followModuleInitData: [],
    //         followNFTURI: MOCK_FOLLOW_NFT_URI,
    //       })
    //     ).to.not.be.reverted;
    //     await expect(
    //       lensHub.connect(anotherUser).mirror({
    //         profileId: secondProfileId,
    //         profileIdPointed: FIRST_PROFILE_ID,
    //         pubIdPointed: 1,
    //         referenceModuleData: [],
    //         referenceModule: AddressZero,
    //         referenceModuleInitData: [],
    //       })
    //     ).to.not.be.reverted;

    //     await expect(
    //       lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
    //     ).to.not.be.reverted;

    //     const data = abiCoder.encode(['address', 'uint256'], [user.address, DEFAULT_COLLECT_PRICE]);
    //     await expect(
    //       lensHub.connect(anotherUser).collect(secondProfileId, 1, data)
    //     ).to.be.revertedWith(ERRORS.MODULE_DATA_MISMATCH);
    //   });
    // });
  });

  // context('Scenarios', function () {
  //   it('User should post with limited timed fee collect module as the collect module and data, correct events should be emitted', async function () {
  //     const collectModuleInitData = abiCoder.encode(
  //       [
  //         'uint256',
  //         'address',
  //         'address',
  //         'uint16',
  //         'bool',
  //         'uint40',
  //         'tuple(uint256, uint256, uint256)',
  //       ],
  //       [
  //         DEFAULT_COLLECT_LIMIT,
  //         currency.address,
  //         user.address,
  //         REFERRAL_FEE_BPS,
  //         true,
  //         1099511627775,
  //         [0, 0, DEFAULT_COLLECT_PRICE],
  //       ]
  //     );
  //     const tx = lensHub.connect(publisher).post({
  //       profileId: FIRST_PROFILE_ID,
  //       contentURI: MOCK_URI,
  //       collectModule: stepwiseCollectModule.address,
  //       collectModuleInitData: collectModuleInitData,
  //       referenceModule: AddressZero,
  //       referenceModuleInitData: [],
  //     });

  //     const receipt = await waitForTx(tx);

  //     const postTimestamp = await getTimestamp();
  //     const endTimestamp = BigNumber.from(postTimestamp).add(24 * 60 * 60);
  //     const expectedData = abiCoder.encode(
  //       ['uint256', 'uint256', 'address', 'address', 'uint16', 'bool', 'uint40'],
  //       [
  //         DEFAULT_COLLECT_LIMIT,
  //         DEFAULT_COLLECT_PRICE,
  //         currency.address,
  //         user.address,
  //         REFERRAL_FEE_BPS,
  //         true,
  //         endTimestamp,
  //       ]
  //     );

  //     expect(receipt.logs.length).to.eq(1);
  //     matchEvent(receipt, 'PostCreated', [
  //       FIRST_PROFILE_ID,
  //       1,
  //       MOCK_URI,
  //       stepwiseCollectModule.address,
  //       expectedData,
  //       AddressZero,
  //       [],
  //       await getTimestamp(),
  //     ]);
  //   });

  //   it('User should post with limited timed fee collect module as the collect module and data, fetched publication data should be accurate', async function () {
  //     const collectModuleInitData = abiCoder.encode(
  //       [
  //         'uint256',
  //         'address',
  //         'address',
  //         'uint16',
  //         'bool',
  //         'uint40',
  //         'tuple(uint256, uint256, uint256)',
  //       ],
  //       [
  //         DEFAULT_COLLECT_LIMIT,
  //         currency.address,
  //         user.address,
  //         REFERRAL_FEE_BPS,
  //         true,
  //         1099511627775,
  //         [0, 0, DEFAULT_COLLECT_PRICE],
  //       ]
  //     );
  //     await expect(
  //       lensHub.connect(publisher).post({
  //         profileId: FIRST_PROFILE_ID,
  //         contentURI: MOCK_URI,
  //         collectModule: stepwiseCollectModule.address,
  //         collectModuleInitData: collectModuleInitData,
  //         referenceModule: AddressZero,
  //         referenceModuleInitData: [],
  //       })
  //     ).to.not.be.reverted;
  //     const postTimestamp = await getTimestamp();

  //     const fetchedData = await stepwiseCollectModule.getPublicationData(FIRST_PROFILE_ID, 1);
  //     expect(fetchedData.collectLimit).to.eq(DEFAULT_COLLECT_LIMIT);
  //     // expect(fetchedData.amount).to.eq(DEFAULT_COLLECT_PRICE);
  //     expect(fetchedData.recipient).to.eq(user.address);
  //     expect(fetchedData.currency).to.eq(currency.address);
  //     expect(fetchedData.referralFee).to.eq(REFERRAL_FEE_BPS);
  //     expect(fetchedData.followerOnly).to.eq(true);
  //     expect(fetchedData.endTimestamp).to.eq(BigNumber.from(postTimestamp).add(24 * 60 * 60));
  //   });

  //   it('User should post with limited timed fee collect module as the collect module and data, allowing non-followers to collect, user two collects without following, fee distribution is valid', async function () {
  //     const collectModuleInitData = abiCoder.encode(
  //       [
  //         'uint256',
  //         'address',
  //         'address',
  //         'uint16',
  //         'bool',
  //         'uint40',
  //         'tuple(uint256, uint256, uint256)',
  //       ],
  //       [
  //         DEFAULT_COLLECT_LIMIT,
  //         currency.address,
  //         user.address,
  //         REFERRAL_FEE_BPS,
  //         false,
  //         1099511627775,
  //         [0, 0, DEFAULT_COLLECT_PRICE],
  //       ]
  //     );
  //     await expect(
  //       lensHub.connect(publisher).post({
  //         profileId: FIRST_PROFILE_ID,
  //         contentURI: MOCK_URI,
  //         collectModule: stepwiseCollectModule.address,
  //         collectModuleInitData: collectModuleInitData,
  //         referenceModule: AddressZero,
  //         referenceModuleInitData: [],
  //       })
  //     ).to.not.be.reverted;

  //     await expect(currency.mint(anotherUser.address, MaxUint256)).to.not.be.reverted;
  //     await expect(
  //       currency.connect(anotherUser).approve(stepwiseCollectModule.address, MaxUint256)
  //     ).to.not.be.reverted;
  //     const data = abiCoder.encode(
  //       ['address', 'uint256'],
  //       [currency.address, DEFAULT_COLLECT_PRICE]
  //     );
  //     await expect(
  //       lensHub.connect(anotherUser).collect(FIRST_PROFILE_ID, 1, data)
  //     ).to.not.be.reverted;

  //     const expectedTreasuryAmount = BigNumber.from(DEFAULT_COLLECT_PRICE)
  //       .mul(TREASURY_FEE_BPS)
  //       .div(BPS_MAX);
  //     const expectedRecipientAmount =
  //       BigNumber.from(DEFAULT_COLLECT_PRICE).sub(expectedTreasuryAmount);

  //     expect(await currency.balanceOf(anotherUser.address)).to.eq(
  //       BigNumber.from(MaxUint256).sub(DEFAULT_COLLECT_PRICE)
  //     );
  //     expect(await currency.balanceOf(user.address)).to.eq(expectedRecipientAmount);
  //     expect(await currency.balanceOf(treasury.address)).to.eq(expectedTreasuryAmount);
  //   });

  //   it('User should post with limited timed fee collect module as the collect module and data, user two follows, then collects and pays fee, fee distribution is valid', async function () {
  //     const collectModuleInitData = abiCoder.encode(
  //       [
  //         'uint256',
  //         'address',
  //         'address',
  //         'uint16',
  //         'bool',
  //         'uint40',
  //         'tuple(uint256, uint256, uint256)',
  //       ],
  //       [
  //         DEFAULT_COLLECT_LIMIT,
  //         currency.address,
  //         user.address,
  //         REFERRAL_FEE_BPS,
  //         true,
  //         1099511627775,
  //         [0, 0, DEFAULT_COLLECT_PRICE],
  //       ]
  //     );
  //     await expect(
  //       lensHub.connect(publisher).post({
  //         profileId: FIRST_PROFILE_ID,
  //         contentURI: MOCK_URI,
  //         collectModule: stepwiseCollectModule.address,
  //         collectModuleInitData: collectModuleInitData,
  //         referenceModule: AddressZero,
  //         referenceModuleInitData: [],
  //       })
  //     ).to.not.be.reverted;

  //     await expect(currency.mint(anotherUser.address, MaxUint256)).to.not.be.reverted;
  //     await expect(
  //       currency.connect(anotherUser).approve(stepwiseCollectModule.address, MaxUint256)
  //     ).to.not.be.reverted;
  //     await expect(
  //       lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
  //     ).to.not.be.reverted;
  //     const data = abiCoder.encode(
  //       ['address', 'uint256'],
  //       [currency.address, DEFAULT_COLLECT_PRICE]
  //     );
  //     await expect(
  //       lensHub.connect(anotherUser).collect(FIRST_PROFILE_ID, 1, data)
  //     ).to.not.be.reverted;

  //     const expectedTreasuryAmount = BigNumber.from(DEFAULT_COLLECT_PRICE)
  //       .mul(TREASURY_FEE_BPS)
  //       .div(BPS_MAX);
  //     const expectedRecipientAmount =
  //       BigNumber.from(DEFAULT_COLLECT_PRICE).sub(expectedTreasuryAmount);

  //     expect(await currency.balanceOf(anotherUser.address)).to.eq(
  //       BigNumber.from(MaxUint256).sub(DEFAULT_COLLECT_PRICE)
  //     );
  //     expect(await currency.balanceOf(user.address)).to.eq(expectedRecipientAmount);
  //     expect(await currency.balanceOf(treasury.address)).to.eq(expectedTreasuryAmount);
  //   });

  //   it('User should post with limited timed fee collect module as the collect module and data, user two follows, then collects twice, fee distribution is valid', async function () {
  //     const collectModuleInitData = abiCoder.encode(
  //       [
  //         'uint256',
  //         'address',
  //         'address',
  //         'uint16',
  //         'bool',
  //         'uint40',
  //         'tuple(uint256, uint256, uint256)',
  //       ],
  //       [
  //         DEFAULT_COLLECT_LIMIT,
  //         currency.address,
  //         user.address,
  //         REFERRAL_FEE_BPS,
  //         true,
  //         1099511627775,
  //         [0, 0, DEFAULT_COLLECT_PRICE],
  //       ]
  //     );
  //     await expect(
  //       lensHub.post({
  //         profileId: FIRST_PROFILE_ID,
  //         contentURI: MOCK_URI,
  //         collectModule: stepwiseCollectModule.address,
  //         collectModuleInitData: collectModuleInitData,
  //         referenceModule: AddressZero,
  //         referenceModuleInitData: [],
  //       })
  //     ).to.not.be.reverted;

  //     await expect(currency.mint(anotherUser.address, MaxUint256)).to.not.be.reverted;
  //     await expect(
  //       currency.connect(anotherUser).approve(stepwiseCollectModule.address, MaxUint256)
  //     ).to.not.be.reverted;
  //     await expect(
  //       lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
  //     ).to.not.be.reverted;
  //     const data = abiCoder.encode(
  //       ['address', 'uint256'],
  //       [currency.address, DEFAULT_COLLECT_PRICE]
  //     );
  //     await expect(
  //       lensHub.connect(anotherUser).collect(FIRST_PROFILE_ID, 1, data)
  //     ).to.not.be.reverted;
  //     await expect(
  //       lensHub.connect(anotherUser).collect(FIRST_PROFILE_ID, 1, data)
  //     ).to.not.be.reverted;

  //     const expectedTreasuryAmount = BigNumber.from(DEFAULT_COLLECT_PRICE)
  //       .mul(TREASURY_FEE_BPS)
  //       .div(BPS_MAX);
  //     const expectedRecipientAmount =
  //       BigNumber.from(DEFAULT_COLLECT_PRICE).sub(expectedTreasuryAmount);

  //     expect(await currency.balanceOf(anotherUser.address)).to.eq(
  //       BigNumber.from(MaxUint256).sub(BigNumber.from(DEFAULT_COLLECT_PRICE).mul(2))
  //     );
  //     expect(await currency.balanceOf(user.address)).to.eq(expectedRecipientAmount.mul(2));
  //     expect(await currency.balanceOf(treasury.address)).to.eq(expectedTreasuryAmount.mul(2));
  //   });

  //   it('User should post with limited timed fee collect module as the collect module and data, user two mirrors, follows, then collects from their mirror and pays fee, fee distribution is valid', async function () {
  //     const secondProfileId = FIRST_PROFILE_ID + 1;
  //     const collectModuleInitData = abiCoder.encode(
  //       [
  //         'uint256',
  //         'address',
  //         'address',
  //         'uint16',
  //         'bool',
  //         'uint40',
  //         'tuple(uint256, uint256, uint256)',
  //       ],
  //       [
  //         DEFAULT_COLLECT_LIMIT,
  //         currency.address,
  //         user.address,
  //         REFERRAL_FEE_BPS,
  //         true,
  //         1099511627775,
  //         [0, 0, DEFAULT_COLLECT_PRICE],
  //       ]
  //     );
  //     await expect(
  //       lensHub.connect(publisher).post({
  //         profileId: FIRST_PROFILE_ID,
  //         contentURI: MOCK_URI,
  //         collectModule: stepwiseCollectModule.address,
  //         collectModuleInitData: collectModuleInitData,
  //         referenceModule: AddressZero,
  //         referenceModuleInitData: [],
  //       })
  //     ).to.not.be.reverted;

  //     await expect(
  //       lensHub.connect(anotherUser).createProfile({
  //         to: anotherUser.address,
  //         handle: 'anotherUser',
  //         imageURI: OTHER_MOCK_URI,
  //         followModule: AddressZero,
  //         followModuleInitData: [],
  //         followNFTURI: MOCK_FOLLOW_NFT_URI,
  //       })
  //     ).to.not.be.reverted;
  //     await expect(
  //       lensHub.connect(anotherUser).mirror({
  //         profileId: secondProfileId,
  //         profileIdPointed: FIRST_PROFILE_ID,
  //         pubIdPointed: 1,
  //         referenceModuleData: [],
  //         referenceModule: AddressZero,
  //         referenceModuleInitData: [],
  //       })
  //     ).to.not.be.reverted;

  //     await expect(currency.mint(anotherUser.address, MaxUint256)).to.not.be.reverted;
  //     await expect(
  //       currency.connect(anotherUser).approve(stepwiseCollectModule.address, MaxUint256)
  //     ).to.not.be.reverted;
  //     await expect(
  //       lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
  //     ).to.not.be.reverted;
  //     const data = abiCoder.encode(
  //       ['address', 'uint256'],
  //       [currency.address, DEFAULT_COLLECT_PRICE]
  //     );
  //     await expect(
  //       lensHub.connect(anotherUser).collect(secondProfileId, 1, data)
  //     ).to.not.be.reverted;

  //     const expectedTreasuryAmount = BigNumber.from(DEFAULT_COLLECT_PRICE)
  //       .mul(TREASURY_FEE_BPS)
  //       .div(BPS_MAX);
  //     const expectedReferralAmount = BigNumber.from(DEFAULT_COLLECT_PRICE)
  //       .sub(expectedTreasuryAmount)
  //       .mul(REFERRAL_FEE_BPS)
  //       .div(BPS_MAX);
  //     const expectedReferrerAmount = BigNumber.from(MaxUint256)
  //       .sub(DEFAULT_COLLECT_PRICE)
  //       .add(expectedReferralAmount);
  //     const expectedRecipientAmount = BigNumber.from(DEFAULT_COLLECT_PRICE)
  //       .sub(expectedTreasuryAmount)
  //       .sub(expectedReferralAmount);

  //     expect(await currency.balanceOf(anotherUser.address)).to.eq(expectedReferrerAmount);
  //     expect(await currency.balanceOf(user.address)).to.eq(expectedRecipientAmount);
  //     expect(await currency.balanceOf(treasury.address)).to.eq(expectedTreasuryAmount);
  //   });

  //   it('User should post with limited timed fee collect module as the collect module and data, with no referral fee, user two mirrors, follows, then collects from their mirror and pays fee, fee distribution is valid', async function () {
  //     const secondProfileId = FIRST_PROFILE_ID + 1;
  //     const collectModuleInitData = abiCoder.encode(
  //       [
  //         'uint256',
  //         'address',
  //         'address',
  //         'uint16',
  //         'bool',
  //         'uint40',
  //         'tuple(uint256, uint256, uint256)',
  //       ],
  //       [
  //         DEFAULT_COLLECT_LIMIT,
  //         currency.address,
  //         user.address,
  //         0,
  //         true,
  //         1099511627775,
  //         [0, 0, DEFAULT_COLLECT_PRICE],
  //       ]
  //     );
  //     await expect(
  //       lensHub.connect(publisher).post({
  //         profileId: FIRST_PROFILE_ID,
  //         contentURI: MOCK_URI,
  //         collectModule: stepwiseCollectModule.address,
  //         collectModuleInitData: collectModuleInitData,
  //         referenceModule: AddressZero,
  //         referenceModuleInitData: [],
  //       })
  //     ).to.not.be.reverted;

  //     await expect(
  //       lensHub.connect(anotherUser).createProfile({
  //         to: anotherUser.address,
  //         handle: 'anotherUser',
  //         imageURI: OTHER_MOCK_URI,
  //         followModule: AddressZero,
  //         followModuleInitData: [],
  //         followNFTURI: MOCK_FOLLOW_NFT_URI,
  //       })
  //     ).to.not.be.reverted;
  //     await expect(
  //       lensHub.connect(anotherUser).mirror({
  //         profileId: secondProfileId,
  //         profileIdPointed: FIRST_PROFILE_ID,
  //         pubIdPointed: 1,
  //         referenceModuleData: [],
  //         referenceModule: AddressZero,
  //         referenceModuleInitData: [],
  //       })
  //     ).to.not.be.reverted;

  //     await expect(currency.mint(anotherUser.address, MaxUint256)).to.not.be.reverted;
  //     await expect(
  //       currency.connect(anotherUser).approve(stepwiseCollectModule.address, MaxUint256)
  //     ).to.not.be.reverted;
  //     await expect(
  //       lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
  //     ).to.not.be.reverted;
  //     const data = abiCoder.encode(
  //       ['address', 'uint256'],
  //       [currency.address, DEFAULT_COLLECT_PRICE]
  //     );
  //     await expect(
  //       lensHub.connect(anotherUser).collect(secondProfileId, 1, data)
  //     ).to.not.be.reverted;

  //     const expectedTreasuryAmount = BigNumber.from(DEFAULT_COLLECT_PRICE)
  //       .mul(TREASURY_FEE_BPS)
  //       .div(BPS_MAX);
  //     const expectedRecipientAmount =
  //       BigNumber.from(DEFAULT_COLLECT_PRICE).sub(expectedTreasuryAmount);

  //     expect(await currency.balanceOf(anotherUser.address)).to.eq(
  //       BigNumber.from(MaxUint256).sub(DEFAULT_COLLECT_PRICE)
  //     );
  //     expect(await currency.balanceOf(user.address)).to.eq(expectedRecipientAmount);
  //     expect(await currency.balanceOf(treasury.address)).to.eq(expectedTreasuryAmount);
  //   });

  //   it('User should post with limited timed fee collect module as the collect module and data, user two mirrors, follows, then collects once from the original, twice from the mirror, and fails to collect a third time from either the mirror or the original', async function () {
  //     const secondProfileId = FIRST_PROFILE_ID + 1;
  //     const collectModuleInitData = abiCoder.encode(
  //       [
  //         'uint256',
  //         'address',
  //         'address',
  //         'uint16',
  //         'bool',
  //         'uint40',
  //         'tuple(uint256, uint256, uint256)',
  //       ],
  //       [
  //         DEFAULT_COLLECT_LIMIT,
  //         currency.address,
  //         user.address,
  //         REFERRAL_FEE_BPS,
  //         true,
  //         1099511627775,
  //         [0, 0, DEFAULT_COLLECT_PRICE],
  //       ]
  //     );
  //     await expect(
  //       lensHub.connect(publisher).post({
  //         profileId: FIRST_PROFILE_ID,
  //         contentURI: MOCK_URI,
  //         collectModule: stepwiseCollectModule.address,
  //         collectModuleInitData: collectModuleInitData,
  //         referenceModule: AddressZero,
  //         referenceModuleInitData: [],
  //       })
  //     ).to.not.be.reverted;

  //     await expect(
  //       lensHub.connect(anotherUser).createProfile({
  //         to: anotherUser.address,
  //         handle: 'anotherUser',
  //         imageURI: OTHER_MOCK_URI,
  //         followModule: AddressZero,
  //         followModuleInitData: [],
  //         followNFTURI: MOCK_FOLLOW_NFT_URI,
  //       })
  //     ).to.not.be.reverted;
  //     await expect(
  //       lensHub.connect(anotherUser).mirror({
  //         profileId: secondProfileId,
  //         profileIdPointed: FIRST_PROFILE_ID,
  //         pubIdPointed: 1,
  //         referenceModuleData: [],
  //         referenceModule: AddressZero,
  //         referenceModuleInitData: [],
  //       })
  //     ).to.not.be.reverted;

  //     await expect(currency.mint(anotherUser.address, MaxUint256)).to.not.be.reverted;
  //     await expect(
  //       currency.connect(anotherUser).approve(stepwiseCollectModule.address, MaxUint256)
  //     ).to.not.be.reverted;
  //     await expect(
  //       lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]])
  //     ).to.not.be.reverted;
  //     const data = abiCoder.encode(
  //       ['address', 'uint256'],
  //       [currency.address, DEFAULT_COLLECT_PRICE]
  //     );
  //     await expect(
  //       lensHub.connect(anotherUser).collect(FIRST_PROFILE_ID, 1, data)
  //     ).to.not.be.reverted;
  //     await expect(
  //       lensHub.connect(anotherUser).collect(secondProfileId, 1, data)
  //     ).to.not.be.reverted;
  //     await expect(
  //       lensHub.connect(anotherUser).collect(secondProfileId, 1, data)
  //     ).to.not.be.reverted;

  //     await expect(
  //       lensHub.connect(anotherUser).collect(FIRST_PROFILE_ID, 1, data)
  //     ).to.be.revertedWith(ERRORS.MINT_LIMIT_EXCEEDED);
  //     await expect(
  //       lensHub.connect(anotherUser).collect(secondProfileId, 1, data)
  //     ).to.be.revertedWith(ERRORS.MINT_LIMIT_EXCEEDED);
  //   });
  // });
});
