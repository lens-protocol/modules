// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {Errors} from '@aave/lens-protocol/contracts/libraries/Errors.sol';
import {BaseCollectModule} from './base/BaseCollectModule.sol';
import {BaseProfilePublicationData, BaseCollectModuleInitData} from './base/IBaseCollectModule.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {ICollectModule} from '@aave/lens-protocol/contracts/interfaces/ICollectModule.sol';

struct RecipientData {
    address recipient;
    uint16 split; // fraction of BPS_MAX (10 000)
}

/**
 * @notice A struct containing the necessary data to initialize MultirecipientFeeCollectModule.
 *
 * @param amount The collecting cost associated with this publication. 0 for free collect.
 * @param collectLimit The maximum number of collects for this publication. 0 for no limit.
 * @param currency The currency associated with this publication.
 * @param referralFee The referral fee associated with this publication.
 * @param followerOnly True if only followers of publisher may collect the post.
 * @param endTimestamp The end timestamp after which collecting is impossible. 0 for no expiry.
 * @param recipients Array of RecipientData items to split collect fees across multiple recipients.
 */
struct MultirecipientFeeCollectModuleInitData {
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
struct MultirecipientFeeCollectProfilePublicationData {
    uint160 amount;
    uint96 collectLimit;
    address currency;
    uint96 currentCollects;
    uint16 referralFee;
    bool followerOnly;
    uint72 endTimestamp;
    RecipientData[] recipients;
}

error TooManyRecipients();
error InvalidRecipientSplits();
error RecipientSplitCannotBeZero();

/**
 * @title MultirecipientCollectModule
 * @author Lens Protocol
 *
 * @notice This is a simple Lens CollectModule implementation, allowing customization of time to collect, number of collects,
 * splitting collect fee across multiple recipients, and whether only followers can collect.
 * It is charging a fee for collect (if enabled) and distributing it among Receivers/Referral/Treasury.
 */
contract MultirecipientFeeCollectModule is BaseCollectModule {
    using SafeERC20 for IERC20;

    uint256 internal constant MAX_RECIPIENTS = 5;

    mapping(uint256 => mapping(uint256 => RecipientData[]))
        internal _recipientsByPublicationByProfile;

    constructor(address hub, address moduleGlobals) BaseCollectModule(hub, moduleGlobals) {}

    /**
     * @inheritdoc ICollectModule
     */
    function initializePublicationCollectModule(
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) external override onlyHub returns (bytes memory) {
        MultirecipientFeeCollectModuleInitData memory initData = abi.decode(
            data,
            (MultirecipientFeeCollectModuleInitData)
        );

        BaseCollectModuleInitData memory baseInitData = BaseCollectModuleInitData({
            amount: initData.amount,
            collectLimit: initData.collectLimit,
            currency: initData.currency,
            referralFee: initData.referralFee,
            followerOnly: initData.followerOnly,
            endTimestamp: initData.endTimestamp,
            recipient: address(0)
        });

        _validateBaseInitData(baseInitData);
        _validateAndStoreRecipients(initData.recipients, profileId, pubId);
        _storeBasePublicationCollectParameters(profileId, pubId, baseInitData);
        return data;
    }

    /**
     * @dev Validates the recipients array and stores them to (a separate from Base) storage.
     *
     * @param recipients An array of recipients
     * @param profileId The profile ID who is publishing the publication.
     * @param pubId The associated publication's LensHub publication ID.
     */
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

    /**
     * @dev Transfers the fee to multiple recipients.
     *
     * @inheritdoc BaseCollectModule
     */
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
     * @return The BaseProfilePublicationData struct mapped to that publication.
     */
    function getPublicationData(uint256 profileId, uint256 pubId)
        external
        view
        returns (MultirecipientFeeCollectProfilePublicationData memory)
    {
        BaseProfilePublicationData memory baseData = getBasePublicationData(profileId, pubId);
        RecipientData[] memory recipients = _recipientsByPublicationByProfile[profileId][pubId];

        return
            MultirecipientFeeCollectProfilePublicationData({
                amount: baseData.amount,
                collectLimit: baseData.collectLimit,
                currency: baseData.currency,
                currentCollects: baseData.currentCollects,
                referralFee: baseData.referralFee,
                followerOnly: baseData.followerOnly,
                endTimestamp: baseData.endTimestamp,
                recipients: recipients
            });
    }
}
