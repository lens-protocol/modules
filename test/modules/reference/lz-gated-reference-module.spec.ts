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
  OTHER_MOCK_URI,
  deployer,
  user,
  anotherUser,
  freeCollectModule,
} from './../../__setup.spec';
import { ERRORS } from './../../helpers/errors';
import { matchEvent, waitForTx, getTimestamp } from './../../helpers/utils';
import signCommentWithSigData from './../../helpers/signatures/core/sign-comment-with-sig-data';
import signMirrorWithSigData from './../../helpers/signatures/core/sign-mirror-with-sig-data';
import {
  ZERO_ADDRESS,
  MAX_UINT256,
  EMPTY_BYTES,
  LZ_GATED_REMOTE_CHAIN_ID,
  LZ_GATED_BALANCE_THRESHOLD,
} from './../../helpers/constants';
import {
  LZGatedReferenceModule,
  LZGatedReferenceModule__factory,
  LZGatedProxy,
  LZGatedProxy__factory,
  LZEndpointMock,
  LZEndpointMock__factory,
  ERC721Mock,
  ERC721Mock__factory,
  ERC20Mock,
  ERC20Mock__factory,
  FollowNFT__factory,
} from '../../../typechain';

makeSuiteCleanRoom('LZGatedReferenceModule', function () {
  let lzGatedProxy: LZGatedProxy;
  let lzEndpoint: LZEndpointMock;
  let referenceModule: LZGatedReferenceModule;
  let erc721: ERC721Mock;
  let erc20: ERC20Mock;
  let deployerAddress: string, userAddress: string, anotherUserAddress: string;

  beforeEach(async () => {
    deployerAddress = await deployer.getAddress();
    userAddress = await user.getAddress();
    anotherUserAddress = await anotherUser.getAddress();

    lzEndpoint = await new LZEndpointMock__factory(deployer).deploy(LZ_GATED_REMOTE_CHAIN_ID);
    const transactionCount = await deployer.getTransactionCount();
    const referenceModuleAddress = getContractAddress({ from: deployerAddress, nonce: transactionCount + 1 });

    lzGatedProxy = await new LZGatedProxy__factory(deployer).deploy(
      lzEndpoint.address,
      LZ_GATED_REMOTE_CHAIN_ID,
      ZERO_ADDRESS, // _remoteFollowModule
      referenceModuleAddress,
      ZERO_ADDRESS // _remoteCollectModule
    );
    referenceModule = await new LZGatedReferenceModule__factory(deployer).deploy(
      lensHub.address,
      lzEndpoint.address,
      [LZ_GATED_REMOTE_CHAIN_ID],
      [lzGatedProxy.address]
    );
    erc721 = await new ERC721Mock__factory(deployer).deploy();
    erc20 = await new ERC20Mock__factory(deployer).deploy();

    // use same lz endpoint mock
    await lzEndpoint.setDestLzEndpoint(referenceModule.address, lzEndpoint.address);
    await lzEndpoint.setDestLzEndpoint(lzGatedProxy.address, lzEndpoint.address);

    await lensHub.connect(governance).whitelistCollectModule(freeCollectModule.address, true)
    await lensHub.connect(governance).whitelistReferenceModule(referenceModule.address, true);

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
        new LZGatedReferenceModule__factory(deployer).deploy(ZERO_ADDRESS, lzEndpoint.address, [], [])
      ).to.be.revertedWith('InitParamsInvalid');
    });

    it('sets storage', async () => {
      const owner = await referenceModule.owner();
      const endpoint = await referenceModule.lzEndpoint();

      expect(owner).to.equal(deployerAddress);
      expect(endpoint).to.equal(lzEndpoint.address);
    });
  });

  describe('#initializeReferenceModule', () => {
    it('reverts when the caller is not LensHub', async () => {
      await expect(
        referenceModule.initializeReferenceModule(FIRST_PROFILE_ID, 1, EMPTY_BYTES)
      ).to.be.revertedWith(ERRORS.NOT_HUB);
    });

    it('reverts when an invalid chain id is provided in the encoded data', async () => {
      const referenceModuleInitData = ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint256', 'uint16'],
        [erc721.address, LZ_GATED_BALANCE_THRESHOLD, 12345]
      );

      await expect(
        lensHub.connect(user).post({
          profileId: FIRST_PROFILE_ID,
          contentURI: MOCK_URI,
          collectModule: freeCollectModule.address,
          collectModuleInitData: ethers.utils.defaultAbiCoder.encode(['bool'], [true]),
          referenceModule: referenceModule.address,
          referenceModuleInitData: referenceModuleInitData,
        })
      ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
    });

    it('reverts when token contract as zero address is provided in the encoded data', async () => {
      const referenceModuleInitData = ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint256', 'uint16'],
        [ZERO_ADDRESS, LZ_GATED_BALANCE_THRESHOLD, LZ_GATED_REMOTE_CHAIN_ID]
      );

      await expect(
        lensHub.connect(user).post({
          profileId: FIRST_PROFILE_ID,
          contentURI: MOCK_URI,
          collectModule: freeCollectModule.address,
          collectModuleInitData: ethers.utils.defaultAbiCoder.encode(['bool'], [true]),
          referenceModule: referenceModule.address,
          referenceModuleInitData: referenceModuleInitData,
        })
      ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
    });

    context('context: with valid params', () => {
      let tx;

      beforeEach(async() => {
        const referenceModuleInitData = ethers.utils.defaultAbiCoder.encode(
          ['address', 'uint256', 'uint16'],
          [erc721.address, LZ_GATED_BALANCE_THRESHOLD, LZ_GATED_REMOTE_CHAIN_ID]
        );
        tx = lensHub.connect(user).post({
          profileId: FIRST_PROFILE_ID,
          contentURI: MOCK_URI,
          collectModule: freeCollectModule.address,
          collectModuleInitData: ethers.utils.defaultAbiCoder.encode(['bool'], [true]),
          referenceModule: referenceModule.address,
          referenceModuleInitData: referenceModuleInitData,
        });
      });

      it('sets storage', async () => {
        await waitForTx(tx);
        const res = await referenceModule.gatedReferenceDataPerPub(FIRST_PROFILE_ID, 1);

        expect(res.balanceThreshold.toNumber()).to.equal(LZ_GATED_BALANCE_THRESHOLD);
        expect(res.tokenContract).to.equal(erc721.address);
        expect(res.remoteChainId).to.equal(LZ_GATED_REMOTE_CHAIN_ID);
      });

      it('emits an event', async () => {
        const txReceipt = await waitForTx(tx);
        matchEvent(
          txReceipt,
          'InitReferenceModule',
          [FIRST_PROFILE_ID, FIRST_PUB_ID, erc721.address, LZ_GATED_BALANCE_THRESHOLD, LZ_GATED_REMOTE_CHAIN_ID],
          referenceModule
        );
      });
    });
  });

  describe('#processComment (triggered from LZGatedProxy#relayCommentWithSig)', () => {
    let commentWithSigData;
    let referenceModuleInitData;
    let collectModuleInitData;

    beforeEach(async() => {
      collectModuleInitData = ethers.utils.defaultAbiCoder.encode(['bool'], [true]);
      referenceModuleInitData = ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint256', 'uint16'],
        [erc721.address, LZ_GATED_BALANCE_THRESHOLD, LZ_GATED_REMOTE_CHAIN_ID]
      );

      await lensHub.connect(user).post({
        profileId: FIRST_PROFILE_ID,
        contentURI: MOCK_URI,
        collectModule: freeCollectModule.address,
        collectModuleInitData,
        referenceModule: referenceModule.address,
        referenceModuleInitData,
      });

      // anotherUser signs that they would like to comment on user's first post
      commentWithSigData = await signCommentWithSigData({
        signer: anotherUser,
        profileId: FIRST_PROFILE_ID + 1,
        contentURI: OTHER_MOCK_URI,
        profileIdPointed: FIRST_PROFILE_ID,
        pubIdPointed: FIRST_PUB_ID,
        referenceModuleData: [],
        collectModule: freeCollectModule.address,
        collectModuleInitData,
        referenceModule: ZERO_ADDRESS,
        referenceModuleInitData: [],
      });
    });

    it('reverts if called without going through lzGatedProxy', async () => {
      await expect(
        lensHub.commentWithSig(commentWithSigData)
      ).to.be.revertedWith('CommentOrMirrorInvalid()');
    });

    it('reverts if the caller does not have sufficient balance', async () => {
      await expect(
        lzGatedProxy
          .relayCommentWithSig(
            anotherUserAddress,
            erc721.address,
            LZ_GATED_BALANCE_THRESHOLD,
            0, // lzCustomGasAmount
            commentWithSigData
          )
      ).to.be.revertedWith('InsufficientBalance');
    });

    it('reverts if the contract call for balanceOf() fails', async () => {
      await expect(
        lzGatedProxy
          .relayCommentWithSig(
            userAddress,
            lzEndpoint.address,
            LZ_GATED_BALANCE_THRESHOLD,
            0, // lzCustomGasAmount
            commentWithSigData
          )
      ).to.be.revertedWith('InsufficientBalance');
    });

    it('[non-blocking] fails if the caller passed an invalid threshold', async () => {
      await erc721.safeMint(anotherUserAddress);

      const tx = lzGatedProxy
        .relayCommentWithSig(
          anotherUserAddress,
          erc721.address,
          0,
          0, // lzCustomGasAmount
          commentWithSigData
        );
      const txReceipt = await waitForTx(tx);
      matchEvent(
        txReceipt,
        'MessageFailed',
        undefined,
        referenceModule
      );
      // expect(messageFailedReason).to.equal('InvalidRemoteInput');
    });


    it('[non-blocking] fails if the caller passed an invalid token contract', async () => {
      await erc20.mint(anotherUserAddress, LZ_GATED_BALANCE_THRESHOLD);

      const tx = lzGatedProxy
        .relayCommentWithSig(
          anotherUserAddress,
          erc20.address,
          LZ_GATED_BALANCE_THRESHOLD,
          0, // lzCustomGasAmount
          commentWithSigData
        );
      const txReceipt = await waitForTx(tx);
      matchEvent(
        txReceipt,
        'MessageFailed',
        undefined,
        referenceModule
      );
      // expect(messageFailedReason).to.equal('InvalidRemoteInput');
    });

    it('[non-blocking] fails if the balance check is done against an address other than the signer', async () => {
      await erc721.safeMint(deployerAddress);

      const tx = lzGatedProxy
        .relayCommentWithSig(
          deployerAddress,
          erc721.address,
          LZ_GATED_BALANCE_THRESHOLD,
          0, // lzCustomGasAmount
          commentWithSigData
        );

      const txReceipt = await waitForTx(tx);
      matchEvent(
        txReceipt,
        'MessageFailed',
        undefined,
        referenceModule
      );
      // expect(messageFailedReason).to.equal('InvalidSender');
    });

    it('processes a valid comment', async () => {
      await erc721.safeMint(anotherUserAddress);

      const tx = lzGatedProxy
        .relayCommentWithSig(
          anotherUserAddress,
          erc721.address,
          LZ_GATED_BALANCE_THRESHOLD,
          0, // lzCustomGasAmount
          commentWithSigData
        );
      const txReceipt = await waitForTx(tx);
      const timestamp = await getTimestamp();

      matchEvent(
        txReceipt,
        'CommentCreated',
        [
          FIRST_PROFILE_ID + 1,
          1, // first pub for anotherUser
          OTHER_MOCK_URI,
          FIRST_PROFILE_ID,
          FIRST_PUB_ID,
          EMPTY_BYTES,
          freeCollectModule.address,
          collectModuleInitData,
          ZERO_ADDRESS,
          EMPTY_BYTES,
          timestamp
        ]
      );
    });
  });

  describe('#processMirror (triggered from LZGatedProxy#relayMirrorWithSig)', () => {
    let mirrorWithSigData;
    let referenceModuleInitData;
    let collectModuleInitData;

    beforeEach(async() => {
      collectModuleInitData = ethers.utils.defaultAbiCoder.encode(['bool'], [true]);
      referenceModuleInitData = ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint256', 'uint16'],
        [erc721.address, LZ_GATED_BALANCE_THRESHOLD, LZ_GATED_REMOTE_CHAIN_ID]
      );

      await lensHub.connect(user).post({
        profileId: FIRST_PROFILE_ID,
        contentURI: MOCK_URI,
        collectModule: freeCollectModule.address,
        collectModuleInitData,
        referenceModule: referenceModule.address,
        referenceModuleInitData,
      });

      // anotherUser signs that they would like to mirror the user's first post
      mirrorWithSigData = await signMirrorWithSigData({
        signer: anotherUser,
        profileId: FIRST_PROFILE_ID + 1,
        profileIdPointed: FIRST_PROFILE_ID,
        pubIdPointed: FIRST_PUB_ID,
        referenceModuleData: [],
        referenceModule: ZERO_ADDRESS,
        referenceModuleInitData: [],
      });
    });

    it('reverts if called without going through lzGatedProxy', async () => {
      await expect(
        lensHub.mirrorWithSig(mirrorWithSigData)
      ).to.be.revertedWith('CommentOrMirrorInvalid()');
    });

    it('reverts if the caller does not have sufficient balance', async () => {
      await expect(
        lzGatedProxy
          .relayMirrorWithSig(
            anotherUserAddress,
            erc721.address,
            LZ_GATED_BALANCE_THRESHOLD,
            0, // lzCustomGasAmount
            mirrorWithSigData
          )
      ).to.be.revertedWith('InsufficientBalance');
    });

    it('reverts if the contract call for balanceOf() fails', async () => {
      await expect(
        lzGatedProxy
          .relayMirrorWithSig(
            anotherUserAddress,
            lzEndpoint.address,
            LZ_GATED_BALANCE_THRESHOLD,
            0, // lzCustomGasAmount
            mirrorWithSigData
          )
      ).to.be.revertedWith('InsufficientBalance');
    });

    it('[non-blocking] fails if the caller passed an invalid threshold', async () => {
      await erc721.safeMint(anotherUserAddress);

      const tx = lzGatedProxy
        .relayMirrorWithSig(
          anotherUserAddress,
          erc721.address,
          0,
          0, // lzCustomGasAmount
          mirrorWithSigData
        );

      const txReceipt = await waitForTx(tx);
      matchEvent(
        txReceipt,
        'MessageFailed',
        undefined,
        referenceModule
      );
      // expect(messageFailedReason).to.equal('InvalidRemoteInput');
    });


    it('[non-blocking] fails if the caller passed an invalid token contract', async () => {
      await erc20.mint(anotherUserAddress, LZ_GATED_BALANCE_THRESHOLD);

      const tx = lzGatedProxy
        .relayMirrorWithSig(
          anotherUserAddress,
          erc20.address,
          LZ_GATED_BALANCE_THRESHOLD,
          0, // lzCustomGasAmount
          mirrorWithSigData
        );

      const txReceipt = await waitForTx(tx);
      matchEvent(
        txReceipt,
        'MessageFailed',
        undefined,
        referenceModule
      );
      // expect(messageFailedReason).to.equal('InvalidRemoteInput');
    });

    it('[non-blocking] fails if the balance check is done against an address other than the signer', async () => {
      await erc721.safeMint(deployerAddress);

      const tx = lzGatedProxy
        .relayMirrorWithSig(
          deployerAddress,
          erc721.address,
          LZ_GATED_BALANCE_THRESHOLD,
          0, // lzCustomGasAmount
          mirrorWithSigData
        );

      const txReceipt = await waitForTx(tx);
      matchEvent(
        txReceipt,
        'MessageFailed',
        undefined,
        referenceModule
      );
      // expect(messageFailedReason).to.equal('InvalidSender');
    });

    it('processes a valid mirror', async () => {
      await erc721.safeMint(anotherUserAddress);

      const tx = lzGatedProxy
        .relayMirrorWithSig(
          anotherUserAddress,
          erc721.address,
          LZ_GATED_BALANCE_THRESHOLD,
          0, // lzCustomGasAmount
          mirrorWithSigData
        );
      const txReceipt = await waitForTx(tx);
      const timestamp = await getTimestamp();

      matchEvent(
        txReceipt,
        'MirrorCreated',
        [
          FIRST_PROFILE_ID + 1,
          1, // first pub for anotherUser
          FIRST_PROFILE_ID,
          FIRST_PUB_ID,
          EMPTY_BYTES,
          ZERO_ADDRESS,
          EMPTY_BYTES,
          timestamp
        ]
      );
    });
  });
});
