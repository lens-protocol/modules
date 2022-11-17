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
        userProfileId = hub.createProfile(
            DataTypes.CreateProfileData({
                to: me,
                handle: 'user',
                imageURI: OTHER_MOCK_URI,
                followModule: address(0),
                followModuleInitData: '',
                followNFTURI: MOCK_FOLLOW_NFT_URI
            })
        );
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
        uint256 pubId = hub.post(
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
        uint256 eventPubId = TestHelpers.getCreatedPubIdFromEvents(entries);
        assertEq(pubId, eventPubId);
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
        referralFee = uint16(bound(referralFee, 0, TREASURY_FEE_MAX_BPS));
        endTimestamp = uint40(bound(endTimestamp, block.timestamp + 1, type(uint40).max));

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
        referralFee = uint16(bound(referralFee, 0, TREASURY_FEE_MAX_BPS));
        endTimestamp = uint40(bound(endTimestamp, block.timestamp + 1, type(uint40).max));

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

        uint256 pubId = hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(fuzzyInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
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
//
contract StepwiseCollectModule_Collect is StepwiseCollectModuleBase {
    uint256 immutable publisherProfileId;
    uint256 immutable userProfileId;

    uint256 pubId;

    StepwiseCollectModuleInitData exampleInitData;

    constructor() StepwiseCollectModuleBase() {
        publisherProfileId = hub.createProfile(
            DataTypes.CreateProfileData({
                to: publisher,
                handle: 'pub',
                imageURI: OTHER_MOCK_URI,
                followModule: address(0),
                followModuleInitData: '',
                followNFTURI: MOCK_FOLLOW_NFT_URI
            })
        );

        userProfileId = hub.createProfile(
            DataTypes.CreateProfileData({
                to: user,
                handle: 'user',
                imageURI: OTHER_MOCK_URI,
                followModule: address(0),
                followModuleInitData: '',
                followNFTURI: MOCK_FOLLOW_NFT_URI
            })
        );
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

        vm.prank(publisher);
        pubId = hub.post(
            DataTypes.PostData({
                profileId: publisherProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(exampleInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );

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
        vm.prank(publisher);
        uint256 pubId = hub.post(
            DataTypes.PostData({
                profileId: publisherProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(initData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
        return pubId;
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
        exampleInitData.endTimestamp = uint40(block.timestamp) + 100;
        uint256 secondPubId = hubPost(exampleInitData);

        vm.warp(exampleInitData.endTimestamp + 1);

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

/////////////
// Collect with StepwiseCollectModule from a Mirror
//
contract StepwiseCollectModule_Mirror is StepwiseCollectModuleBase, StepwiseCollectModule_Collect {
    uint256 immutable userTwoProfileId;
    uint256 origPubId;

    constructor() StepwiseCollectModule_Collect() {
        userTwoProfileId = hub.createProfile(
            DataTypes.CreateProfileData({
                to: userTwo,
                handle: 'usertwo.lens',
                imageURI: OTHER_MOCK_URI,
                followModule: address(0),
                followModuleInitData: '',
                followNFTURI: MOCK_FOLLOW_NFT_URI
            })
        );
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

        vm.prank(userTwo);
        origPubId = hub.post(
            DataTypes.PostData({
                profileId: userTwoProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(exampleInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );

        vm.prank(publisher);
        pubId = hub.mirror(
            DataTypes.MirrorData({
                profileId: publisherProfileId,
                profileIdPointed: userTwoProfileId,
                pubIdPointed: origPubId,
                referenceModule: address(0),
                referenceModuleInitData: '',
                referenceModuleData: ''
            })
        );

        currency.mint(user, type(uint256).max);
        vm.prank(user);
        currency.approve(address(stepwiseCollectModule), type(uint256).max);
    }

    function hubPost(StepwiseCollectModuleInitData memory initData)
        public
        override
        returns (uint256)
    {
        vm.prank(userTwo);
        origPubId = hub.post(
            DataTypes.PostData({
                profileId: userTwoProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(exampleInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );

        vm.prank(publisher);
        uint256 mirrorId = hub.mirror(
            DataTypes.MirrorData({
                profileId: publisherProfileId,
                profileIdPointed: userTwoProfileId,
                pubIdPointed: origPubId,
                referenceModule: address(0),
                referenceModuleInitData: '',
                referenceModuleData: ''
            })
        );
        return mirrorId;
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

/////////////
// Fee Distribution
//
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
        publisherProfileId = hub.createProfile(
            DataTypes.CreateProfileData({
                to: publisher,
                handle: 'pub',
                imageURI: OTHER_MOCK_URI,
                followModule: address(0),
                followModuleInitData: '',
                followNFTURI: MOCK_FOLLOW_NFT_URI
            })
        );

        userProfileId = hub.createProfile(
            DataTypes.CreateProfileData({
                to: user,
                handle: 'user',
                imageURI: OTHER_MOCK_URI,
                followModule: address(0),
                followModuleInitData: '',
                followNFTURI: MOCK_FOLLOW_NFT_URI
            })
        );

        mirrorerProfileId = hub.createProfile(
            DataTypes.CreateProfileData({
                to: userTwo,
                handle: 'usertwo.lens',
                imageURI: OTHER_MOCK_URI,
                followModule: address(0),
                followModuleInitData: '',
                followNFTURI: MOCK_FOLLOW_NFT_URI
            })
        );
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
        vm.prank(publisher);
        uint256 pubId = hub.post(
            DataTypes.PostData({
                profileId: publisherProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(exampleInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );

        vm.prank(userTwo);
        uint256 mirrorId = hub.mirror(
            DataTypes.MirrorData({
                profileId: mirrorerProfileId,
                profileIdPointed: publisherProfileId,
                pubIdPointed: pubId,
                referenceModule: address(0),
                referenceModuleInitData: '',
                referenceModuleData: ''
            })
        );
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
        treasuryFee = uint16(bound(treasuryFee, 0, BPS_MAX / 2 - 2));

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
        treasuryFee = uint16(bound(treasuryFee, 0, BPS_MAX / 2 - 2));
        referralFee = uint16(bound(referralFee, 0, BPS_MAX / 2 - 2));
        verifyFeesWithMirror(treasuryFee, referralFee, amount);
    }
}

/////////////
// Quadratic formula calculation
//
library Calculations {
    function expectedStepwiseAmount(
        StepwiseCollectModule stepwiseCollectModule,
        uint256 a,
        uint256 b,
        uint256 c,
        uint256 currentCollects
    ) internal returns (uint256) {
        return
            ((uint256(a) * (uint256(currentCollects) * uint256(currentCollects))) /
                stepwiseCollectModule.A_DECIMALS()) +
            ((uint256(b) * uint256(currentCollects)) / stepwiseCollectModule.B_DECIMALS()) +
            uint256(c);
    }
}

/////////////
// Stepwise curve formula
//
contract StepwiseCollectModule_StepwiseCurveFormula is StepwiseCollectModuleBase {
    uint256 immutable publisherProfileId;
    uint256 immutable userProfileId;

    StepwiseCollectModuleInitData exampleInitData;

    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor() StepwiseCollectModuleBase() {
        publisherProfileId = hub.createProfile(
            DataTypes.CreateProfileData({
                to: publisher,
                handle: 'pub',
                imageURI: OTHER_MOCK_URI,
                followModule: address(0),
                followModuleInitData: '',
                followNFTURI: MOCK_FOLLOW_NFT_URI
            })
        );

        userProfileId = hub.createProfile(
            DataTypes.CreateProfileData({
                to: user,
                handle: 'user',
                imageURI: OTHER_MOCK_URI,
                followModule: address(0),
                followModuleInitData: '',
                followNFTURI: MOCK_FOLLOW_NFT_URI
            })
        );

        vm.prank(governance);
        moduleGlobals.setTreasuryFee(0);
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

    function testStepwiseCollectConstant() public {
        exampleInitData.a = 0;
        exampleInitData.b = 0;
        exampleInitData.c = 1;

        vm.prank(publisher);
        uint256 pubId = hub.post(
            DataTypes.PostData({
                profileId: publisherProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(exampleInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );

        for (uint256 i = 0; i < 10; i++) {
            uint256 expectedAmount = 1;
            assertEq(stepwiseCollectModule.previewFee(publisherProfileId, pubId), expectedAmount);
            vm.prank(user);
            vm.expectEmit(true, true, true, true, address(currency));
            emit Transfer(user, publisher, expectedAmount);
            hub.collect(publisherProfileId, pubId, abi.encode(address(currency), expectedAmount));
        }
    }

    function testStepwiseCollectLinear() public {
        exampleInitData.a = 0;
        exampleInitData.b = uint56(2 * stepwiseCollectModule.B_DECIMALS());
        exampleInitData.c = 2;

        vm.prank(publisher);
        uint256 pubId = hub.post(
            DataTypes.PostData({
                profileId: publisherProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(exampleInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );

        console.log('Linear increase test (2, 4, 6, ...):');
        for (uint256 i = 0; i < 10; i++) {
            uint256 expectedAmount = 2 + 2 * i;
            assertEq(stepwiseCollectModule.previewFee(publisherProfileId, pubId), expectedAmount);
            vm.prank(user);
            vm.expectEmit(true, true, true, true, address(currency));
            emit Transfer(user, publisher, expectedAmount);
            hub.collect(publisherProfileId, pubId, abi.encode(address(currency), expectedAmount));
            console.log('  ', expectedAmount);
        }
    }

    function testStepwiseCollectSquared() public {
        exampleInitData.a = uint72(stepwiseCollectModule.A_DECIMALS());
        exampleInitData.b = 0;
        exampleInitData.c = 0;

        vm.prank(publisher);
        uint256 pubId = hub.post(
            DataTypes.PostData({
                profileId: publisherProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(exampleInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );

        console.log('Squared curve test (0, 1, 4, 9, ...):');
        for (uint256 i = 0; i < 10; i++) {
            uint256 expectedAmount = i * i;
            assertEq(stepwiseCollectModule.previewFee(publisherProfileId, pubId), expectedAmount);
            vm.prank(user);
            if (expectedAmount != 0) {
                vm.expectEmit(true, false, false, false);
                emit Transfer(user, publisher, expectedAmount);
            }
            hub.collect(publisherProfileId, pubId, abi.encode(address(currency), expectedAmount));
            console.log('  ', expectedAmount);
        }
    }

    function testStepwiseCollectFuzz(
        uint72 a,
        uint56 b,
        uint128 c,
        uint64 numberOfCollects
    ) public {
        console.log('Testing %s collects:', numberOfCollects);
        numberOfCollects = uint64(bound(numberOfCollects, 1, 99));

        exampleInitData.a = a;
        exampleInitData.b = b;
        exampleInitData.c = c;

        vm.prank(publisher);
        uint256 pubId = hub.post(
            DataTypes.PostData({
                profileId: publisherProfileId,
                contentURI: MOCK_URI,
                collectModule: address(stepwiseCollectModule),
                collectModuleInitData: abi.encode(exampleInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );

        for (uint256 i = 0; i < numberOfCollects; i++) {
            uint256 currentCollects = stepwiseCollectModule
                .getPublicationData(publisherProfileId, pubId)
                .currentCollects;
            assertEq(currentCollects, i, 'Number of collects doesnt match');
            uint256 expectedAmount = Calculations.expectedStepwiseAmount(
                stepwiseCollectModule,
                a,
                b,
                c,
                currentCollects
            );
            assertEq(stepwiseCollectModule.previewFee(publisherProfileId, pubId), expectedAmount);
            console.log('  ', expectedAmount);
            vm.prank(user);
            if (expectedAmount > 0) vm.expectEmit(true, true, true, true, address(currency));
            emit Transfer(user, publisher, expectedAmount);
            hub.collect(publisherProfileId, pubId, abi.encode(address(currency), expectedAmount));
        }
    }
}

/////////////
// CalculateFee function
//
contract StepwiseCollectModule_StepwiseCalculateFeeInternal is StepwiseCollectModule, Test {
    constructor() StepwiseCollectModule(address(1), address(2)) {}

    function testCalculateFeeMax() public {
        ProfilePublicationData memory testData;
        testData.a = type(uint72).max;
        testData.b = type(uint56).max;
        testData.c = type(uint128).max;
        testData.currentCollects = type(uint64).max;

        uint256 amount = StepwiseCollectModule._calculateFee(testData);

        uint256 expectedAmount = Calculations.expectedStepwiseAmount(
            this,
            testData.a,
            testData.b,
            testData.c,
            testData.currentCollects - 1
        );

        assertEq(amount, expectedAmount);
    }

    function testCalculateFeeFuzz(
        uint72 a,
        uint56 b,
        uint128 c,
        uint64 currentCollects
    ) public {
        currentCollects = uint64(bound(currentCollects, 1, type(uint64).max));
        ProfilePublicationData memory testData;
        testData.a = a;
        testData.b = b;
        testData.c = c;
        testData.currentCollects = currentCollects;

        uint256 amount = StepwiseCollectModule._calculateFee(testData);

        uint256 expectedAmount = Calculations.expectedStepwiseAmount(
            this,
            a,
            b,
            c,
            currentCollects - 1
        );

        assertEq(amount, expectedAmount);
    }
}
