// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import '../BaseSetup.t.sol';
import {TokenGatedReferenceModuleBase} from './TokenGatedReferenceModule.base.sol';
import '../helpers/TestHelpers.sol';
import {TokenGatedReferenceModule} from 'contracts/reference/TokenGatedReferenceModule.sol';

/////////
// Publication Creation with TokenGatedReferenceModule
//
contract TokenGatedReferenceModule_Publication is TokenGatedReferenceModuleBase {
    uint256 immutable userProfileId;

    constructor() TokenGatedReferenceModuleBase() {
        vm.recordLogs();
        hub.createProfile(
            DataTypes.CreateProfileData({
                to: me,
                handle: 'user',
                imageURI: OTHER_MOCK_URI,
                followModule: address(0),
                followModuleInitData: '',
                followNFTURI: MOCK_FOLLOW_NFT_URI
            })
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        userProfileId = TestHelpers.getCreatedProfileIdFromEvents(entries);
    }

    // Negatives
    function testCannotPostWithZeroTokenAddress() public {
        vm.expectRevert(Errors.InitParamsInvalid.selector);
        hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: address(freeCollectModule),
                collectModuleInitData: abi.encode(false),
                referenceModule: address(tokenGatedReferenceModule),
                referenceModuleInitData: abi.encode(address(0), 1)
            })
        );
    }

    function testCannotPostWithZeroMinThreshold() public {
        vm.expectRevert(Errors.InitParamsInvalid.selector);
        hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: address(freeCollectModule),
                collectModuleInitData: abi.encode(false),
                referenceModule: address(tokenGatedReferenceModule),
                referenceModuleInitData: abi.encode(address(currency), 0)
            })
        );
    }

    function testCannotCallInitializeFromNonHub() public {
        vm.expectRevert(Errors.NotHub.selector);
        tokenGatedReferenceModule.initializeReferenceModule(
            userProfileId,
            1,
            abi.encode(address(currency), 1)
        );
    }

    function testCannotProcessCommentFromNonHub() public {
        vm.expectRevert(Errors.NotHub.selector);
        tokenGatedReferenceModule.processComment(userProfileId, userProfileId, 1, '');
    }

    function testCannotProcessMirrorFromNonHub() public {
        vm.expectRevert(Errors.NotHub.selector);
        tokenGatedReferenceModule.processMirror(userProfileId, userProfileId, 1, '');
    }

    // Scenarios
    function testCreatePublicationWithTokenGatedReferenceModule() public {
        hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: address(freeCollectModule),
                collectModuleInitData: abi.encode(false),
                referenceModule: address(tokenGatedReferenceModule),
                referenceModuleInitData: abi.encode(address(currency), 1)
            })
        );
    }

    function testCreatePublicationWithTokenGatedReferenceModuleEmitsExpectedEvents() public {
        vm.recordLogs();
        hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: address(freeCollectModule),
                collectModuleInitData: abi.encode(false),
                referenceModule: address(tokenGatedReferenceModule),
                referenceModuleInitData: abi.encode(address(currency), 1)
            })
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 pubId = TestHelpers.getCreatedPubIdFromEvents(entries);
        assertEq(pubId, 1);
    }
}

/////////
// ERC20-Gated Reference
//
contract TokenGatedReferenceModule_ERC20_Gated is TokenGatedReferenceModuleBase {
    uint256 immutable publisherProfileId;
    uint256 immutable userProfileId;

    address immutable tokenAddress;
    uint256 constant minThreshold = 10 ether;

    bytes referenceModuleInitData;

    uint256 pubId;

    constructor() TokenGatedReferenceModuleBase() {
        vm.recordLogs();
        hub.createProfile(
            DataTypes.CreateProfileData({
                to: publisher,
                handle: MOCK_HANDLE,
                imageURI: MOCK_URI,
                followModule: address(0),
                followModuleInitData: '',
                followNFTURI: MOCK_URI
            })
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        publisherProfileId = TestHelpers.getCreatedProfileIdFromEvents(entries);
        vm.recordLogs();
        hub.createProfile(
            DataTypes.CreateProfileData({
                to: me,
                handle: 'user',
                imageURI: OTHER_MOCK_URI,
                followModule: address(0),
                followModuleInitData: '',
                followNFTURI: MOCK_FOLLOW_NFT_URI
            })
        );
        entries = vm.getRecordedLogs();
        userProfileId = TestHelpers.getCreatedProfileIdFromEvents(entries);

        tokenAddress = address(currency);
        referenceModuleInitData = abi.encode(tokenAddress, minThreshold);
    }

    function setUp() public {
        vm.recordLogs();
        vm.prank(publisher);
        hub.post(
            DataTypes.PostData({
                profileId: publisherProfileId,
                contentURI: MOCK_URI,
                collectModule: address(freeCollectModule),
                collectModuleInitData: abi.encode(false),
                referenceModule: address(tokenGatedReferenceModule),
                referenceModuleInitData: referenceModuleInitData
            })
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        pubId = TestHelpers.getCreatedPubIdFromEvents(entries);
    }

    // Negatives
    function testCannotMirrorIfNotEnoughBalance() public {
        vm.expectRevert(TokenGatedReferenceModule.NotEnoughBalance.selector);
        hub.mirror(
            DataTypes.MirrorData({
                profileId: userProfileId,
                profileIdPointed: publisherProfileId,
                pubIdPointed: pubId,
                referenceModuleData: '',
                referenceModule: address(tokenGatedReferenceModule),
                referenceModuleInitData: referenceModuleInitData
            })
        );
    }

    function testCannotCommentIfNotEnoughBalance() public {
        vm.expectRevert(TokenGatedReferenceModule.NotEnoughBalance.selector);
        hub.comment(
            DataTypes.CommentData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                profileIdPointed: publisherProfileId,
                pubIdPointed: pubId,
                collectModule: address(freeCollectModule),
                collectModuleInitData: abi.encode(false),
                referenceModuleData: '',
                referenceModule: address(tokenGatedReferenceModule),
                referenceModuleInitData: referenceModuleInitData
            })
        );
    }

    // Scenarios
    function testMirrorWhileHoldingEnoughTokens() public {
        currency.mint(me, minThreshold);
        assert(currency.balanceOf(me) >= minThreshold);
        hub.mirror(
            DataTypes.MirrorData({
                profileId: userProfileId,
                profileIdPointed: publisherProfileId,
                pubIdPointed: pubId,
                referenceModuleData: '',
                referenceModule: address(tokenGatedReferenceModule),
                referenceModuleInitData: referenceModuleInitData
            })
        );
    }

    function testCommentWhileHoldingEnoughTokens() public {
        currency.mint(me, minThreshold);
        assert(currency.balanceOf(me) >= minThreshold);
        hub.comment(
            DataTypes.CommentData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                profileIdPointed: publisherProfileId,
                pubIdPointed: pubId,
                collectModule: address(freeCollectModule),
                collectModuleInitData: abi.encode(false),
                referenceModuleData: '',
                referenceModule: address(tokenGatedReferenceModule),
                referenceModuleInitData: referenceModuleInitData
            })
        );
    }
}

/////////
// ERC721-Gated Reference
//
contract TokenGatedReferenceModule_ERC721_Gated is TokenGatedReferenceModuleBase {
    uint256 immutable publisherProfileId;
    uint256 immutable userProfileId;

    address immutable tokenAddress;
    uint256 constant minThreshold = 1;

    bytes referenceModuleInitData;

    uint256 pubId;

    constructor() TokenGatedReferenceModuleBase() {
        vm.recordLogs();
        hub.createProfile(
            DataTypes.CreateProfileData({
                to: publisher,
                handle: MOCK_HANDLE,
                imageURI: MOCK_URI,
                followModule: address(0),
                followModuleInitData: '',
                followNFTURI: MOCK_URI
            })
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        publisherProfileId = TestHelpers.getCreatedProfileIdFromEvents(entries);
        vm.recordLogs();
        hub.createProfile(
            DataTypes.CreateProfileData({
                to: me,
                handle: 'user',
                imageURI: OTHER_MOCK_URI,
                followModule: address(0),
                followModuleInitData: '',
                followNFTURI: MOCK_FOLLOW_NFT_URI
            })
        );
        entries = vm.getRecordedLogs();
        userProfileId = TestHelpers.getCreatedProfileIdFromEvents(entries);

        tokenAddress = address(nft);
        referenceModuleInitData = abi.encode(tokenAddress, minThreshold);
    }

    function setUp() public {
        vm.recordLogs();
        vm.prank(publisher);
        hub.post(
            DataTypes.PostData({
                profileId: publisherProfileId,
                contentURI: MOCK_URI,
                collectModule: address(freeCollectModule),
                collectModuleInitData: abi.encode(false),
                referenceModule: address(tokenGatedReferenceModule),
                referenceModuleInitData: referenceModuleInitData
            })
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        pubId = TestHelpers.getCreatedPubIdFromEvents(entries);
        console.log('post created:', pubId);
    }

    // Negatives
    function testCannotMirrorIfNotEnoughBalance() public {
        vm.expectRevert(TokenGatedReferenceModule.NotEnoughBalance.selector);
        hub.mirror(
            DataTypes.MirrorData({
                profileId: userProfileId,
                profileIdPointed: publisherProfileId,
                pubIdPointed: pubId,
                referenceModuleData: '',
                referenceModule: address(tokenGatedReferenceModule),
                referenceModuleInitData: referenceModuleInitData
            })
        );
    }

    function testCannotCommentIfNotEnoughBalance() public {
        vm.expectRevert(TokenGatedReferenceModule.NotEnoughBalance.selector);
        hub.comment(
            DataTypes.CommentData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                profileIdPointed: publisherProfileId,
                pubIdPointed: pubId,
                collectModule: address(freeCollectModule),
                collectModuleInitData: abi.encode(false),
                referenceModuleData: '',
                referenceModule: address(tokenGatedReferenceModule),
                referenceModuleInitData: referenceModuleInitData
            })
        );
    }

    // Scenarios
    function testMirrorWhileHoldingEnoughTokens() public {
        nft.mint(me, 1);
        assert(nft.balanceOf(me) >= minThreshold);
        hub.mirror(
            DataTypes.MirrorData({
                profileId: userProfileId,
                profileIdPointed: publisherProfileId,
                pubIdPointed: pubId,
                referenceModuleData: '',
                referenceModule: address(tokenGatedReferenceModule),
                referenceModuleInitData: referenceModuleInitData
            })
        );
    }

    function testCommentWhileHoldingEnoughTokens() public {
        nft.mint(me, 1);
        assert(nft.balanceOf(me) >= minThreshold);
        hub.comment(
            DataTypes.CommentData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                profileIdPointed: publisherProfileId,
                pubIdPointed: pubId,
                collectModule: address(freeCollectModule),
                collectModuleInitData: abi.encode(false),
                referenceModuleData: '',
                referenceModule: address(tokenGatedReferenceModule),
                referenceModuleInitData: referenceModuleInitData
            })
        );
    }
}
