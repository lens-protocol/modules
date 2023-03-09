import '@nomiclabs/hardhat-ethers';
import { expect } from 'chai';
import { Signer } from 'ethers';
const { getContractAddress } = require('@ethersproject/address');
import { ethers } from 'hardhat';
import {
  FIRST_PROFILE_ID,
  FIRST_PUB_ID,
  governance,
  lensHub,
  makeSuiteCleanRoom,
  MOCK_FOLLOW_NFT_URI,
  MOCK_PROFILE_HANDLE,
  MOCK_PROFILE_URI,
  MOCK_URI,
  deployer,
  user,
  anotherUser,
  thirdUser,
} from './../../__setup.spec';
import { ERRORS } from './../../helpers/errors';
import { matchEvent, waitForTx } from './../../helpers/utils';
import { ZERO_ADDRESS, EMPTY_BYTES } from './../../helpers/constants';
import {
  MadRewardCollectModule,
  MadRewardCollectModule__factory,
  MockMadSBT,
  MockMadSBT__factory,
  FollowNFT__factory,
} from '../../../typechain';

const FIRST_COLLECTION_ID = 1;
const MOCK_AVAILABLE_SUPPLY = 1;

makeSuiteCleanRoom('MadRewardCollectModule', function () {
  let collectModule: MadRewardCollectModule;
  let madSBT: MockMadSBT;
  let deployerAddress: string, userAddress: string, anotherUserAddress: string;

  beforeEach(async () => {
    deployerAddress = await deployer.getAddress();
    userAddress = await user.getAddress();
    anotherUserAddress = await anotherUser.getAddress();

    madSBT = await new MockMadSBT__factory(deployer).deploy();
    collectModule = await new MadRewardCollectModule__factory(deployer).deploy(lensHub.address, madSBT.address);

    await madSBT.setCollectModule(collectModule.address);

    await lensHub.connect(governance).whitelistCollectModule(collectModule.address, true);

    await lensHub.createProfile({
      to: userAddress,
      handle: MOCK_PROFILE_HANDLE,
      imageURI: MOCK_PROFILE_URI,
      followModule: ZERO_ADDRESS,
      followModuleInitData: [],
      followNFTURI: MOCK_FOLLOW_NFT_URI,
    });

    await lensHub.createProfile({
      to: anotherUserAddress,
      handle: 'test.lens',
      imageURI: MOCK_PROFILE_URI,
      followModule: ZERO_ADDRESS,
      followModuleInitData: [],
      followNFTURI: MOCK_FOLLOW_NFT_URI,
    });
  });

  describe('#constructor', () => {
    it('reverts when the hub arg is the null address', async () => {
      expect(
        new MadRewardCollectModule__factory(deployer).deploy(ZERO_ADDRESS, madSBT.address)
      ).to.be.revertedWith('InitParamsInvalid');
    });

    it('reverts when the madSBT arg is the null address', async () => {
      expect(
        new MadRewardCollectModule__factory(deployer).deploy(lensHub.address, ZERO_ADDRESS)
      ).to.be.revertedWith('NoZeroAddress');
    });

    it('sets storage', async () => {
      const _madSBT = await collectModule.madSBT();

      expect(_madSBT).to.equal(madSBT.address);
    });
  });

  describe('#initializePublicationCollectModule', () => {
    it('reverts when the caller is not LensHub', async () => {
      await expect(
        collectModule.initializePublicationCollectModule(FIRST_PROFILE_ID, 1, EMPTY_BYTES)
      ).to.be.revertedWith(ERRORS.NOT_HUB);
    });

    it('reverts with invalid uri', async () => {
      const collectModuleInitData = ethers.utils.defaultAbiCoder.encode(
        ['uint256', 'uint256', 'string'],
        [0, MOCK_AVAILABLE_SUPPLY, ""]
      );

      await expect(
        lensHub.connect(user).post({
          profileId: FIRST_PROFILE_ID,
          contentURI: MOCK_URI,
          collectModule: collectModule.address,
          collectModuleInitData,
          referenceModule: ZERO_ADDRESS,
          referenceModuleInitData: [],
        })
      ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
    });

    it('reverts with invalid supply', async () => {
      const collectModuleInitData = ethers.utils.defaultAbiCoder.encode(
        ['uint256', 'uint256', 'string'],
        [0, 0, MOCK_URI]
      );

      await expect(
        lensHub.connect(user).post({
          profileId: FIRST_PROFILE_ID,
          contentURI: MOCK_URI,
          collectModule: collectModule.address,
          collectModuleInitData,
          referenceModule: ZERO_ADDRESS,
          referenceModuleInitData: [],
        })
      ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
    });

    it('creates a new collection, sets the active collection for the profile, and emits an event', async () => {
      const collectModuleInitData = ethers.utils.defaultAbiCoder.encode(
        ['uint256', 'uint256', 'string'],
        [0, MOCK_AVAILABLE_SUPPLY, MOCK_URI]
      );

      const tx = lensHub.connect(user).post({
        profileId: FIRST_PROFILE_ID,
        contentURI: MOCK_URI,
        collectModule: collectModule.address,
        collectModuleInitData,
        referenceModule: ZERO_ADDRESS,
        referenceModuleInitData: [],
      });

      const txReceipt = await waitForTx(tx);

      const collectionData = await madSBT.collectionData(FIRST_COLLECTION_ID);
      expect(collectionData.creatorId.toNumber()).to.equal(FIRST_PROFILE_ID);

      const activeCollectionId = await collectModule.activeCollectionPerPubId(FIRST_PROFILE_ID, FIRST_PUB_ID);
      expect(activeCollectionId.toNumber()).to.equal(FIRST_COLLECTION_ID);

      matchEvent(
        txReceipt,
        'InitCollectModule',
        [FIRST_PROFILE_ID, FIRST_PUB_ID, FIRST_COLLECTION_ID],
        collectModule
      );
    });

    context('context: when using an existing collection id', () => {
      beforeEach(async() => {
        const collectModuleInitData = ethers.utils.defaultAbiCoder.encode(
          ['uint256', 'uint256', 'string'],
          [0, MOCK_AVAILABLE_SUPPLY, MOCK_URI]
        );

        const tx = lensHub.connect(user).post({
          profileId: FIRST_PROFILE_ID,
          contentURI: MOCK_URI,
          collectModule: collectModule.address,
          collectModuleInitData,
          referenceModule: ZERO_ADDRESS,
          referenceModuleInitData: [],
        });

        await waitForTx(tx);
      });

      it('reverts when the caller is not the creator', async () => {
        const collectModuleInitData = ethers.utils.defaultAbiCoder.encode(
          ['uint256', 'uint256', 'string'],
          [FIRST_COLLECTION_ID, MOCK_AVAILABLE_SUPPLY, MOCK_URI]
        );

        await expect(
          lensHub.connect(anotherUser).post({
            profileId: FIRST_PROFILE_ID + 1,
            contentURI: MOCK_URI,
            collectModule: collectModule.address,
            collectModuleInitData,
            referenceModule: ZERO_ADDRESS,
            referenceModuleInitData: [],
          })
        ).to.be.revertedWith('NotCollectionCreator()');
      });

      it('does not create a new collection', async() => {
        const collectModuleInitData = ethers.utils.defaultAbiCoder.encode(
          ['uint256', 'uint256', 'string'],
          [FIRST_COLLECTION_ID, MOCK_AVAILABLE_SUPPLY, MOCK_URI]
        );

        const tx = lensHub.connect(user).post({
          profileId: FIRST_PROFILE_ID,
          contentURI: MOCK_URI,
          collectModule: collectModule.address,
          collectModuleInitData,
          referenceModule: ZERO_ADDRESS,
          referenceModuleInitData: [],
        });

        await waitForTx(tx);

        const emptyCollection = await madSBT.collectionData(FIRST_COLLECTION_ID + 1);
        expect(emptyCollection.creatorId.toNumber()).to.equal(0);
      });
    });
  });

  describe('#processCollect', () => {
    let tx;

    beforeEach(async() => {
      const collectModuleInitData = ethers.utils.defaultAbiCoder.encode(
        ['uint256', 'uint256', 'string'],
        [0, MOCK_AVAILABLE_SUPPLY, MOCK_URI]
      );

      const tx = lensHub.connect(user).post({
        profileId: FIRST_PROFILE_ID,
        contentURI: MOCK_URI,
        collectModule: collectModule.address,
        collectModuleInitData,
        referenceModule: ZERO_ADDRESS,
        referenceModuleInitData: [],
      });

      await waitForTx(tx);
    });

    it('reverts when the caller is not LensHub', async () => {
      await expect(
        collectModule.processCollect(1, anotherUserAddress, FIRST_PROFILE_ID, FIRST_PUB_ID, EMPTY_BYTES)
      ).to.be.revertedWith(ERRORS.NOT_HUB);
    });

    it('reverts if the collector is not following the creator', async () => {
      await expect(
        lensHub.connect(anotherUser).collect(
          FIRST_PROFILE_ID,
          FIRST_PUB_ID,
          EMPTY_BYTES
        )
      ).to.be.revertedWith('NotFollowing');
    });

    context('context: when the collector does not have a balance of the mad sbt collection', () => {
      let txReceipt;

      beforeEach(async() => {
        await lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]]);
        const tx = lensHub.connect(anotherUser).collect(
          FIRST_PROFILE_ID,
          FIRST_PUB_ID,
          EMPTY_BYTES
        );

        txReceipt = await waitForTx(tx);
      });

      it('mints the collector an NFT from the collection and inits the reward units', async () => {
        const balance = await madSBT.balanceOf(anotherUserAddress);
        expect(balance.toNumber()).to.equal(1);

        const units = await madSBT.rewardUnitsOf(anotherUserAddress, FIRST_COLLECTION_ID);
        const expectedUnits = await madSBT.mintRewardUnit();
        expect(units.toNumber()).to.equal(expectedUnits.toNumber());
      });

      it('processes the collect', async () => {
        matchEvent(txReceipt, 'Collected');
      });

      it('reverts when the collection supply has been reached', async () => {
        await lensHub.connect(thirdUser).follow([FIRST_PROFILE_ID], [[]]);
        expect(
          lensHub.connect(thirdUser).collect(
            FIRST_PROFILE_ID,
            FIRST_PUB_ID,
            EMPTY_BYTES
          )
        ).to.be.revertedWith(ERRORS.COLLECT_NOT_ALLOWED);
      });
    });

    context('context: when the collector does have a balance of the mad sbt collection', () => {
      let txReceipt;

      beforeEach(async() => {
        await lensHub.connect(anotherUser).follow([FIRST_PROFILE_ID], [[]]);
        await lensHub.connect(anotherUser).collect(
          FIRST_PROFILE_ID,
          FIRST_PUB_ID,
          EMPTY_BYTES
        );

        const collectModuleInitData = ethers.utils.defaultAbiCoder.encode(
          ['uint256', 'uint256', 'string'],
          [FIRST_COLLECTION_ID, MOCK_AVAILABLE_SUPPLY, MOCK_URI]
        );

        // another post with the previously created collection id
        await lensHub.connect(user).post({
          profileId: FIRST_PROFILE_ID,
          contentURI: MOCK_URI,
          collectModule: collectModule.address,
          collectModuleInitData,
          referenceModule: ZERO_ADDRESS,
          referenceModuleInitData: [],
        });

        const tx = lensHub.connect(anotherUser).collect(
          FIRST_PROFILE_ID,
          FIRST_PUB_ID + 1, // the second post
          EMPTY_BYTES
        );

        txReceipt = await waitForTx(tx);
      });

      it('does not mint them another nft and simply updates the reward units', async () => {
        const balance = await madSBT.balanceOf(anotherUserAddress);
        expect(balance.toNumber()).to.equal(1);

        const units = await madSBT.rewardUnitsOf(anotherUserAddress, FIRST_COLLECTION_ID);
        const mintUnits = await madSBT.mintRewardUnit();
        const collectUnits = await madSBT.collectRewardUnit();
        expect(units.toNumber()).to.equal(mintUnits.add(collectUnits).toNumber());
      });

      it('processes the collect', async () => {
        matchEvent(txReceipt, 'Collected');
      });
    });
  });
});
