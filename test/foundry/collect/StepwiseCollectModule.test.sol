// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import '../BaseSetup.t.sol';
import {StepwiseCollectModuleBase} from './StepwiseCollectModule.base.sol';
import '../helpers/TestHelpers.sol';
import {ProfilePublicationData, StepwiseCollectModuleInitData, StepwiseCollectModule} from 'contracts/collect/StepwiseCollectModule.sol';
import '@aave/lens-protocol/contracts/libraries/Events.sol';

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

/////////////
// Collect with StepwiseCollectModule

contract StepwiseCollectModule_Collect is StepwiseCollectModuleBase {
    uint256 immutable publisherProfileId;
    uint256 immutable userProfileId;

    uint256 pubId;

    StepwiseCollectModuleInitData exampleInitData;

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
        publisherProfileId = TestHelpers.getCreatedProfileIdFromEvents(entries);

        vm.recordLogs();
        hub.createProfile(
            DataTypes.CreateProfileData({
                to: user,
                handle: 'user.lens',
                imageURI: OTHER_MOCK_URI,
                followModule: address(0),
                followModuleInitData: '',
                followNFTURI: MOCK_FOLLOW_NFT_URI
            })
        );
        entries = vm.getRecordedLogs();
        userProfileId = TestHelpers.getCreatedProfileIdFromEvents(entries);
    }

    function setUp() public virtual {
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

        vm.recordLogs();
        vm.prank(publisher);
        hub.post(
            DataTypes.PostData({
                profileId: publisherProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(exampleInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        pubId = TestHelpers.getCreatedPubIdFromEvents(entries);

        currency.mint(user, type(uint256).max);
        vm.prank(user);
        currency.approve(address(stepwiseCollectModule), type(uint256).max);
    }

    // Negatives

    function testCannotCollectIfCalledFromNonHubAddress() public {
        vm.expectRevert(Errors.NotHub.selector);
        stepwiseCollectModule.processCollect(
            publisherProfileId,
            me,
            publisherProfileId,
            pubId,
            abi.encode(address(currency), 1 ether)
        );
    }

    function testCannotCollectNonExistentPublication() public {
        vm.prank(user);
        vm.expectRevert(Errors.PublicationDoesNotExist.selector);
        hub.collect(publisherProfileId, pubId + 1, abi.encode(address(currency), 1 ether));
    }

    function testCannotCollectPassingWrongAmountInData() public {
        vm.prank(user);
        vm.expectRevert(Errors.ModuleDataMismatch.selector);
        hub.collect(publisherProfileId, pubId, abi.encode(address(currency), 0.5 ether));
    }

    function testCannotCollectPassingWrongCurrencyInData() public {
        vm.prank(user);
        vm.expectRevert(Errors.ModuleDataMismatch.selector);
        hub.collect(publisherProfileId, pubId, abi.encode(address(0xdead), 1 ether));
    }

    function testCannotCollectWithoutEnoughApproval() public {
        vm.startPrank(user);
        currency.approve(address(stepwiseCollectModule), 0);
        assert(currency.allowance(user, address(stepwiseCollectModule)) < 1 ether);
        vm.expectRevert('ERC20: insufficient allowance');
        hub.collect(publisherProfileId, pubId, abi.encode(address(currency), 1 ether));
        vm.stopPrank();
    }

    function testCannotCollectWithoutEnoughBalance() public {
        vm.startPrank(user);
        currency.transfer(address(1), currency.balanceOf(user));
        assertEq(currency.balanceOf(user), 0);
        assert(currency.allowance(user, address(stepwiseCollectModule)) >= 1 ether);
        vm.expectRevert('ERC20: transfer amount exceeds balance');
        hub.collect(publisherProfileId, pubId, abi.encode(address(currency), 1 ether));
        vm.stopPrank();
    }

    function hubPost(StepwiseCollectModuleInitData memory initData)
        public
        virtual
        returns (uint256)
    {
        vm.recordLogs();
        vm.prank(publisher);
        hub.post(
            DataTypes.PostData({
                profileId: publisherProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(initData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        return TestHelpers.getCreatedPubIdFromEvents(entries);
    }

    function testCannotCollectIfNotAFollower() public {
        exampleInitData.followerOnly = true;
        uint256 secondPubId = hubPost(exampleInitData);
        vm.startPrank(user);
        vm.expectRevert(Errors.FollowInvalid.selector);
        hub.collect(publisherProfileId, secondPubId, abi.encode(address(currency), 1 ether));
        vm.stopPrank();
    }

    function testCannotCollectAfterEndTimestamp() public {
        exampleInitData.endTimestamp = 100;
        uint256 secondPubId = hubPost(exampleInitData);

        vm.warp(101);

        vm.startPrank(user);
        vm.expectRevert(Errors.CollectExpired.selector);
        hub.collect(publisherProfileId, secondPubId, abi.encode(address(currency), 1 ether));
        vm.stopPrank();
    }

    function testCannotCollectMoreThanLimit() public {
        exampleInitData.collectLimit = 3;
        uint256 secondPubId = hubPost(exampleInitData);

        vm.startPrank(user);
        hub.collect(publisherProfileId, secondPubId, abi.encode(address(currency), 1 ether));
        hub.collect(publisherProfileId, secondPubId, abi.encode(address(currency), 1 ether));
        hub.collect(publisherProfileId, secondPubId, abi.encode(address(currency), 1 ether));
        vm.expectRevert(Errors.MintLimitExceeded.selector);
        hub.collect(publisherProfileId, secondPubId, abi.encode(address(currency), 1 ether));
        vm.stopPrank();
    }

    //Scenarios

    function testCanCollectIfAllConditionsAreMet() public {
        uint256 secondPubId = hubPost(exampleInitData);
        vm.startPrank(user);
        hub.collect(publisherProfileId, secondPubId, abi.encode(address(currency), 1 ether));
        vm.stopPrank();
    }

    function testProperEventsAreEmittedAfterCollect() public {
        uint256 secondPubId = hubPost(exampleInitData);
        vm.startPrank(user);

        vm.expectEmit(true, true, true, false);
        emit Events.Collected(
            user,
            publisherProfileId,
            secondPubId,
            publisherProfileId,
            secondPubId,
            '',
            block.timestamp
        );
        hub.collect(publisherProfileId, secondPubId, abi.encode(address(currency), 1 ether));

        vm.stopPrank();
    }

    function testCurrentCollectsIncreaseProperlyWhenCollecting() public virtual {
        uint256 secondPubId = hubPost(exampleInitData);
        vm.startPrank(user);

        ProfilePublicationData memory fetchedData = stepwiseCollectModule.getPublicationData(
            publisherProfileId,
            secondPubId
        );
        assertEq(fetchedData.currentCollects, 0);

        for (uint256 collects = 1; collects < 5; collects++) {
            hub.collect(publisherProfileId, secondPubId, abi.encode(address(currency), 1 ether));
            fetchedData = stepwiseCollectModule.getPublicationData(publisherProfileId, secondPubId);
            assertEq(fetchedData.currentCollects, collects);
        }
        vm.stopPrank();
    }
}

contract StepwiseCollectModule_Mirror is StepwiseCollectModuleBase, StepwiseCollectModule_Collect {
    uint256 immutable userTwoProfileId;
    uint256 origPubId;

    constructor() StepwiseCollectModule_Collect() {
        vm.recordLogs();
        hub.createProfile(
            DataTypes.CreateProfileData({
                to: userTwo,
                handle: 'usertwo.lens',
                imageURI: OTHER_MOCK_URI,
                followModule: address(0),
                followModuleInitData: '',
                followNFTURI: MOCK_FOLLOW_NFT_URI
            })
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        userTwoProfileId = TestHelpers.getCreatedProfileIdFromEvents(entries);
    }

    function setUp() public override {
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

        vm.recordLogs();
        vm.prank(userTwo);
        hub.post(
            DataTypes.PostData({
                profileId: userTwoProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(exampleInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        origPubId = TestHelpers.getCreatedPubIdFromEvents(entries);

        vm.recordLogs();
        vm.prank(publisher);
        hub.mirror(
            DataTypes.MirrorData({
                profileId: publisherProfileId,
                profileIdPointed: userTwoProfileId,
                pubIdPointed: origPubId,
                referenceModule: address(0),
                referenceModuleInitData: '',
                referenceModuleData: ''
            })
        );
        entries = vm.getRecordedLogs();
        pubId = TestHelpers.getCreatedMirrorIdFromEvents(entries);

        currency.mint(user, type(uint256).max);
        vm.prank(user);
        currency.approve(address(stepwiseCollectModule), type(uint256).max);
    }

    function hubPost(StepwiseCollectModuleInitData memory initData)
        public
        override
        returns (uint256)
    {
        vm.recordLogs();
        vm.prank(userTwo);
        hub.post(
            DataTypes.PostData({
                profileId: userTwoProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(exampleInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        origPubId = TestHelpers.getCreatedPubIdFromEvents(entries);

        vm.recordLogs();
        vm.prank(publisher);
        hub.mirror(
            DataTypes.MirrorData({
                profileId: publisherProfileId,
                profileIdPointed: userTwoProfileId,
                pubIdPointed: origPubId,
                referenceModule: address(0),
                referenceModuleInitData: '',
                referenceModuleData: ''
            })
        );
        entries = vm.getRecordedLogs();
        return TestHelpers.getCreatedMirrorIdFromEvents(entries);
    }

    function testCurrentCollectsIncreaseProperlyWhenCollecting() public override {
        uint256 secondPubId = hubPost(exampleInitData);
        vm.startPrank(user);

        ProfilePublicationData memory fetchedData = stepwiseCollectModule.getPublicationData(
            userTwoProfileId,
            origPubId
        );
        assertEq(fetchedData.currentCollects, 0);

        for (uint256 collects = 1; collects < 5; collects++) {
            hub.collect(publisherProfileId, secondPubId, abi.encode(address(currency), 1 ether));
            fetchedData = stepwiseCollectModule.getPublicationData(userTwoProfileId, origPubId);
            assertEq(fetchedData.currentCollects, collects);
        }
        vm.stopPrank();
    }
}

contract StepwiseCollectModule_FeeDistribution is StepwiseCollectModuleBase {
    struct Balances {
        uint256 treasury;
        uint256 referral;
        uint256 publisher;
        uint256 user;
    }

    uint16 internal constant BPS_MAX = 10000;

    uint256 immutable publisherProfileId;
    uint256 immutable userProfileId;
    uint256 immutable mirrorerProfileId;

    StepwiseCollectModuleInitData exampleInitData;

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
        publisherProfileId = TestHelpers.getCreatedProfileIdFromEvents(entries);

        vm.recordLogs();
        hub.createProfile(
            DataTypes.CreateProfileData({
                to: user,
                handle: 'user.lens',
                imageURI: OTHER_MOCK_URI,
                followModule: address(0),
                followModuleInitData: '',
                followNFTURI: MOCK_FOLLOW_NFT_URI
            })
        );
        entries = vm.getRecordedLogs();
        userProfileId = TestHelpers.getCreatedProfileIdFromEvents(entries);

        vm.recordLogs();
        hub.createProfile(
            DataTypes.CreateProfileData({
                to: userTwo,
                handle: 'usertwo.lens',
                imageURI: OTHER_MOCK_URI,
                followModule: address(0),
                followModuleInitData: '',
                followNFTURI: MOCK_FOLLOW_NFT_URI
            })
        );
        entries = vm.getRecordedLogs();
        mirrorerProfileId = TestHelpers.getCreatedProfileIdFromEvents(entries);
    }

    function setUp() public virtual {
        exampleInitData = StepwiseCollectModuleInitData({
            collectLimit: 0,
            currency: address(currency),
            recipient: address(publisher),
            referralFee: 0,
            followerOnly: false,
            endTimestamp: 0,
            a: 0,
            b: 0,
            c: 1 ether
        });

        currency.mint(user, type(uint256).max);
        vm.prank(user);
        currency.approve(address(stepwiseCollectModule), type(uint256).max);
    }

    function hubPostAndMirror(
        StepwiseCollectModuleInitData memory initData,
        uint16 referralFee,
        uint128 amount
    ) public returns (uint256, uint256) {
        exampleInitData.referralFee = referralFee;
        exampleInitData.c = amount;
        vm.recordLogs();
        vm.prank(publisher);
        hub.post(
            DataTypes.PostData({
                profileId: publisherProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(exampleInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 pubId = TestHelpers.getCreatedPubIdFromEvents(entries);

        vm.recordLogs();
        vm.prank(userTwo);
        hub.mirror(
            DataTypes.MirrorData({
                profileId: mirrorerProfileId,
                profileIdPointed: publisherProfileId,
                pubIdPointed: pubId,
                referenceModule: address(0),
                referenceModuleInitData: '',
                referenceModuleData: ''
            })
        );
        entries = vm.getRecordedLogs();
        uint256 mirrorId = TestHelpers.getCreatedMirrorIdFromEvents(entries);
        return (pubId, mirrorId);
    }

    function verifyFeesWithoutMirror(uint16 treasuryFee, uint128 amount) public {
        vm.prank(governance);
        moduleGlobals.setTreasuryFee(treasuryFee);
        (uint256 pubId, ) = hubPostAndMirror(exampleInitData, 0, amount);

        Balances memory balancesBefore;
        Balances memory balancesAfter;
        Balances memory balancesChange;

        balancesBefore.treasury = currency.balanceOf(treasury);
        balancesBefore.publisher = currency.balanceOf(publisher);
        balancesBefore.user = currency.balanceOf(user);

        vm.prank(user);
        vm.recordLogs();
        hub.collect(publisherProfileId, pubId, abi.encode(address(currency), amount));
        Vm.Log[] memory entries = vm.getRecordedLogs();

        balancesAfter.treasury = currency.balanceOf(treasury);
        balancesAfter.publisher = currency.balanceOf(publisher);
        balancesAfter.user = currency.balanceOf(user);

        balancesChange.treasury = balancesAfter.treasury - balancesBefore.treasury;
        balancesChange.publisher = balancesAfter.publisher - balancesBefore.publisher;
        balancesChange.user = balancesBefore.user - balancesAfter.user;

        assertEq(balancesChange.treasury + balancesChange.publisher, balancesChange.user);

        uint256 treasuryAmount = (uint256(amount) * treasuryFee) / BPS_MAX;
        uint256 adjustedAmount = amount - treasuryAmount;

        assertEq(balancesChange.treasury, treasuryAmount);
        assertEq(balancesChange.publisher, adjustedAmount);
        assertEq(balancesChange.user, amount);

        if (amount == 0 || adjustedAmount == 0) {
            vm.expectRevert('No Transfer event found');
            TestHelpers.getTransferFromEvents(entries, user, publisher);
            assertEq(balancesChange.treasury, 0);
            assertEq(balancesChange.publisher, 0);
            assertEq(balancesChange.user, 0);
        } else {
            uint256 ownerFeeTransferEventAmount = TestHelpers.getTransferFromEvents(
                entries,
                user,
                publisher
            );
            assertEq(ownerFeeTransferEventAmount, adjustedAmount);
        }
        if (treasuryFee == 0 || treasuryAmount == 0) {
            vm.expectRevert('No Transfer event found');
            TestHelpers.getTransferFromEvents(entries, user, treasury);
            assertEq(balancesChange.treasury, 0);
        } else {
            uint256 treasuryTransferEventAmount = TestHelpers.getTransferFromEvents(
                entries,
                user,
                treasury
            );
            assertEq(treasuryTransferEventAmount, treasuryAmount);
        }
    }

    function verifyFeesWithMirror(
        uint16 treasuryFee,
        uint16 referralFee,
        uint128 amount
    ) public {
        vm.prank(governance);
        moduleGlobals.setTreasuryFee(treasuryFee);
        (uint256 pubId, uint256 mirrorId) = hubPostAndMirror(exampleInitData, referralFee, amount);

        Vm.Log[] memory entries;

        Balances memory balancesBefore;
        Balances memory balancesAfter;
        Balances memory balancesChange;

        balancesBefore.treasury = currency.balanceOf(treasury);
        balancesBefore.referral = currency.balanceOf(userTwo);
        balancesBefore.publisher = currency.balanceOf(publisher);
        balancesBefore.user = currency.balanceOf(user);

        vm.recordLogs();
        vm.prank(user);
        hub.collect(mirrorerProfileId, mirrorId, abi.encode(address(currency), amount));
        entries = vm.getRecordedLogs();

        balancesAfter.treasury = currency.balanceOf(treasury);
        balancesAfter.referral = currency.balanceOf(userTwo);
        balancesAfter.publisher = currency.balanceOf(publisher);
        balancesAfter.user = currency.balanceOf(user);

        balancesChange.treasury = balancesAfter.treasury - balancesBefore.treasury;
        balancesChange.referral = balancesAfter.referral - balancesBefore.referral;
        balancesChange.publisher = balancesAfter.publisher - balancesBefore.publisher;
        balancesChange.user = balancesBefore.user - balancesAfter.user;

        assertEq(
            balancesChange.treasury + balancesChange.referral + balancesChange.publisher,
            balancesChange.user
        );

        uint256 treasuryAmount = (uint256(amount) * treasuryFee) / BPS_MAX;
        uint256 adjustedAmount = uint256(amount) - treasuryAmount;
        uint256 referralAmount = (adjustedAmount * referralFee) / BPS_MAX;

        if (referralFee != 0) adjustedAmount = adjustedAmount - referralAmount;

        assertEq(balancesChange.treasury, treasuryAmount);
        assertEq(balancesChange.referral, referralAmount);
        assertEq(balancesChange.publisher, adjustedAmount);
        assertEq(balancesChange.user, amount);

        if (amount == 0 || adjustedAmount == 0) {
            vm.expectRevert('No Transfer event found');
            TestHelpers.getTransferFromEvents(entries, user, publisher);
            assertEq(balancesChange.treasury, 0);
            assertEq(balancesChange.referral, 0);
            assertEq(balancesChange.publisher, 0);
            assertEq(balancesChange.user, 0);
        } else {
            uint256 ownerFeeTransferEventAmount = TestHelpers.getTransferFromEvents(
                entries,
                user,
                publisher
            );
            assertEq(ownerFeeTransferEventAmount, adjustedAmount);
        }

        if (treasuryFee == 0 || treasuryAmount == 0) {
            vm.expectRevert('No Transfer event found');
            TestHelpers.getTransferFromEvents(entries, user, treasury);
            assertEq(balancesChange.treasury, 0);
        } else {
            uint256 treasuryTransferEventAmount = TestHelpers.getTransferFromEvents(
                entries,
                user,
                treasury
            );
            assertEq(treasuryTransferEventAmount, treasuryAmount);
        }

        if (referralFee == 0 || referralAmount == 0) {
            vm.expectRevert('No Transfer event found');
            TestHelpers.getTransferFromEvents(entries, user, userTwo);
            assertEq(balancesChange.referral, referralAmount);
        } else {
            uint256 referralTransferEventAmount = TestHelpers.getTransferFromEvents(
                entries,
                user,
                userTwo
            );
            assertEq(referralTransferEventAmount, referralAmount);
        }
    }

    function testFeesDistributionEdgeCasesWithoutMirror() public {
        verifyFeesWithoutMirror(0, 0);
        verifyFeesWithoutMirror(0, 1 ether);
        verifyFeesWithoutMirror(0, type(uint128).max);
        verifyFeesWithoutMirror(BPS_MAX / 2 - 1, 0);
        verifyFeesWithoutMirror(BPS_MAX / 2 - 1, 1 ether);
        verifyFeesWithoutMirror(BPS_MAX / 2 - 1, type(uint128).max);
    }

    function testFeesDistributionWithoutMirrorFuzzing(uint16 treasuryFee, uint128 amount) public {
        vm.assume(treasuryFee < BPS_MAX / 2 - 1);
        verifyFeesWithoutMirror(treasuryFee, amount);
    }

    function testFeesDistributionEdgeCasesWithMirror() public {
        verifyFeesWithMirror(0, 0, 0);
        verifyFeesWithMirror(0, 0, type(uint128).max);
        verifyFeesWithMirror(0, BPS_MAX / 2 - 1, 0);
        verifyFeesWithMirror(0, BPS_MAX / 2 - 1, type(uint128).max);
        verifyFeesWithMirror(BPS_MAX / 2 - 1, 0, 0);
        verifyFeesWithMirror(BPS_MAX / 2 - 1, 0, type(uint128).max);
        verifyFeesWithMirror(BPS_MAX / 2 - 1, BPS_MAX / 2 - 1, 0);
        verifyFeesWithMirror(BPS_MAX / 2 - 1, BPS_MAX / 2 - 1, type(uint128).max);
        verifyFeesWithMirror(0, 0, 1);
        verifyFeesWithMirror(0, 1, 0);
        verifyFeesWithMirror(0, 1, 1);
        verifyFeesWithMirror(1, 0, 1);
        verifyFeesWithMirror(1, 1, 0);
        verifyFeesWithMirror(1, 1, 1);
    }

    function testFeesDistributionWithMirrorFuzzing(
        uint16 treasuryFee,
        uint16 referralFee,
        uint128 amount
    ) public {
        vm.assume(treasuryFee < BPS_MAX / 2 - 1);
        vm.assume(referralFee < BPS_MAX / 2 - 1);
        verifyFeesWithMirror(treasuryFee, referralFee, amount);
    }
}
