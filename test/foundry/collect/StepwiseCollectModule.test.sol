// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import '../BaseSetup.t.sol';
import {StepwiseCollectModuleBase} from './StepwiseCollectModule.base.sol';
import '../helpers/TestHelpers.sol';
import {CurveParameters, StepwiseCollectModule} from 'contracts/collect/StepwiseCollectModule.sol';

/////////
// Publication Creation with StepwiseCollectModule
//
contract StepwiseCollectModule_Publication is StepwiseCollectModuleBase {
    uint256 immutable userProfileId;

    constructor() StepwiseCollectModuleBase() {
        vm.recordLogs();
        hub.createProfile(
            DataTypes.CreateProfileData({
                to: me,
                handle: 'user.lens',
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
    function testCannotPostWithZeroCollectLimit() public {
        vm.expectRevert(Errors.InitParamsInvalid.selector);
        hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(
                    0,
                    address(currency),
                    me,
                    REFERRAL_FEE_BPS,
                    true,
                    0,
                    CurveParameters(0, 0, 10 ether)
                ),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
    }

    function testCannotPostWithUnwhitelistedCurrncy() public {
        vm.expectRevert(Errors.InitParamsInvalid.selector);
        hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(
                    DEFAULT_COLLECT_LIMIT,
                    address(treasury),
                    me,
                    REFERRAL_FEE_BPS,
                    true,
                    0,
                    CurveParameters(0, 0, 10 ether)
                ),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
    }

    function testCannotPostWithZeroRecipient() public {
        vm.expectRevert(Errors.InitParamsInvalid.selector);
        hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(
                    DEFAULT_COLLECT_LIMIT,
                    address(currency),
                    address(0),
                    REFERRAL_FEE_BPS,
                    true,
                    0,
                    CurveParameters(0, 0, 10 ether)
                ),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
    }

    function testCannotPostWithReferralFeeGreaterThanMaxBPS() public {
        vm.expectRevert(Errors.InitParamsInvalid.selector);
        hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(
                    DEFAULT_COLLECT_LIMIT,
                    address(currency),
                    me,
                    10001, // TODO: replace with MaxBPS constant
                    true,
                    0,
                    CurveParameters(0, 0, 10 ether)
                ),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
    }

    function testCannotPostWithPastNonzeroTimestamp() public {
        vm.warp(1666666666);
        vm.expectRevert(Errors.InitParamsInvalid.selector);
        hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(
                    DEFAULT_COLLECT_LIMIT,
                    address(currency),
                    me,
                    REFERRAL_FEE_BPS,
                    true,
                    block.timestamp - 1,
                    CurveParameters(0, 0, 10 ether)
                ),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
    }

    function testCannotPostWithWrongInitDataFormat() public {
        vm.expectRevert();
        hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(DEFAULT_COLLECT_LIMIT, REFERRAL_FEE_BPS, true),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
    }

    function testCannotPostIfCalledFromNonHubAddress() public {
        vm.expectRevert(Errors.NotHub.selector);
        stepwiseCollectModule.initializePublicationCollectModule(
            userProfileId,
            1,
            abi.encode(
                DEFAULT_COLLECT_LIMIT,
                address(currency),
                me,
                REFERRAL_FEE_BPS,
                true,
                0,
                CurveParameters(0, 0, 10 ether)
            )
        );
    }

    // Scenarios
    function testCreatePublicationWithCorrectInitData() public {
        hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(
                    DEFAULT_COLLECT_LIMIT,
                    address(currency),
                    me,
                    REFERRAL_FEE_BPS,
                    true,
                    0,
                    CurveParameters(0, 0, 10 ether)
                ),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
    }

    function testCreatePublicationEmitsExpectedEvents() public {
        vm.recordLogs();
        hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(
                    DEFAULT_COLLECT_LIMIT,
                    address(currency),
                    me,
                    REFERRAL_FEE_BPS,
                    true,
                    0,
                    CurveParameters(0, 0, 10 ether)
                ),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 pubId = TestHelpers.getCreatedPubIdFromEvents(entries);
        assertEq(pubId, 1);
    }
}

/////////
// Collect with StepwiseCollectModule
//
contract StepwiseCollectModule_Collect is StepwiseCollectModuleBase {
    uint256 immutable publisherProfileId;
    uint256 immutable userProfileId;

    uint256 pubId;

    constructor() StepwiseCollectModuleBase() {
        vm.recordLogs();
        hub.createProfile(
            DataTypes.CreateProfileData({
                to: publisher,
                handle: 'publisher.lens',
                imageURI: OTHER_MOCK_URI,
                followModule: address(0),
                followModuleInitData: '',
                followNFTURI: MOCK_FOLLOW_NFT_URI
            })
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        userProfileId = TestHelpers.getCreatedProfileIdFromEvents(entries);
    }

    function setUp() public {
        bytes referenceModuleInitData = abi.encode(
            DEFAULT_COLLECT_LIMIT,
            address(currency),
            me,
            REFERRAL_FEE_BPS,
            true,
            0,
            CurveParameters(0, 0, 10 ether)
        );

        vm.recordLogs();
        vm.prank(publisher);
        hub.post(
            DataTypes.PostData({
                profileId: publisherProfileId,
                contentURI: MOCK_URI,
                collectModule: stepwiseCollectModule,
                collectModuleInitData: abi.encode(false),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        pubId = TestHelpers.getCreatedPubIdFromEvents(entries);
    }
}
