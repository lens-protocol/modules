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
} from './../../__setup.spec';
import { ERRORS } from './../../helpers/errors';
import { matchEvent, waitForTx, getTimestamp } from './../../helpers/utils';
import signCollectWithSigData from './../../helpers/signatures/core/sign-collect-with-sig-data';
import {
  ZERO_ADDRESS,
  MAX_UINT256,
  EMPTY_BYTES,
  LZ_GATED_REMOTE_CHAIN_ID,
  LZ_GATED_BALANCE_THRESHOLD,
} from './../../helpers/constants';
import {
  LZGatedCollectModule,
  LZGatedCollectModule__factory,
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

makeSuiteCleanRoom('LZGatedCollectModule', function () {
  let lzGatedProxy: LZGatedProxy;
  let lzEndpoint: LZEndpointMock;
  let collectModule: LZGatedCollectModule;
  let erc721: ERC721Mock;
  let erc20: ERC20Mock;
  let deployerAddress: string, userAddress: string, anotherUserAddress: string;

  beforeEach(async () => {
    deployerAddress = await deployer.getAddress();
    userAddress = await user.getAddress();
    anotherUserAddress = await anotherUser.getAddress();

    lzEndpoint = await new LZEndpointMock__factory(deployer).deploy(LZ_GATED_REMOTE_CHAIN_ID);
    const transactionCount = await deployer.getTransactionCount();
    const collectModuleAddress = getContractAddress({ from: deployerAddress, nonce: transactionCount + 1 });

    lzGatedProxy = await new LZGatedProxy__factory(deployer).deploy(
      lzEndpoint.address,
      LZ_GATED_REMOTE_CHAIN_ID,
      ZERO_ADDRESS, // _remoteFollowModule
      ZERO_ADDRESS, // _remoteReferenceModule
      collectModuleAddress
    );
    collectModule = await new LZGatedCollectModule__factory(deployer).deploy(
      lensHub.address,
      lzEndpoint.address,
      [LZ_GATED_REMOTE_CHAIN_ID],
      [lzGatedProxy.address]
    );
    erc721 = await new ERC721Mock__factory(deployer).deploy();
    erc20 = await new ERC20Mock__factory(deployer).deploy();

    // use same lz endpoint mock
    await lzEndpoint.setDestLzEndpoint(collectModule.address, lzEndpoint.address);
    await lzEndpoint.setDestLzEndpoint(lzGatedProxy.address, lzEndpoint.address);

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
        new LZGatedCollectModule__factory(deployer).deploy(ZERO_ADDRESS, lzEndpoint.address, [], [])
      ).to.be.revertedWith('InitParamsInvalid');
    });

    it('sets storage', async () => {
      const owner = await collectModule.owner();
      const endpoint = await collectModule.lzEndpoint();

      expect(owner).to.equal(deployerAddress);
      expect(endpoint).to.equal(lzEndpoint.address);
    });
  });

  describe('#initializePublicationCollectModule', () => {
    it('reverts when the caller is not LensHub', async () => {
      await expect(
        collectModule.initializePublicationCollectModule(FIRST_PROFILE_ID, 1, EMPTY_BYTES)
      ).to.be.revertedWith(ERRORS.NOT_HUB);
    });

    it('reverts when an invalid chain id is provided in the encoded data', async () => {
      const collectModuleInitData = ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint256', 'uint16'],
        [erc721.address, LZ_GATED_BALANCE_THRESHOLD, 12345]
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

    it('reverts when token contract as zero address is provided in the encoded data', async () => {
      const collectModuleInitData = ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint256', 'uint16'],
        [ZERO_ADDRESS, LZ_GATED_BALANCE_THRESHOLD, LZ_GATED_REMOTE_CHAIN_ID]
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

    context('context: with valid params', () => {
      let tx;

      beforeEach(async() => {
        const collectModuleInitData = ethers.utils.defaultAbiCoder.encode(
          ['address', 'uint256', 'uint16'],
          [erc721.address, LZ_GATED_BALANCE_THRESHOLD, LZ_GATED_REMOTE_CHAIN_ID]
        );
        tx = lensHub.connect(user).post({
          profileId: FIRST_PROFILE_ID,
          contentURI: MOCK_URI,
          collectModule: collectModule.address,
          collectModuleInitData,
          referenceModule: ZERO_ADDRESS,
          referenceModuleInitData: [],
        });
      });

      it('sets storage', async () => {
        await waitForTx(tx);
        const res = await collectModule.gatedCollectDataPerPub(FIRST_PROFILE_ID, 1);

        expect(res.balanceThreshold.toNumber()).to.equal(LZ_GATED_BALANCE_THRESHOLD);
        expect(res.tokenContract).to.equal(erc721.address);
        expect(res.remoteChainId).to.equal(LZ_GATED_REMOTE_CHAIN_ID);
      });

      it('emits an event', async () => {
        const txReceipt = await waitForTx(tx);
        matchEvent(
          txReceipt,
          'InitCollectModule',
          [FIRST_PROFILE_ID, FIRST_PUB_ID, erc721.address, LZ_GATED_BALANCE_THRESHOLD, LZ_GATED_REMOTE_CHAIN_ID],
          collectModule
        );
      });
    });
  });

  describe('#processCollect (triggered from LZGatedProxy#relayCollectWithSig)', () => {
    let collectWithSigData;
    let collectModuleInitData;

    beforeEach(async() => {
      collectModuleInitData = ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint256', 'uint16'],
        [erc721.address, LZ_GATED_BALANCE_THRESHOLD, LZ_GATED_REMOTE_CHAIN_ID]
      );

      await lensHub.connect(user).post({
        profileId: FIRST_PROFILE_ID,
        contentURI: MOCK_URI,
        collectModule: collectModule.address,
        collectModuleInitData,
        referenceModule: ZERO_ADDRESS,
        referenceModuleInitData: [],
      });

      // anotherUser signs that they would like to collect user's first post
      collectWithSigData = await signCollectWithSigData({
        signer: anotherUser,
        profileId: FIRST_PROFILE_ID,
        pubId: FIRST_PUB_ID,
        data: []
      });
    });

    it('reverts if called without going through lzGatedProxy', async () => {
      await expect(
        lensHub.collectWithSig(collectWithSigData)
      ).to.be.revertedWith('CollectNotAllowed()');
    });

    it('reverts if the caller does not have sufficient balance', async () => {
      await expect(
        lzGatedProxy
          .connect(anotherUser)
          .relayCollectWithSig(
            erc721.address,
            LZ_GATED_BALANCE_THRESHOLD,
            0, // lzCustomGasAmount
            collectWithSigData
          )
      ).to.be.revertedWith('InsufficientBalance');
    });

    it('reverts if the contract call for balanceOf() fails', async () => {
      await expect(
        lzGatedProxy
          .connect(anotherUser)
          .relayCollectWithSig(
            lzEndpoint.address,
            LZ_GATED_BALANCE_THRESHOLD,
            0, // lzCustomGasAmount
            collectWithSigData
          )
      ).to.be.revertedWith('InsufficientBalance');
    });

    it('[non-blocking] fails if the caller passed an invalid threshold', async () => {
      await erc721.safeMint(anotherUserAddress);

      const tx = lzGatedProxy
        .connect(anotherUser)
        .relayCollectWithSig(
          erc721.address,
          0,
          0, // lzCustomGasAmount
          collectWithSigData
        );

      const txReceipt = await waitForTx(tx);
      matchEvent(
        txReceipt,
        'MessageFailed',
        undefined, // @TODO: need all the args
        collectModule
      );
      // expect(messageFailedReason).to.equal('InvalidRemoteInput');
    });


    it('[non-blocking] fails if the caller passed an invalid token contract', async () => {
      await erc20.mint(anotherUserAddress, LZ_GATED_BALANCE_THRESHOLD);

      const tx = lzGatedProxy
        .connect(anotherUser)
        .relayCollectWithSig(
          erc20.address,
          LZ_GATED_BALANCE_THRESHOLD,
          0, // lzCustomGasAmount
          collectWithSigData
        );

      const txReceipt = await waitForTx(tx);
      matchEvent(
        txReceipt,
        'MessageFailed',
        undefined, // @TODO: need all the args
        collectModule
      );
      // expect(messageFailedReason).to.equal('InvalidRemoteInput');
    });

    it('processes a valid collect', async () => {
      await erc721.safeMint(anotherUserAddress);

      const tx = lzGatedProxy
        .connect(anotherUser)
        .relayCollectWithSig(
          erc721.address,
          LZ_GATED_BALANCE_THRESHOLD,
          0, // lzCustomGasAmount
          collectWithSigData
        );

      const txReceipt = await waitForTx(tx);
      const timestamp = await getTimestamp();

      matchEvent(
        txReceipt,
        'Collected',
        [
          anotherUserAddress,
          FIRST_PROFILE_ID,
          1, // first pub from anotherUser
          FIRST_PROFILE_ID,
          FIRST_PUB_ID,
          EMPTY_BYTES,
          timestamp
        ]
      );
    });
  });
});
