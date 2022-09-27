// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import '../BaseSetup.t.sol';
import {StepwiseCollectModuleBase} from './StepwiseCollectModule.base.sol';
import '../helpers/TestHelpers.sol';
import {ProfilePublicationData, StepwiseCollectModuleInitData, StepwiseCollectModule} from 'contracts/collect/StepwiseCollectModule.sol';

/////////
// Publication Creation with StepwiseCollectModule
//
contract StepwiseCollectModule_Publication is StepwiseCollectModuleBase {
    uint256 immutable userProfileId;

    StepwiseCollectModuleInitData exampleInitData;

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

    function setUp() public {
        exampleInitData = StepwiseCollectModuleInitData({
            collectLimit: 0,
            currency: address(currency),
            recipient: me,
            referralFee: 0,
            followerOnly: false,
            endTimestamp: 0,
            a: 0,
            b: 0,
            c: 1 ether
        });
    }

    function hubPostWithRevert(bytes4 expectedError) public {
        vm.expectRevert(expectedError);
        hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(exampleInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
    }

    // Negatives
    function testCannotPostWithNonWhitelistedCurrncy() public {
        exampleInitData.currency = address(0);
        hubPostWithRevert(Errors.InitParamsInvalid.selector);
    }

    function testCannotPostWithZeroRecipient() public {
        exampleInitData.recipient = address(0);
        hubPostWithRevert(Errors.InitParamsInvalid.selector);
    }

    function testCannotPostWithReferralFeeGreaterThanMaxBPS() public {
        exampleInitData.referralFee = TREASURY_FEE_MAX_BPS + 1;
        hubPostWithRevert(Errors.InitParamsInvalid.selector);
    }

    function testCannotPostWithPastNonzeroTimestamp() public {
        vm.warp(1666666666);
        exampleInitData.endTimestamp = uint40(block.timestamp) - 1;
        hubPostWithRevert(Errors.InitParamsInvalid.selector);
    }

    function testCannotPostIfCalledFromNonHubAddress() public {
        vm.expectRevert(Errors.NotHub.selector);
        stepwiseCollectModule.initializePublicationCollectModule(
            userProfileId,
            1,
            abi.encode(exampleInitData)
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

    // Scenarios
    function testCreatePublicationWithCorrectInitData() public {
        hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(exampleInitData),
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
                collectModuleInitData: abi.encode(exampleInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 pubId = TestHelpers.getCreatedPubIdFromEvents(entries);
        assertEq(pubId, 1);
    }

    function testFuzzCreatePublicationWithDifferentInitData(
        uint64 collectLimit,
        uint16 referralFee,
        bool followerOnly,
        uint40 endTimestamp,
        uint72 a,
        uint56 b,
        uint128 c
    ) public {
        vm.assume(referralFee <= TREASURY_FEE_MAX_BPS);
        vm.assume(endTimestamp > block.timestamp);

        StepwiseCollectModuleInitData memory fuzzyInitData = StepwiseCollectModuleInitData({
            collectLimit: collectLimit,
            currency: address(currency),
            recipient: me,
            referralFee: referralFee,
            followerOnly: followerOnly,
            endTimestamp: endTimestamp,
            a: a,
            b: b,
            c: c
        });
        hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(fuzzyInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
    }

    function testFuzzFetchedPublicationDataShouldBeAccurate(
        uint64 collectLimit,
        uint16 referralFee,
        bool followerOnly,
        uint40 endTimestamp,
        uint72 a,
        uint56 b,
        uint128 c
    ) public {
        vm.assume(referralFee <= TREASURY_FEE_MAX_BPS);
        vm.assume(endTimestamp > block.timestamp);

        StepwiseCollectModuleInitData memory fuzzyInitData = StepwiseCollectModuleInitData({
            collectLimit: collectLimit,
            currency: address(currency),
            recipient: me,
            referralFee: referralFee,
            followerOnly: followerOnly,
            endTimestamp: endTimestamp,
            a: a,
            b: b,
            c: c
        });

        vm.recordLogs();
        hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(fuzzyInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 pubId = TestHelpers.getCreatedPubIdFromEvents(entries);
        assert(pubId > 0);
        ProfilePublicationData memory fetchedData = stepwiseCollectModule.getPublicationData(
            userProfileId,
            pubId
        );
        assertEq(fetchedData.currency, fuzzyInitData.currency);
        assertEq(fetchedData.a, fuzzyInitData.a);
        assertEq(fetchedData.referralFee, fuzzyInitData.referralFee);
        assertEq(fetchedData.followerOnly, fuzzyInitData.followerOnly);
        assertEq(fetchedData.recipient, fuzzyInitData.recipient);
        assertEq(fetchedData.b, fuzzyInitData.b);
        assertEq(fetchedData.endTimestamp, fuzzyInitData.endTimestamp);
        assertEq(fetchedData.c, fuzzyInitData.c);
        assertEq(fetchedData.collectLimit, fuzzyInitData.collectLimit);
    }
}

/////////
// Collect with StepwiseCollectModule
//
// contract StepwiseCollectModule_Collect is StepwiseCollectModuleBase {
//     uint256 immutable publisherProfileId;
//     uint256 immutable userProfileId;

//     uint256 pubId;

//     constructor() StepwiseCollectModuleBase() {
//         vm.recordLogs();
//         hub.createProfile(
//             DataTypes.CreateProfileData({
//                 to: publisher,
//                 handle: 'publisher.lens',
//                 imageURI: OTHER_MOCK_URI,
//                 followModule: address(0),
//                 followModuleInitData: '',
//                 followNFTURI: MOCK_FOLLOW_NFT_URI
//             })
//         );
//         Vm.Log[] memory entries = vm.getRecordedLogs();
//         userProfileId = TestHelpers.getCreatedProfileIdFromEvents(entries);
//     }

//     function setUp() public {
//         bytes referenceModuleInitData = abi.encode(
//             DEFAULT_COLLECT_LIMIT,
//             address(currency),
//             me,
//             REFERRAL_FEE_BPS,
//             true,
//             0,
//             CurveParameters(0, 0, 10 ether)
//         );

//         vm.recordLogs();
//         vm.prank(publisher);
//         hub.post(
//             DataTypes.PostData({
//                 profileId: publisherProfileId,
//                 contentURI: MOCK_URI,
//                 collectModule: stepwiseCollectModule,
//                 collectModuleInitData: abi.encode(false),
//                 referenceModule: address(0),
//                 referenceModuleInitData: ''
//             })
//         );
//         Vm.Log[] memory entries = vm.getRecordedLogs();
//         pubId = TestHelpers.getCreatedPubIdFromEvents(entries);
//     }
// }
