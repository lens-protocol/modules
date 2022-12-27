import '@nomiclabs/hardhat-ethers';
import { expect } from 'chai';
import { Signer, BigNumber } from 'ethers';
const { getContractAddress } = require('@ethersproject/address');
import { ethers } from 'hardhat';
import {
  FIRST_PROFILE_ID,
  governance,
  lensHub,
  makeSuiteCleanRoom,
  MOCK_FOLLOW_NFT_URI,
  MOCK_PROFILE_HANDLE,
  MOCK_PROFILE_URI,
  deployer,
  user,
  anotherUser,
} from './../../__setup.spec';
import { ERRORS } from './../../helpers/errors';
import { matchEvent, waitForTx, getTimestamp } from './../../helpers/utils';
import signFollowWithSigData from './../../helpers/signatures/core/sign-follow-with-sig-data';
import {
  ZERO_ADDRESS,
  MAX_UINT256,
  EMPTY_BYTES,
  LZ_GATED_REMOTE_CHAIN_ID,
  LZ_GATED_BALANCE_THRESHOLD,
} from './../../helpers/constants';
import {
  LZGatedFollowModule,
  LZGatedFollowModule__factory,
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

makeSuiteCleanRoom('LZGatedFollowModule', function () {
  let lzGatedProxy: LZGatedProxy;
  let lzEndpoint: LZEndpointMock;
  let followModule: LZGatedFollowModule;
  let erc721: ERC721Mock;
  let erc20: ERC20Mock;
  let deployerAddress: string, userAddress: string, anotherUserAddress: string;

  // set the follow module for `user`
  const setFollowModule = async ({
    tokenContract = erc721.address,
    tokenThreshold = LZ_GATED_BALANCE_THRESHOLD,
    chainId = LZ_GATED_REMOTE_CHAIN_ID
  }) => {
    const followModuleInitData = ethers.utils.defaultAbiCoder.encode(
      ['address', 'uint256', 'uint16'],
      [tokenContract, tokenThreshold, chainId]
    );

    return await lensHub.connect(user).setFollowModule(FIRST_PROFILE_ID, followModule.address, followModuleInitData);
  };

  beforeEach(async () => {
    deployerAddress = await deployer.getAddress();
    userAddress = await user.getAddress();
    anotherUserAddress = await anotherUser.getAddress();

    lzEndpoint = await new LZEndpointMock__factory(deployer).deploy(LZ_GATED_REMOTE_CHAIN_ID);
    const transactionCount = await deployer.getTransactionCount();
    const followModuleAddress = getContractAddress({ from: deployerAddress, nonce: transactionCount + 1 });

    lzGatedProxy = await new LZGatedProxy__factory(deployer).deploy(
      lzEndpoint.address,
      LZ_GATED_REMOTE_CHAIN_ID,
      followModuleAddress,
      ZERO_ADDRESS, // _remoteReferenceModule
      ZERO_ADDRESS // _remoteCollectModule
    );
    followModule = await new LZGatedFollowModule__factory(deployer).deploy(
      lensHub.address,
      lzEndpoint.address,
      [LZ_GATED_REMOTE_CHAIN_ID],
      [lzGatedProxy.address]
    );
    erc721 = await new ERC721Mock__factory(deployer).deploy();
    erc20 = await new ERC20Mock__factory(deployer).deploy();

    // use same lz endpoint mock
    await lzEndpoint.setDestLzEndpoint(followModule.address, lzEndpoint.address);
    await lzEndpoint.setDestLzEndpoint(lzGatedProxy.address, lzEndpoint.address);

    await lensHub.connect(governance).whitelistFollowModule(followModule.address, true);

    await lensHub.createProfile({
      to: userAddress,
      handle: MOCK_PROFILE_HANDLE,
      imageURI: MOCK_PROFILE_URI,
      followModule: ZERO_ADDRESS,
      followModuleInitData: [],
      followNFTURI: MOCK_FOLLOW_NFT_URI,
    });
  });

  describe('#constructor', () => {
    it('reverts when the hub arg is the null address', async () => {
      expect(
        new LZGatedFollowModule__factory(deployer).deploy(ZERO_ADDRESS, lzEndpoint.address, [], [])
      ).to.be.revertedWith('InitParamsInvalid');
    });

    it('sets storage', async () => {
      const owner = await followModule.owner();
      const endpoint = await followModule.lzEndpoint();

      expect(owner).to.equal(deployerAddress);
      expect(endpoint).to.equal(lzEndpoint.address);
    });
  });

  describe('#initializeFollowModule', () => {
    it('reverts when the caller is not LensHub', async () => {
      await expect(
        followModule.initializeFollowModule(FIRST_PROFILE_ID, EMPTY_BYTES)
      ).to.be.revertedWith(ERRORS.NOT_HUB);
    });

    it('reverts when an invalid chain id is provided in the encoded data', async () => {
      const followModuleInitData = ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint256', 'uint16'],
        [erc721.address, LZ_GATED_BALANCE_THRESHOLD, 12345]
      );

      await expect(
        lensHub.connect(user).setFollowModule(FIRST_PROFILE_ID, followModule.address, followModuleInitData)
      ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
    });

    it('reverts when token contract as zero address is provided in the encoded data', async () => {
      const followModuleInitData = ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint256', 'uint16'],
        [ZERO_ADDRESS, LZ_GATED_BALANCE_THRESHOLD, LZ_GATED_REMOTE_CHAIN_ID]
      );

      await expect(
        lensHub.connect(user).setFollowModule(FIRST_PROFILE_ID, followModule.address, followModuleInitData)
      ).to.be.revertedWith(ERRORS.INIT_PARAMS_INVALID);
    });

    context('context: with valid params', () => {
      let tx;

      beforeEach(async() => {
        tx = setFollowModule({
          tokenContract: erc721.address,
          tokenThreshold: LZ_GATED_BALANCE_THRESHOLD,
          chainId: LZ_GATED_REMOTE_CHAIN_ID
        });
      });

      it('sets storage', async () => {
        await waitForTx(tx);
        const res = await followModule.gatedFollowPerProfile(FIRST_PROFILE_ID);

        expect(res.balanceThreshold.toNumber()).to.equal(LZ_GATED_BALANCE_THRESHOLD);
        expect(res.tokenContract).to.equal(erc721.address);
        expect(res.remoteChainId).to.equal(LZ_GATED_REMOTE_CHAIN_ID);
      });

      it('emits an event', async () => {
        const txReceipt = await waitForTx(tx);
        matchEvent(
          txReceipt,
          'InitFollowModule',
          [FIRST_PROFILE_ID, erc721.address, LZ_GATED_BALANCE_THRESHOLD, LZ_GATED_REMOTE_CHAIN_ID],
          followModule
        );
      });
    });
  });

  describe('#processFollow (triggered from LZGatedProxy#relayFollowWithSig)', () => {
    let followWithSigData;
    let expectedPayload;

    beforeEach(async() => {
      await setFollowModule({
        tokenContract: erc721.address,
        tokenThreshold: LZ_GATED_BALANCE_THRESHOLD,
        chainId: LZ_GATED_REMOTE_CHAIN_ID
      });

      followWithSigData = await signFollowWithSigData({
        signer: anotherUser,
        profileIds: [FIRST_PROFILE_ID],
        datas: [[]]
      });
    });

    it('reverts if called without going through lzGatedProxy', async () => {
      await expect(
        lensHub.followWithSig(followWithSigData)
      ).to.be.revertedWith(ERRORS.FOLLOW_INVALID);
    });

    it('reverts if the caller does not have sufficient balance', async () => {
      await expect(
        lzGatedProxy
          .relayFollowWithSig(
            erc721.address,
            LZ_GATED_BALANCE_THRESHOLD,
            0, // customGasAmount
            followWithSigData
          )
      ).to.be.revertedWith('InsufficientBalance');
    });

    it('reverts if the contract call for balanceOf() fails', async () => {
      await expect(
        lzGatedProxy
          .relayFollowWithSig(
            lzEndpoint.address,
            LZ_GATED_BALANCE_THRESHOLD,
            0, // customGasAmount
            followWithSigData
          )
      ).to.be.revertedWith('InsufficientBalance');
    });

    it('[non-blocking] fails if the caller passed an invalid threshold', async () => {
      await erc721.safeMint(anotherUserAddress);

      const tx = lzGatedProxy
        .relayFollowWithSig(
          erc721.address,
          0,
          0, // customGasAmount
          followWithSigData
        );

      const txReceipt = await waitForTx(tx);
      matchEvent(
        txReceipt,
        'MessageFailed',
        undefined,
        followModule
      );
      // expect(messageFailedReason).to.equal('InvalidRemoteInput');
    });


    it('[non-blocking] fails if the caller passed an invalid token contract', async () => {
      await erc20.mint(anotherUserAddress, LZ_GATED_BALANCE_THRESHOLD);

      const tx = lzGatedProxy
        .relayFollowWithSig(
          erc20.address,
          LZ_GATED_BALANCE_THRESHOLD,
          0, // customGasAmount
          followWithSigData
        );

      const txReceipt = await waitForTx(tx);
      matchEvent(
        txReceipt,
        'MessageFailed',
        undefined,
        followModule
      );
      // expect(messageFailedReason).to.equal('InvalidRemoteInput');
    });

    it('processes a valid follow', async () => {
      await erc721.safeMint(anotherUserAddress);

      const tx = lzGatedProxy
        .relayFollowWithSig(
          erc721.address,
          LZ_GATED_BALANCE_THRESHOLD,
          0, // customGasAmount
          followWithSigData,
        );

      const txReceipt = await waitForTx(tx);
      const timestamp = await getTimestamp();

      matchEvent(
        txReceipt,
        'Followed',
        [
          anotherUserAddress,
          [FIRST_PROFILE_ID],
          [EMPTY_BYTES],
          timestamp
        ]
      );
    });
  });
});
