// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {Errors} from '@aave/lens-protocol/contracts/libraries/Errors.sol';
import {BaseFeeCollectModule} from './BaseFeeCollectModule.sol';
import {ProfilePublicationData, CollectModuleInitData} from './BaseFeeCollectDataStructures.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

struct RecipientData {
    address recipient;
    uint16 split; // fraction of BPS_MAX (10 000)
}

/**
 * @notice A struct containing the necessary data to initialize FeeCollect Module V2.
 *
 * @param amount The collecting cost associated with this publication. 0 for free collect.
 * @param collectLimit The maximum number of collects for this publication. 0 for no limit.
 * @param currency The currency associated with this publication.
 * @param referralFee The referral fee associated with this publication.
 * @param followerOnly True if only followers of publisher may collect the post.
 * @param endTimestamp The end timestamp after which collecting is impossible. 0 for no expiry.
 * @param recipients Array of RecipientData items to split collect fees across multiple recipients.
 */
struct FeeCollectModuleV2InitData {
    uint160 amount;
    uint96 collectLimit;
    address currency;
    uint16 referralFee;
    bool followerOnly;
    uint72 endTimestamp;
    RecipientData[] recipients;
}

/**
 * @notice A struct containing the necessary data to execute collect actions on a publication.
 *
 * @param amount The collecting cost associated with this publication. 0 for free collect.
 * @param collectLimit The maximum number of collects for this publication. 0 for no limit.
 * @param currency The currency associated with this publication.
 * @param currentCollects The current number of collects for this publication.
 * @param referralFee The referral fee associated with this publication.
 * @param followerOnly True if only followers of publisher may collect the post.
 * @param endTimestamp The end timestamp after which collecting is impossible. 0 for no expiry.
 * @param recipients Array of RecipientData items to split collect fees across multiple recipients.
 */
struct FeeCollectV2ProfilePublicationData {
    uint160 amount;
    uint96 collectLimit;
    address currency;
    uint96 currentCollects;
    uint16 referralFee;
    bool followerOnly;
    uint72 endTimestamp;
    RecipientData[] recipients;
}

contract FeeCollectModuleV2 is BaseFeeCollectModule {
    using SafeERC20 for IERC20;

    uint256 internal constant MAX_RECIPIENTS = 5;

    mapping(uint256 => mapping(uint256 => RecipientData[]))
        internal _recipientsByPublicationByProfile;

    error TooManyRecipients();
    error InvalidRecipientSplits();
    error RecipientSplitCannotBeZero();

    constructor(address hub, address moduleGlobals) BaseFeeCollectModule(hub, moduleGlobals) {}

    function _validateInitData(
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) internal override {
        super._validateInitData(profileId, pubId, data);
        FeeCollectModuleV2InitData memory initData = abi.decode(data, (FeeCollectModuleV2InitData));
        _validateAndStoreRecipients(initData.recipients, profileId, pubId);
    }

    function _decodeStandardInitParameters(bytes calldata data)
        internal
        pure
        override
        returns (CollectModuleInitData memory)
    {
        FeeCollectModuleV2InitData memory initData = abi.decode(data, (FeeCollectModuleV2InitData));
        return
            CollectModuleInitData({
                amount: initData.amount,
                collectLimit: initData.collectLimit,
                currency: initData.currency,
                referralFee: initData.referralFee,
                followerOnly: initData.followerOnly,
                endTimestamp: initData.endTimestamp,
                recipient: address(0)
            });
    }

    function _validateAndStoreRecipients(
        RecipientData[] memory recipients,
        uint256 profileId,
        uint256 pubId
    ) internal {
        (uint256 i, uint256 len) = (0, recipients.length);

        // Check number of recipients is supported
        if (len > MAX_RECIPIENTS) revert TooManyRecipients();
        if (len == 0) revert Errors.InitParamsInvalid();

        // Skip loop check if only 1 recipient in the array
        if (len == 1) {
            if (recipients[0].recipient == address(0)) revert Errors.InitParamsInvalid();
            if (recipients[0].split != BPS_MAX) revert InvalidRecipientSplits();

            // If single recipient passes check above, store and return
            _recipientsByPublicationByProfile[profileId][pubId].push(recipients[0]);
        } else {
            // Check recipient splits sum to 10 000 BPS (100%)
            uint256 totalSplits;
            for (i; i < len; ) {
                if (recipients[i].recipient == address(0)) revert Errors.InitParamsInvalid();
                if (recipients[i].split == 0) revert RecipientSplitCannotBeZero();
                totalSplits += recipients[i].split;

                // Store each recipient while looping - avoids extra gas costs in successful cases
                _recipientsByPublicationByProfile[profileId][pubId].push(recipients[i]);

                unchecked {
                    ++i;
                }
            }

            if (totalSplits != BPS_MAX) revert InvalidRecipientSplits();
        }
    }

    function _transferToRecipients(
        address currency,
        address collector,
        uint256 profileId,
        uint256 pubId,
        uint256 amount
    ) internal override {
        RecipientData[] memory recipients = _recipientsByPublicationByProfile[profileId][pubId];
        (uint256 i, uint256 len) = (0, recipients.length);

        // If only 1 recipient, transfer full amount and skip split calculations
        if (len == 1 && amount != 0) {
            IERC20(currency).safeTransferFrom(collector, recipients[0].recipient, amount);
        } else {
            uint256 splitAmount;
            for (i; i < len; ) {
                splitAmount = (amount * recipients[i].split) / BPS_MAX;
                if (splitAmount != 0)
                    IERC20(currency).safeTransferFrom(
                        collector,
                        recipients[i].recipient,
                        splitAmount
                    );

                unchecked {
                    ++i;
                }
            }
        }
    }

    /**
     * @notice Returns the publication data for a given publication, or an empty struct if that publication was not
     * initialized with this module.
     *
     * @param profileId The token ID of the profile mapped to the publication to query.
     * @param pubId The publication ID of the publication to query.
     *
     * @return The ProfilePublicationData struct mapped to that publication.
     */
    function getFullPublicationData(uint256 profileId, uint256 pubId)
        external
        view
        returns (FeeCollectV2ProfilePublicationData memory)
    {
        ProfilePublicationData memory standardData = _dataByPublicationByProfile[profileId][pubId];
        RecipientData[] memory recipients = _recipientsByPublicationByProfile[profileId][pubId];

        return
            FeeCollectV2ProfilePublicationData({
                amount: standardData.amount,
                collectLimit: standardData.collectLimit,
                currency: standardData.currency,
                currentCollects: standardData.currentCollects,
                referralFee: standardData.referralFee,
                followerOnly: standardData.followerOnly,
                endTimestamp: standardData.endTimestamp,
                recipients: recipients
            });
    }
}
