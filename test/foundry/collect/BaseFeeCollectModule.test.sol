// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import '../BaseSetup.t.sol';
import {BaseFeeCollectModuleBase} from './BaseFeeCollectModule.base.sol';
import {IBaseFeeCollectModule, BaseProfilePublicationData, BaseFeeCollectModuleInitData} from 'contracts/collect/base/IBaseFeeCollectModule.sol';
import {SimpleFeeCollectModule} from 'contracts/collect/SimpleFeeCollectModule.sol';

import '../helpers/TestHelpers.sol';
import '@aave/lens-protocol/contracts/libraries/Events.sol';

uint16 constant BPS_MAX = 10000;

/////////
// Publication Creation with BaseFeeCollectModule
//
contract BaseFeeCollectModule_Publication is BaseFeeCollectModuleBase {
    uint256 immutable userProfileId;

    constructor() BaseFeeCollectModuleBase() {
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
        exampleInitData.amount = 1 ether;
        exampleInitData.collectLimit = 0;
        exampleInitData.currency = address(currency);
        exampleInitData.referralFee = 0;
        exampleInitData.followerOnly = false;
        exampleInitData.endTimestamp = 0;
        exampleInitData.recipient = me;
    }

    function hubPostWithRevert(bytes4 expectedError) public virtual {
        vm.expectRevert(expectedError);
        hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: baseFeeCollectModule,
                collectModuleInitData: getEncodedInitData(),
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

    // We don't test for zero recipient here for two reasons:
    //  1) Allows burning tokens
    //  2) Inherited modules might not use the recipient field and leave it zero
    //
    // function testCannotPostWithZeroAddressRecipient() public {
    //     exampleInitData.recipient = address(0);
    //     hubPostWithRevert(Errors.InitParamsInvalid.selector);
    // }

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
        SimpleFeeCollectModule(baseFeeCollectModule).initializePublicationCollectModule(
            userProfileId,
            1,
            getEncodedInitData()
        );
    }

    function testCannotPostWithWrongInitDataFormat() public {
        vm.expectRevert();
        hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: baseFeeCollectModule,
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
                collectModule: baseFeeCollectModule,
                collectModuleInitData: getEncodedInitData(),
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
                collectModule: baseFeeCollectModule,
                collectModuleInitData: getEncodedInitData(),
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
        uint72 endTimestamp
    ) public virtual {
        referralFee = uint16(bound(referralFee, 0, TREASURY_FEE_MAX_BPS));
        vm.assume(endTimestamp > block.timestamp || endTimestamp == 0);

        BaseFeeCollectModuleInitData memory fuzzyInitData = BaseFeeCollectModuleInitData({
            amount: amount,
            collectLimit: collectLimit,
            currency: address(currency),
            referralFee: referralFee,
            followerOnly: followerOnly,
            endTimestamp: endTimestamp,
            recipient: me
        });

        hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: baseFeeCollectModule,
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
        uint72 endTimestamp
    ) public virtual {
        referralFee = uint16(bound(referralFee, 0, TREASURY_FEE_MAX_BPS));
        endTimestamp = uint72(bound(endTimestamp, block.timestamp + 1, type(uint72).max));

        BaseFeeCollectModuleInitData memory fuzzyInitData = BaseFeeCollectModuleInitData({
            amount: amount,
            collectLimit: collectLimit,
            currency: address(currency),
            referralFee: referralFee,
            followerOnly: followerOnly,
            endTimestamp: endTimestamp,
            recipient: me
        });

        uint256 pubId = hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: baseFeeCollectModule,
                collectModuleInitData: abi.encode(fuzzyInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
        assert(pubId > 0);
        BaseProfilePublicationData memory fetchedData = SimpleFeeCollectModule(baseFeeCollectModule)
            .getPublicationData(userProfileId, pubId);
        assertEq(fetchedData.currency, fuzzyInitData.currency);
        assertEq(fetchedData.amount, fuzzyInitData.amount);
        assertEq(fetchedData.referralFee, fuzzyInitData.referralFee);
        assertEq(fetchedData.followerOnly, fuzzyInitData.followerOnly);
        assertEq(fetchedData.endTimestamp, fuzzyInitData.endTimestamp);
        assertEq(fetchedData.collectLimit, fuzzyInitData.collectLimit);
        assertEq(fetchedData.recipient, fuzzyInitData.recipient);
    }
}

//////////////
// Collect with BaseFeeCollectModule
//
contract BaseFeeCollectModule_Collect is BaseFeeCollectModuleBase {
    uint256 immutable publisherProfileId;
    uint256 immutable userProfileId;

    uint256 pubId;

    constructor() BaseFeeCollectModuleBase() {
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
        exampleInitData.amount = 1 ether;
        exampleInitData.collectLimit = 0;
        exampleInitData.currency = address(currency);
        exampleInitData.referralFee = 0;
        exampleInitData.followerOnly = false;
        exampleInitData.endTimestamp = 0;
        exampleInitData.recipient = me;

        vm.prank(publisher);
        pubId = hub.post(
            DataTypes.PostData({
                profileId: publisherProfileId,
                contentURI: MOCK_URI,
                collectModule: baseFeeCollectModule,
                collectModuleInitData: getEncodedInitData(),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );

        currency.mint(user, type(uint256).max);
        vm.prank(user);
        currency.approve(baseFeeCollectModule, type(uint256).max);
    }

    // Negatives

    function testCannotCollectIfCalledFromNonHubAddress() public {
        vm.expectRevert(Errors.NotHub.selector);
        SimpleFeeCollectModule(baseFeeCollectModule).processCollect(
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
        currency.approve(baseFeeCollectModule, 0);
        assert(currency.allowance(user, baseFeeCollectModule) < 1 ether);
        vm.expectRevert('ERC20: insufficient allowance');
        hub.collect(publisherProfileId, pubId, abi.encode(address(currency), 1 ether));
        vm.stopPrank();
    }

    function testCannotCollectWithoutEnoughBalance() public {
        vm.startPrank(user);
        currency.transfer(address(1), currency.balanceOf(user));
        assertEq(currency.balanceOf(user), 0);
        assert(currency.allowance(user, baseFeeCollectModule) >= 1 ether);
        vm.expectRevert('ERC20: transfer amount exceeds balance');
        hub.collect(publisherProfileId, pubId, abi.encode(address(currency), 1 ether));
        vm.stopPrank();
    }

    function hubPost() public virtual returns (uint256) {
        vm.prank(publisher);
        uint256 newPubId = hub.post(
            DataTypes.PostData({
                profileId: publisherProfileId,
                contentURI: MOCK_URI,
                collectModule: baseFeeCollectModule,
                collectModuleInitData: getEncodedInitData(),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
        return newPubId;
    }

    function testCannotCollectIfNotAFollower() public {
        exampleInitData.followerOnly = true;
        uint256 secondPubId = hubPost();
        vm.startPrank(user);
        vm.expectRevert(Errors.FollowInvalid.selector);
        hub.collect(publisherProfileId, secondPubId, abi.encode(address(currency), 1 ether));
        vm.stopPrank();
    }

    function testCannotCollectAfterEndTimestamp() public {
        exampleInitData.endTimestamp = uint72(block.timestamp) + 100;
        uint256 secondPubId = hubPost();

        vm.warp(exampleInitData.endTimestamp + 1);

        vm.startPrank(user);
        vm.expectRevert(Errors.CollectExpired.selector);
        hub.collect(publisherProfileId, secondPubId, abi.encode(address(currency), 1 ether));
        vm.stopPrank();
    }

    function testCannotCollectMoreThanLimit() public {
        exampleInitData.collectLimit = 3;
        uint256 secondPubId = hubPost();

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
        uint256 secondPubId = hubPost();
        vm.startPrank(user);
        hub.collect(publisherProfileId, secondPubId, abi.encode(address(currency), 1 ether));
        vm.stopPrank();
    }

    function testProperEventsAreEmittedAfterCollect() public {
        uint256 secondPubId = hubPost();
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
        uint256 secondPubId = hubPost();
        vm.startPrank(user);

        BaseProfilePublicationData memory fetchedData = IBaseFeeCollectModule(baseFeeCollectModule)
            .getBasePublicationData(publisherProfileId, secondPubId);
        assertEq(fetchedData.currentCollects, 0);

        for (uint256 collects = 1; collects < 5; collects++) {
            hub.collect(publisherProfileId, secondPubId, abi.encode(address(currency), 1 ether));
            fetchedData = IBaseFeeCollectModule(baseFeeCollectModule).getBasePublicationData(
                publisherProfileId,
                secondPubId
            );
            assertEq(fetchedData.currentCollects, collects);
        }
        vm.stopPrank();
    }
}

contract BaseFeeCollectModule_Mirror is BaseFeeCollectModuleBase, BaseFeeCollectModule_Collect {
    uint256 immutable userTwoProfileId;
    uint256 origPubId;

    constructor() BaseFeeCollectModule_Collect() {
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
        exampleInitData.recipient = me;

        vm.prank(userTwo);
        origPubId = hub.post(
            DataTypes.PostData({
                profileId: userTwoProfileId,
                contentURI: MOCK_URI,
                collectModule: baseFeeCollectModule,
                collectModuleInitData: getEncodedInitData(),
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
        currency.approve(baseFeeCollectModule, type(uint256).max);
    }

    function hubPost() public override returns (uint256) {
        vm.prank(userTwo);
        origPubId = hub.post(
            DataTypes.PostData({
                profileId: userTwoProfileId,
                contentURI: MOCK_URI,
                collectModule: baseFeeCollectModule,
                collectModuleInitData: getEncodedInitData(),
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
        uint256 secondPubId = hubPost();
        vm.startPrank(user);

        BaseProfilePublicationData memory fetchedData = IBaseFeeCollectModule(baseFeeCollectModule)
            .getBasePublicationData(userTwoProfileId, origPubId);
        assertEq(fetchedData.currentCollects, 0);

        for (uint256 collects = 1; collects < 5; collects++) {
            hub.collect(publisherProfileId, secondPubId, abi.encode(address(currency), 1 ether));
            fetchedData = IBaseFeeCollectModule(baseFeeCollectModule).getBasePublicationData(
                userTwoProfileId,
                origPubId
            );
            assertEq(fetchedData.currentCollects, collects);
        }
        vm.stopPrank();
    }
}

contract BaseFeeCollectModule_FeeDistribution is BaseFeeCollectModuleBase {
    struct Balances {
        uint256 treasury;
        uint256 referral;
        uint256 publisher;
        uint256 user;
        uint256 userTwo;
    }

    uint256 immutable publisherProfileId;
    uint256 immutable userProfileId;
    uint256 immutable mirrorerProfileId;

    constructor() BaseFeeCollectModuleBase() {
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
        exampleInitData.amount = 1 ether;
        exampleInitData.collectLimit = 0;
        exampleInitData.currency = address(currency);
        exampleInitData.referralFee = 0;
        exampleInitData.followerOnly = false;
        exampleInitData.endTimestamp = 0;
        exampleInitData.recipient = publisher;

        currency.mint(user, type(uint256).max);
        vm.prank(user);
        currency.approve(baseFeeCollectModule, type(uint256).max);
    }

    function hubPostAndMirror(uint16 referralFee, uint128 amount)
        public
        returns (uint256, uint256)
    {
        exampleInitData.referralFee = referralFee;
        exampleInitData.amount = amount;
        vm.prank(publisher);
        uint256 pubId = hub.post(
            DataTypes.PostData({
                profileId: publisherProfileId,
                contentURI: MOCK_URI,
                collectModule: baseFeeCollectModule,
                collectModuleInitData: getEncodedInitData(),
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
        (uint256 pubId, ) = hubPostAndMirror(0, amount);

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
        (, uint256 mirrorId) = hubPostAndMirror(referralFee, amount);

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

    function testFeesDistributionEdgeCasesWithoutMirror() public virtual {
        verifyFeesWithoutMirror(0, 0);
        verifyFeesWithoutMirror(0, 1 ether);
        verifyFeesWithoutMirror(0, type(uint128).max);
        verifyFeesWithoutMirror(BPS_MAX / 2 - 1, 0);
        verifyFeesWithoutMirror(BPS_MAX / 2 - 1, 1 ether);
        verifyFeesWithoutMirror(BPS_MAX / 2 - 1, type(uint128).max);
    }

    function testFeesDistributionWithoutMirrorFuzzing(uint16 treasuryFee, uint128 amount)
        public
        virtual
    {
        treasuryFee = uint16(bound(treasuryFee, 0, BPS_MAX / 2 - 2));
        verifyFeesWithoutMirror(treasuryFee, amount);
    }

    function testFeesDistributionEdgeCasesWithMirror() public virtual {
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
    ) public virtual {
        treasuryFee = uint16(bound(treasuryFee, 0, BPS_MAX / 2 - 2));
        referralFee = uint16(bound(referralFee, 0, BPS_MAX / 2 - 2));
        verifyFeesWithMirror(treasuryFee, referralFee, amount);
    }
}

/////////
// Publication Creation with BaseFeeCollectModule
//
contract BaseFeeCollectModule_GasReport is BaseFeeCollectModuleBase {
    uint256 immutable userProfileId;

    constructor() BaseFeeCollectModuleBase() {
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

    function testCreatePublicationWithDifferentInitData() public {
        uint96 collectLimit = 10;
        bool followerOnly = false;
        uint72 endTimestamp = uint72(block.timestamp + 100);

        for (uint16 referralFee = 0; referralFee <= BPS_MAX; referralFee++) {
            if (referralFee >= 2) referralFee += BPS_MAX / 4;
            if (referralFee > 9000) referralFee = BPS_MAX;
            for (uint160 amount = 0; amount < type(uint160).max; amount++) {
                if (amount >= 2) amount += 1 ether;
                if (amount >= 2 ether) amount = type(uint160).max - 1;

                exampleInitData.amount = amount;
                exampleInitData.collectLimit = collectLimit;
                exampleInitData.currency = address(currency);
                exampleInitData.referralFee = referralFee;
                exampleInitData.followerOnly = followerOnly;
                exampleInitData.endTimestamp = endTimestamp;
                exampleInitData.recipient = me;

                hub.post(
                    DataTypes.PostData({
                        profileId: userProfileId,
                        contentURI: MOCK_URI,
                        collectModule: baseFeeCollectModule,
                        collectModuleInitData: getEncodedInitData(),
                        referenceModule: address(0),
                        referenceModuleInitData: ''
                    })
                );
            }
        }
    }
}
