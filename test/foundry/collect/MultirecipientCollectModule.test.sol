// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import '../BaseSetup.t.sol';
import {MultirecipientCollectModuleBase} from './MultirecipientCollectModule.base.sol';
import '../helpers/TestHelpers.sol';
import {RecipientSplitCannotBeZero, TooManyRecipients, InvalidRecipientSplits, MultirecipientFeeCollectProfilePublicationData, MultirecipientFeeCollectModuleInitData, RecipientData, MultirecipientFeeCollectModule} from 'contracts/collect/MultirecipientFeeCollectModule.sol';
import '@aave/lens-protocol/contracts/libraries/Events.sol';
import {BaseFeeCollectModule_Publication, BaseFeeCollectModule_Collect, BaseFeeCollectModule_Mirror, BaseFeeCollectModule_FeeDistribution} from './BaseFeeCollectModule.test.sol';
import {BaseFeeCollectModuleBase} from './BaseFeeCollectModule.base.sol';

/////////
// Publication Creation with InheritedFeeCollectModule
//
contract MultirecipientCollectModule_Publication is
    MultirecipientCollectModuleBase,
    BaseFeeCollectModule_Publication
{
    constructor() {}

    function getEncodedInitData()
        internal
        override(MultirecipientCollectModuleBase, BaseFeeCollectModuleBase)
        returns (bytes memory)
    {
        return MultirecipientCollectModuleBase.getEncodedInitData();
    }

    function testCannotPostWithZeroAmount() public {
        exampleInitData.amount = 0;
        hubPostWithRevert(Errors.InitParamsInvalid.selector);
    }

    function testCannotPostWithoutRecipients() public {
        delete multirecipientExampleInitData.recipients;
        vm.expectRevert(Errors.InitParamsInvalid.selector);
        hub.post(
            DataTypes.PostData({
                profileId: userProfileId,
                contentURI: MOCK_URI,
                collectModule: address(baseFeeCollectModule),
                collectModuleInitData: abi.encode(multirecipientExampleInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
    }

    function testCannotPostWithZeroAddressRecipient() public {
        multirecipientExampleInitData.recipients.push(
            RecipientData({recipient: address(0), split: BPS_MAX})
        );
        hubPostWithRevert(Errors.InitParamsInvalid.selector);
    }

    function testCannotPostWithOneOfRecipientsAddressIsZero() public {
        delete multirecipientExampleInitData.recipients;
        multirecipientExampleInitData.recipients.push(
            RecipientData({recipient: me, split: BPS_MAX / 4})
        );
        multirecipientExampleInitData.recipients.push(
            RecipientData({recipient: me, split: BPS_MAX / 4})
        );
        multirecipientExampleInitData.recipients.push(
            RecipientData({recipient: address(0), split: BPS_MAX / 4})
        );
        multirecipientExampleInitData.recipients.push(
            RecipientData({recipient: me, split: BPS_MAX / 4})
        );
        hubPostWithRevert(Errors.InitParamsInvalid.selector);
    }

    function testCannotPostWithMoreThanMaxRecipients() public {
        delete multirecipientExampleInitData.recipients;
        assertEq(multirecipientExampleInitData.recipients.length, 0);
        uint16 splitUsed;
        for (uint256 i = 0; i < MAX_RECIPIENTS; i++) {
            multirecipientExampleInitData.recipients.push(
                RecipientData({recipient: me, split: 1000})
            );
            splitUsed += 1000;
        }
        multirecipientExampleInitData.recipients.push(
            RecipientData({recipient: me, split: BPS_MAX - splitUsed})
        );
        assert(multirecipientExampleInitData.recipients.length > MAX_RECIPIENTS);
        hubPostWithRevert(TooManyRecipients.selector);
    }

    function testCannotPostWithRecipientSplitsSumNotEqualToBPS_MAX() public {
        delete multirecipientExampleInitData.recipients;
        assertEq(multirecipientExampleInitData.recipients.length, 0);
        uint16 splitUsed;
        for (uint256 i = 0; i < MAX_RECIPIENTS; i++) {
            multirecipientExampleInitData.recipients.push(
                RecipientData({recipient: me, split: 1000})
            );
            splitUsed += 1000;
        }
        assert(splitUsed != BPS_MAX);
        hubPostWithRevert(InvalidRecipientSplits.selector);
    }

    function testCannotPostWithOneRecipientAndSplitNotEqualToBPS_MAX() public {
        delete multirecipientExampleInitData.recipients;
        multirecipientExampleInitData.recipients.push(RecipientData({recipient: me, split: 9000}));
        hubPostWithRevert(InvalidRecipientSplits.selector);
    }

    function testCannotPostWithZeroRecipientSplit() public {
        delete multirecipientExampleInitData.recipients;
        assertEq(multirecipientExampleInitData.recipients.length, 0);
        uint16 splitUsed;
        for (uint256 i = 0; i < MAX_RECIPIENTS; i++) {
            if (i != 3) {
                multirecipientExampleInitData.recipients.push(
                    RecipientData({recipient: me, split: 2500})
                );
                splitUsed += 2500;
            } else {
                multirecipientExampleInitData.recipients.push(
                    RecipientData({recipient: me, split: 0})
                );
            }
        }
        assert(splitUsed == BPS_MAX);
        hubPostWithRevert(RecipientSplitCannotBeZero.selector);
    }

    function testFuzzFetchedPublicationDataShouldBeAccurate(
        uint160 amount,
        uint96 collectLimit,
        uint16 referralFee,
        bool followerOnly,
        uint72 endTimestamp
    ) public override {}

    function testFuzzFetchedPublicationDataShouldBeAccurate(
        uint160 amount,
        uint96 collectLimit,
        uint16 referralFee,
        bool followerOnly,
        uint72 endTimestamp,
        uint8 recipientsNumber
    ) public {
        vm.assume(amount != 0);
        referralFee = uint16(bound(referralFee, 0, TREASURY_FEE_MAX_BPS));
        endTimestamp = uint72(bound(endTimestamp, block.timestamp + 1, type(uint72).max));
        recipientsNumber = uint8(bound(recipientsNumber, 1, 5));

        RecipientData[] memory recipients = new RecipientData[](recipientsNumber);
        uint16 sum;
        for (uint16 i = 0; i < recipientsNumber; i++) {
            uint16 split = BPS_MAX / recipientsNumber;
            sum += split;
            if (i == recipientsNumber - 1 && sum != BPS_MAX) split += BPS_MAX - sum;
            recipients[i] = RecipientData({recipient: me, split: split});
        }

        MultirecipientFeeCollectModuleInitData
            memory fuzzyInitData = MultirecipientFeeCollectModuleInitData({
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
                collectModule: address(multirecipientFeeCollectModule),
                collectModuleInitData: abi.encode(fuzzyInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
        assert(pubId > 0);
        MultirecipientFeeCollectProfilePublicationData
            memory fetchedData = multirecipientFeeCollectModule.getPublicationData(
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

    function testFuzzCreatePublicationWithDifferentInitData(
        uint160 amount,
        uint96 collectLimit,
        uint16 referralFee,
        bool followerOnly,
        uint72 endTimestamp
    ) public override {}

    function testFuzzCreatePublicationWithDifferentInitData(
        uint160 amount,
        uint96 collectLimit,
        uint16 referralFee,
        bool followerOnly,
        uint72 endTimestamp,
        uint8 recipientsNumber
    ) public {
        vm.assume(amount != 0);
        referralFee = uint16(bound(referralFee, 0, TREASURY_FEE_MAX_BPS));
        vm.assume(endTimestamp > block.timestamp || endTimestamp == 0);
        recipientsNumber = uint8(bound(recipientsNumber, 1, 5));

        RecipientData[] memory recipients = new RecipientData[](recipientsNumber);
        uint16 sum;
        for (uint16 i = 0; i < recipientsNumber; i++) {
            uint16 split = BPS_MAX / recipientsNumber;
            sum += split;
            if (i == recipientsNumber - 1 && sum != BPS_MAX) split += BPS_MAX - sum;
            recipients[i] = RecipientData({recipient: me, split: split});
        }

        MultirecipientFeeCollectModuleInitData
            memory fuzzyInitData = MultirecipientFeeCollectModuleInitData({
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
                collectModule: address(multirecipientFeeCollectModule),
                collectModuleInitData: abi.encode(fuzzyInitData),
                referenceModule: address(0),
                referenceModuleInitData: ''
            })
        );
    }
}

//////////////
// Collect with InheritedFeeCollectModule
//
contract MultirecipientCollectModule_Collect is
    MultirecipientCollectModuleBase,
    BaseFeeCollectModule_Collect
{
    constructor() {}

    function getEncodedInitData()
        internal
        override(MultirecipientCollectModuleBase, BaseFeeCollectModuleBase)
        returns (bytes memory)
    {
        return MultirecipientCollectModuleBase.getEncodedInitData();
    }
}

//////////////
// Collect on Mirror with InheritedFeeCollectModule
//
contract MultirecipientCollectModule_Mirror is
    MultirecipientCollectModuleBase,
    BaseFeeCollectModule_Mirror
{
    constructor() {}

    function getEncodedInitData()
        internal
        override(MultirecipientCollectModuleBase, BaseFeeCollectModuleBase)
        returns (bytes memory)
    {
        return MultirecipientCollectModuleBase.getEncodedInitData();
    }
}

//////////////
// Fee Distribution of InheritedFeeCollectModule
//
contract MultirecipientCollectModule_FeeDistribution is
    MultirecipientCollectModuleBase,
    BaseFeeCollectModule_FeeDistribution
{
    constructor() {}

    struct InheritedBalances {
        uint256 treasury;
        uint256 referral;
        uint256 publisher;
        uint256 user;
        uint256 userTwo;
        uint256 userThree;
        uint256 userFour;
        uint256 userFive;
    }

    function getEncodedInitData()
        internal
        override(MultirecipientCollectModuleBase, BaseFeeCollectModuleBase)
        returns (bytes memory)
    {
        return MultirecipientCollectModuleBase.getEncodedInitData();
    }

    function testFeeSplitEquallyWithFiveRecipients(uint128 totalCollectFee) public {
        vm.assume(totalCollectFee != 0);
        uint256 treasuryAmount = (uint256(totalCollectFee) * TREASURY_FEE_BPS) / BPS_MAX;
        uint256 adjustedAmount = totalCollectFee - treasuryAmount;

        uint16 splitPerUser = BPS_MAX / 5;
        uint256 expectedUserFeeCut = adjustedAmount / 5;

        InheritedBalances memory balancesBefore;
        InheritedBalances memory balancesAfter;

        // Set users in initData to publisher, u2, u3, u4, userFive with equal split of fee
        delete multirecipientExampleInitData.recipients;
        multirecipientExampleInitData.recipients.push(
            RecipientData({recipient: publisher, split: splitPerUser})
        );
        multirecipientExampleInitData.recipients.push(
            RecipientData({recipient: userTwo, split: splitPerUser})
        );
        multirecipientExampleInitData.recipients.push(
            RecipientData({recipient: userThree, split: splitPerUser})
        );
        multirecipientExampleInitData.recipients.push(
            RecipientData({recipient: userFour, split: splitPerUser})
        );
        multirecipientExampleInitData.recipients.push(
            RecipientData({recipient: userFive, split: splitPerUser})
        );

        (uint256 pubId, ) = hubPostAndMirror(0, totalCollectFee);

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
        vm.assume(totalCollectFee != 0);
        userTwoSplit = uint16(bound(userTwoSplit, 1, BPS_MAX / 2 - 1));
        extraSplit = uint16(bound(extraSplit, 2, BPS_MAX / 2 - 1));

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

        InheritedBalances memory balancesBefore;
        InheritedBalances memory balancesAfter;

        // Set users in initData to five recipients with fuzzed splits
        delete multirecipientExampleInitData.recipients;
        multirecipientExampleInitData.recipients.push(
            RecipientData({recipient: publisher, split: publisherSplit})
        );
        multirecipientExampleInitData.recipients.push(
            RecipientData({recipient: userTwo, split: userTwoSplit})
        );
        multirecipientExampleInitData.recipients.push(
            RecipientData({recipient: userThree, split: userThreeSplit})
        );
        multirecipientExampleInitData.recipients.push(
            RecipientData({recipient: userFour, split: userFourSplit})
        );
        multirecipientExampleInitData.recipients.push(
            RecipientData({recipient: userFive, split: userFiveSplit})
        );

        (uint256 pubId, ) = hubPostAndMirror(0, totalCollectFee);

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

    // Overriding some tests from Base to disable zero amounts:

    function testFeesDistributionWithMirrorFuzzing(
        uint16 treasuryFee,
        uint16 referralFee,
        uint128 amount
    ) public override {
        vm.assume(amount != 0);
        super.testFeesDistributionWithMirrorFuzzing(treasuryFee, referralFee, amount);
    }

    function testFeesDistributionWithoutMirrorFuzzing(uint16 treasuryFee, uint128 amount)
        public
        override
    {
        vm.assume(amount != 0);
        super.testFeesDistributionWithoutMirrorFuzzing(treasuryFee, amount);
    }

    // Using 1 wei instead of zero here in (, amount):
    function testFeesDistributionEdgeCasesWithoutMirror() public override {
        verifyFeesWithoutMirror(0, 1);
        verifyFeesWithoutMirror(0, 1 ether);
        verifyFeesWithoutMirror(0, type(uint128).max);
        verifyFeesWithoutMirror(BPS_MAX / 2 - 1, 1);
        verifyFeesWithoutMirror(BPS_MAX / 2 - 1, 1 ether);
        verifyFeesWithoutMirror(BPS_MAX / 2 - 1, type(uint128).max);
    }

    // Using 1 wei instead of zero here in (, , amount):
    function testFeesDistributionEdgeCasesWithMirror() public override {
        verifyFeesWithMirror(0, 0, type(uint128).max);
        verifyFeesWithMirror(0, BPS_MAX / 2 - 1, 1);
        verifyFeesWithMirror(0, BPS_MAX / 2 - 1, type(uint128).max);
        verifyFeesWithMirror(BPS_MAX / 2 - 1, 0, 1);
        verifyFeesWithMirror(BPS_MAX / 2 - 1, 0, type(uint128).max);
        verifyFeesWithMirror(BPS_MAX / 2 - 1, BPS_MAX / 2 - 1, 1);
        verifyFeesWithMirror(BPS_MAX / 2 - 1, BPS_MAX / 2 - 1, type(uint128).max);
        verifyFeesWithMirror(0, 0, 1);
        verifyFeesWithMirror(0, 1, 1);
        verifyFeesWithMirror(1, 0, 1);
        verifyFeesWithMirror(1, 1, 1);
    }

    function predictCutAmount(uint256 totalAfterTreasuryCut, uint16 cutBPS)
        internal
        pure
        returns (uint256)
    {
        return (totalAfterTreasuryCut * cutBPS) / BPS_MAX;
    }
}
