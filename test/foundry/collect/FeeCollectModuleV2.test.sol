// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import '../BaseSetup.t.sol';
import {FeeCollectModuleV2Base} from './FeeCollectModuleV2.base.sol';
import '../helpers/TestHelpers.sol';
import {ProfilePublicationData, FeeCollectModuleV2InitData, RecipientData, FeeCollectModuleV2} from 'contracts/collect/FeeCollectModuleV2.sol';
import '@aave/lens-protocol/contracts/libraries/Events.sol';

uint16 constant BPS_MAX = 10000;

/////////
// Publication Creation with FeeCollectModuleV2
//
contract FeeCollectModuleV2_Publication is FeeCollectModuleV2Base {
    uint256 immutable userProfileId;

    uint256 internal constant MAX_RECIPIENTS = 5;

    FeeCollectModuleV2InitData exampleInitData;

    constructor() FeeCollectModuleV2Base() {
        userProfileId = hub.createProfile(
            DataTypes.CreateProfileData({
                to: me,
                handle: 'user.lens',
                imageURI: OTHER_MOCK_URI,
                followModule: address(0),
                followModuleInitData: '',
                followNFTURI: MOCK_FOLLOW_NFT_URI
            })
        );
    }

    function setUp() public {
        exampleInitData.amount = 1 ether;
        exampleInitData.collectLimit = 0;
        exampleInitData.currency = address(currency);
        exampleInitData.referralFee = 0;
        exampleInitData.followerOnly = false;
        exampleInitData.endTimestamp = 0;
        exampleInitData.recipients.push(RecipientData({recipient: me, split: BPS_MAX}));
    }

    function hubPostWithRevert(bytes4 expectedError) public {
        vm.expectRevert(expectedError);
        hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: address(feeCollectModuleV2),
                collectModuleInitData: abi.encode(exampleInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
    }

    // Negatives
    function testCannotPostWithNonWhitelistedCurrency() public {
        exampleInitData.currency = address(0);
        hubPostWithRevert(Errors.InitParamsInvalid.selector);
    }

    function testCannotPostWithoutRecipients() public {
        delete exampleInitData.recipients;
        hubPostWithRevert(Errors.InitParamsInvalid.selector);
    }

    function testCannotPostWithZeroAddressRecipient() public {
        exampleInitData.recipients[0] = RecipientData({recipient: address(0), split: BPS_MAX});
        hubPostWithRevert(Errors.InitParamsInvalid.selector);
    }

    function testCannotPostWithOneOfRecipientsAddressIsZero() public {
        delete exampleInitData.recipients;
        exampleInitData.recipients.push(RecipientData({recipient: me, split: BPS_MAX / 4}));
        exampleInitData.recipients.push(RecipientData({recipient: me, split: BPS_MAX / 4}));
        exampleInitData.recipients.push(RecipientData({recipient: address(0), split: BPS_MAX / 4}));
        exampleInitData.recipients.push(RecipientData({recipient: me, split: BPS_MAX / 4}));
        hubPostWithRevert(Errors.InitParamsInvalid.selector);
    }

    function testCannotPostWithMoreThanMaxRecipients() public {
        delete exampleInitData.recipients;
        assertEq(exampleInitData.recipients.length, 0);
        uint16 splitUsed;
        for (uint256 i = 0; i < MAX_RECIPIENTS; i++) {
            exampleInitData.recipients.push(RecipientData({recipient: me, split: 1000}));
            splitUsed += 1000;
        }
        exampleInitData.recipients.push(RecipientData({recipient: me, split: BPS_MAX - splitUsed}));
        assert(exampleInitData.recipients.length > MAX_RECIPIENTS);
        hubPostWithRevert(FeeCollectModuleV2.TooManyRecipients.selector);
    }

    function testCannotPostWithRecipientSplitsSumNotEqualToBPS_MAX() public {
        delete exampleInitData.recipients;
        assertEq(exampleInitData.recipients.length, 0);
        uint16 splitUsed;
        for (uint256 i = 0; i < MAX_RECIPIENTS; i++) {
            exampleInitData.recipients.push(RecipientData({recipient: me, split: 1000}));
            splitUsed += 1000;
        }
        assert(splitUsed != BPS_MAX);
        hubPostWithRevert(FeeCollectModuleV2.InvalidRecipientSplits.selector);
    }

    function testCannotPostWithOneRecipientAndSplitNotEqualToBPS_MAX() public {
        delete exampleInitData.recipients;
        exampleInitData.recipients.push(RecipientData({recipient: me, split: 9000}));
        hubPostWithRevert(FeeCollectModuleV2.InvalidRecipientSplits.selector);
    }

    function testCannotPostWithZeroRecipientSplit() public {
        delete exampleInitData.recipients;
        assertEq(exampleInitData.recipients.length, 0);
        uint16 splitUsed;
        for (uint256 i = 0; i < MAX_RECIPIENTS; i++) {
            if (i != 3) {
                exampleInitData.recipients.push(RecipientData({recipient: me, split: 2500}));
                splitUsed += 2500;
            } else {
                exampleInitData.recipients.push(RecipientData({recipient: me, split: 0}));
            }
        }
        assert(splitUsed == BPS_MAX);
        hubPostWithRevert(FeeCollectModuleV2.RecipientSplitCannotBeZero.selector);
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
        feeCollectModuleV2.initializePublicationCollectModule(
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
                collectModule: address(feeCollectModuleV2),
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
                collectModule: address(feeCollectModuleV2),
                collectModuleInitData: abi.encode(exampleInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
    }

    function testCreatePublicationEmitsExpectedEvents() public {
        uint256 pubId = hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: address(feeCollectModuleV2),
                collectModuleInitData: abi.encode(exampleInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
        assertEq(pubId, 1);
    }

    function testFuzzCreatePublicationWithDifferentInitData(
        uint160 amount,
        uint96 collectLimit,
        uint16 referralFee,
        bool followerOnly,
        uint72 endTimestamp,
        uint8 recipientsNumber
    ) public {
        vm.assume(referralFee <= TREASURY_FEE_MAX_BPS);
        vm.assume(endTimestamp > block.timestamp || endTimestamp == 0);
        vm.assume(recipientsNumber > 0 && recipientsNumber <= 5);

        RecipientData[] memory recipients = new RecipientData[](recipientsNumber);
        uint16 sum;
        for (uint16 i = 0; i < recipientsNumber; i++) {
            uint16 split = BPS_MAX / recipientsNumber;
            sum += split;
            if (i == recipientsNumber - 1 && sum != BPS_MAX) split += BPS_MAX - sum;
            recipients[i] = RecipientData({recipient: me, split: split});
        }

        FeeCollectModuleV2InitData memory fuzzyInitData = FeeCollectModuleV2InitData({
            amount: amount,
            collectLimit: collectLimit,
            currency: address(currency),
            referralFee: referralFee,
            followerOnly: followerOnly,
            endTimestamp: endTimestamp,
            recipients: recipients
        });

        hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: address(feeCollectModuleV2),
                collectModuleInitData: abi.encode(fuzzyInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
    }

    function testFuzzFetchedPublicationDataShouldBeAccurate(
        uint160 amount,
        uint96 collectLimit,
        uint16 referralFee,
        bool followerOnly,
        uint72 endTimestamp,
        uint8 recipientsNumber
    ) public {
        vm.assume(referralFee <= TREASURY_FEE_MAX_BPS);
        vm.assume(endTimestamp > block.timestamp);
        vm.assume(recipientsNumber > 0 && recipientsNumber <= 5);

        RecipientData[] memory recipients = new RecipientData[](recipientsNumber);
        uint16 sum;
        for (uint16 i = 0; i < recipientsNumber; i++) {
            uint16 split = BPS_MAX / recipientsNumber;
            sum += split;
            if (i == recipientsNumber - 1 && sum != BPS_MAX) split += BPS_MAX - sum;
            recipients[i] = RecipientData({recipient: me, split: split});
        }

        FeeCollectModuleV2InitData memory fuzzyInitData = FeeCollectModuleV2InitData({
            amount: amount,
            collectLimit: collectLimit,
            currency: address(currency),
            referralFee: referralFee,
            followerOnly: followerOnly,
            endTimestamp: endTimestamp,
            recipients: recipients
        });

        uint256 pubId = hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: address(feeCollectModuleV2),
                collectModuleInitData: abi.encode(fuzzyInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
        assert(pubId > 0);
        ProfilePublicationData memory fetchedData = feeCollectModuleV2.getPublicationData(
            userProfileId,
            pubId
        );
        assertEq(fetchedData.currency, fuzzyInitData.currency);
        assertEq(fetchedData.amount, fuzzyInitData.amount);
        assertEq(fetchedData.referralFee, fuzzyInitData.referralFee);
        assertEq(fetchedData.followerOnly, fuzzyInitData.followerOnly);
        assertEq(fetchedData.endTimestamp, fuzzyInitData.endTimestamp);
        assertEq(fetchedData.collectLimit, fuzzyInitData.collectLimit);
        for (uint256 i = 0; i < recipientsNumber; i++) {
            assertEq(fetchedData.recipients[i].recipient, fuzzyInitData.recipients[i].recipient);
            assertEq(fetchedData.recipients[i].split, fuzzyInitData.recipients[i].split);
        }
    }
}

//////////////
// Collect with FeeCollectModuleV2

contract FeeCollectModuleV2_Collect is FeeCollectModuleV2Base {
    uint256 immutable publisherProfileId;
    uint256 immutable userProfileId;

    uint256 pubId;

    FeeCollectModuleV2InitData exampleInitData;

    constructor() FeeCollectModuleV2Base() {
        publisherProfileId = hub.createProfile(
            DataTypes.CreateProfileData({
                to: publisher,
                handle: 'publisher.lens',
                imageURI: OTHER_MOCK_URI,
                followModule: address(0),
                followModuleInitData: '',
                followNFTURI: MOCK_FOLLOW_NFT_URI
            })
        );

        userProfileId = hub.createProfile(
            DataTypes.CreateProfileData({
                to: user,
                handle: 'user.lens',
                imageURI: OTHER_MOCK_URI,
                followModule: address(0),
                followModuleInitData: '',
                followNFTURI: MOCK_FOLLOW_NFT_URI
            })
        );
    }

    function setUp() public virtual {
        exampleInitData.amount = 1 ether;
        exampleInitData.collectLimit = 0;
        exampleInitData.currency = address(currency);
        exampleInitData.referralFee = 0;
        exampleInitData.followerOnly = false;
        exampleInitData.endTimestamp = 0;
        exampleInitData.recipients.push(RecipientData({recipient: me, split: BPS_MAX}));

        vm.prank(publisher);
        pubId = hub.post(
            DataTypes.PostData({
                profileId: publisherProfileId,
                contentURI: MOCK_URI,
                collectModule: address(feeCollectModuleV2),
                collectModuleInitData: abi.encode(exampleInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );

        currency.mint(user, type(uint256).max);
        vm.prank(user);
        currency.approve(address(feeCollectModuleV2), type(uint256).max);
    }

    // Negatives

    function testCannotCollectIfCalledFromNonHubAddress() public {
        vm.expectRevert(Errors.NotHub.selector);
        feeCollectModuleV2.processCollect(
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
        currency.approve(address(feeCollectModuleV2), 0);
        assert(currency.allowance(user, address(feeCollectModuleV2)) < 1 ether);
        vm.expectRevert('ERC20: insufficient allowance');
        hub.collect(publisherProfileId, pubId, abi.encode(address(currency), 1 ether));
        vm.stopPrank();
    }

    function testCannotCollectWithoutEnoughBalance() public {
        vm.startPrank(user);
        currency.transfer(address(1), currency.balanceOf(user));
        assertEq(currency.balanceOf(user), 0);
        assert(currency.allowance(user, address(feeCollectModuleV2)) >= 1 ether);
        vm.expectRevert('ERC20: transfer amount exceeds balance');
        hub.collect(publisherProfileId, pubId, abi.encode(address(currency), 1 ether));
        vm.stopPrank();
    }

    function hubPost(FeeCollectModuleV2InitData memory initData) public virtual returns (uint256) {
        vm.prank(publisher);
        uint256 newPubId = hub.post(
            DataTypes.PostData({
                profileId: publisherProfileId,
                contentURI: MOCK_URI,
                collectModule: address(feeCollectModuleV2),
                collectModuleInitData: abi.encode(initData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
        return newPubId;
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

        ProfilePublicationData memory fetchedData = feeCollectModuleV2.getPublicationData(
            publisherProfileId,
            secondPubId
        );
        assertEq(fetchedData.currentCollects, 0);

        for (uint256 collects = 1; collects < 5; collects++) {
            hub.collect(publisherProfileId, secondPubId, abi.encode(address(currency), 1 ether));
            fetchedData = feeCollectModuleV2.getPublicationData(publisherProfileId, secondPubId);
            assertEq(fetchedData.currentCollects, collects);
        }
        vm.stopPrank();
    }
}

contract FeeCollectModuleV2_Mirror is FeeCollectModuleV2Base, FeeCollectModuleV2_Collect {
    uint256 immutable userTwoProfileId;
    uint256 origPubId;

    constructor() FeeCollectModuleV2_Collect() {
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
        exampleInitData.amount = 1 ether;
        exampleInitData.collectLimit = 0;
        exampleInitData.currency = address(currency);
        exampleInitData.referralFee = 0;
        exampleInitData.followerOnly = false;
        exampleInitData.endTimestamp = 0;
        exampleInitData.recipients.push(RecipientData({recipient: me, split: BPS_MAX}));

        vm.prank(userTwo);
        origPubId = hub.post(
            DataTypes.PostData({
                profileId: userTwoProfileId,
                contentURI: MOCK_URI,
                collectModule: address(feeCollectModuleV2),
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
        currency.approve(address(feeCollectModuleV2), type(uint256).max);
    }

    function hubPost(FeeCollectModuleV2InitData memory initData) public override returns (uint256) {
        vm.prank(userTwo);
        origPubId = hub.post(
            DataTypes.PostData({
                profileId: userTwoProfileId,
                contentURI: MOCK_URI,
                collectModule: address(feeCollectModuleV2),
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

        ProfilePublicationData memory fetchedData = feeCollectModuleV2.getPublicationData(
            userTwoProfileId,
            origPubId
        );
        assertEq(fetchedData.currentCollects, 0);

        for (uint256 collects = 1; collects < 5; collects++) {
            hub.collect(publisherProfileId, secondPubId, abi.encode(address(currency), 1 ether));
            fetchedData = feeCollectModuleV2.getPublicationData(userTwoProfileId, origPubId);
            assertEq(fetchedData.currentCollects, collects);
        }
        vm.stopPrank();
    }
}

contract FeeCollectModuleV2_FeeDistribution is FeeCollectModuleV2Base {
    struct Balances {
        uint256 treasury;
        uint256 referral;
        uint256 publisher;
        uint256 user;
        uint256 userTwo;
        uint256 userThree;
        uint256 userFour;
        uint256 userFive;
    }

    uint256 immutable publisherProfileId;
    uint256 immutable userProfileId;
    uint256 immutable mirrorerProfileId;

    FeeCollectModuleV2InitData exampleInitData;

    constructor() FeeCollectModuleV2Base() {
        publisherProfileId = hub.createProfile(
            DataTypes.CreateProfileData({
                to: publisher,
                handle: 'publisher.lens',
                imageURI: OTHER_MOCK_URI,
                followModule: address(0),
                followModuleInitData: '',
                followNFTURI: MOCK_FOLLOW_NFT_URI
            })
        );

        userProfileId = hub.createProfile(
            DataTypes.CreateProfileData({
                to: user,
                handle: 'user.lens',
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
        exampleInitData.amount = 1 ether;
        exampleInitData.collectLimit = 0;
        exampleInitData.currency = address(currency);
        exampleInitData.referralFee = 0;
        exampleInitData.followerOnly = false;
        exampleInitData.endTimestamp = 0;
        exampleInitData.recipients.push(RecipientData({recipient: publisher, split: BPS_MAX}));

        currency.mint(user, type(uint256).max);
        vm.prank(user);
        currency.approve(address(feeCollectModuleV2), type(uint256).max);
    }

    function hubPostAndMirror(
        FeeCollectModuleV2InitData memory initData,
        uint16 referralFee,
        uint128 amount
    ) public returns (uint256, uint256) {
        exampleInitData.referralFee = referralFee;
        exampleInitData.amount = amount;
        vm.prank(publisher);
        uint256 pubId = hub.post(
            DataTypes.PostData({
                profileId: publisherProfileId,
                contentURI: MOCK_URI,
                collectModule: address(feeCollectModuleV2),
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

    function testFeeSplitEquallyWithFiveRecipients(uint128 totalCollectFee) public {
        uint256 treasuryAmount = (uint256(totalCollectFee) * TREASURY_FEE_BPS) / BPS_MAX;
        uint256 adjustedAmount = totalCollectFee - treasuryAmount;

        uint16 splitPerUser = BPS_MAX / 5;
        uint256 expectedUserFeeCut = adjustedAmount / 5;

        Balances memory balancesBefore;
        Balances memory balancesAfter;

        // Set users in initData to publisher, u2, u3, u4, userFive with equal split of fee
        exampleInitData.recipients[0] = RecipientData({recipient: publisher, split: splitPerUser});
        exampleInitData.recipients.push(RecipientData({recipient: userTwo, split: splitPerUser}));
        exampleInitData.recipients.push(RecipientData({recipient: userThree, split: splitPerUser}));
        exampleInitData.recipients.push(RecipientData({recipient: userFour, split: splitPerUser}));
        exampleInitData.recipients.push(RecipientData({recipient: userFive, split: splitPerUser}));

        (uint256 pubId, ) = hubPostAndMirror(exampleInitData, 0, totalCollectFee);

        balancesBefore.treasury = currency.balanceOf(treasury);
        balancesBefore.publisher = currency.balanceOf(publisher);
        balancesBefore.userTwo = currency.balanceOf(userTwo);
        balancesBefore.userThree = currency.balanceOf(userThree);
        balancesBefore.userFour = currency.balanceOf(userFour);
        balancesBefore.userFive = currency.balanceOf(userFive);

        vm.prank(user);
        hub.collect(publisherProfileId, pubId, abi.encode(address(currency), totalCollectFee));

        balancesAfter.treasury = currency.balanceOf(treasury);
        balancesAfter.publisher = currency.balanceOf(publisher);
        balancesAfter.userTwo = currency.balanceOf(userTwo);
        balancesAfter.userThree = currency.balanceOf(userThree);
        balancesAfter.userFour = currency.balanceOf(userFour);
        balancesAfter.userFive = currency.balanceOf(userFive);

        assertEq(balancesAfter.treasury - balancesBefore.treasury, treasuryAmount);
        assertEq(balancesAfter.publisher - balancesBefore.publisher, expectedUserFeeCut);
        assertEq(balancesAfter.userTwo - balancesBefore.userTwo, expectedUserFeeCut);
        assertEq(balancesAfter.userThree - balancesBefore.userThree, expectedUserFeeCut);
        assertEq(balancesAfter.userFour - balancesBefore.userFour, expectedUserFeeCut);
        assertEq(balancesAfter.userFive - balancesBefore.userFive, expectedUserFeeCut);
    }

    function testFuzzedSplitCutsWithFiveRecipients(
        uint128 totalCollectFee,
        uint16 userTwoSplit,
        uint16 extraSplit
    ) public {
        vm.assume(userTwoSplit < BPS_MAX / 2 && userTwoSplit != 0);
        vm.assume(extraSplit < BPS_MAX / 2 && extraSplit > 1);

        uint256 treasuryAmount = (uint256(totalCollectFee) * TREASURY_FEE_BPS) / BPS_MAX;

        // Some fuzzy randomness in the splits
        uint16 publisherSplit = (BPS_MAX / 2) - userTwoSplit;
        uint16 userThreeSplit = (BPS_MAX / 2) - extraSplit;
        uint16 userFourSplit = extraSplit / 2;
        uint16 userFiveSplit = extraSplit - userFourSplit;

        assertEq(
            publisherSplit + userTwoSplit + userThreeSplit + userFourSplit + userFiveSplit,
            BPS_MAX
        );

        Balances memory balancesBefore;
        Balances memory balancesAfter;

        // Set users in initData to five recipients with fuzzed splits
        exampleInitData.recipients[0] = RecipientData({
            recipient: publisher,
            split: publisherSplit
        });
        exampleInitData.recipients.push(RecipientData({recipient: userTwo, split: userTwoSplit}));
        exampleInitData.recipients.push(
            RecipientData({recipient: userThree, split: userThreeSplit})
        );
        exampleInitData.recipients.push(RecipientData({recipient: userFour, split: userFourSplit}));
        exampleInitData.recipients.push(RecipientData({recipient: userFive, split: userFiveSplit}));

        (uint256 pubId, ) = hubPostAndMirror(exampleInitData, 0, totalCollectFee);

        balancesBefore.treasury = currency.balanceOf(treasury);
        balancesBefore.publisher = currency.balanceOf(publisher);
        balancesBefore.userTwo = currency.balanceOf(userTwo);
        balancesBefore.userThree = currency.balanceOf(userThree);
        balancesBefore.userFour = currency.balanceOf(userFour);
        balancesBefore.userFive = currency.balanceOf(userFive);

        vm.prank(user);
        hub.collect(publisherProfileId, pubId, abi.encode(address(currency), totalCollectFee));

        balancesAfter.treasury = currency.balanceOf(treasury);
        balancesAfter.publisher = currency.balanceOf(publisher);
        balancesAfter.userTwo = currency.balanceOf(userTwo);
        balancesAfter.userThree = currency.balanceOf(userThree);
        balancesAfter.userFour = currency.balanceOf(userFour);
        balancesAfter.userFive = currency.balanceOf(userFive);

        assertEq(balancesAfter.treasury - balancesBefore.treasury, treasuryAmount);
        assertEq(
            balancesAfter.publisher - balancesBefore.publisher,
            predictCutAmount(totalCollectFee - treasuryAmount, publisherSplit)
        );
        assertEq(
            balancesAfter.userTwo - balancesBefore.userTwo,
            predictCutAmount(totalCollectFee - treasuryAmount, userTwoSplit)
        );
        assertEq(
            balancesAfter.userThree - balancesBefore.userThree,
            predictCutAmount(totalCollectFee - treasuryAmount, userThreeSplit)
        );
        assertEq(
            balancesAfter.userFour - balancesBefore.userFour,
            predictCutAmount(totalCollectFee - treasuryAmount, userFourSplit)
        );
        assertEq(
            balancesAfter.userFive - balancesBefore.userFive,
            predictCutAmount(totalCollectFee - treasuryAmount, userFiveSplit)
        );
    }

    function predictCutAmount(uint256 totalAfterTreasuryCut, uint16 cutBPS)
        internal
        view
        returns (uint256)
    {
        return (totalAfterTreasuryCut * cutBPS) / BPS_MAX;
    }
}
