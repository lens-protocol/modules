// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.10;

import {Errors} from '@aave/lens-protocol/contracts/libraries/Errors.sol';
import {FeeModuleBase} from '@aave/lens-protocol/contracts/core/modules/FeeModuleBase.sol';
import {ICollectModule} from '@aave/lens-protocol/contracts/interfaces/ICollectModule.sol';
import {ModuleBase} from '@aave/lens-protocol/contracts/core/modules/ModuleBase.sol';
import {FollowValidationModuleBase} from '@aave/lens-protocol/contracts/core/modules/FollowValidationModuleBase.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

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
struct ProfilePublicationData {
    uint160 amount;
    uint96 collectLimit;
    address currency;
    uint96 currentCollects;
    uint16 referralFee;
    bool followerOnly;
    uint72 endTimestamp;
    RecipientData[] recipients;
}

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
 * @title FeeCollectModuleV2
 * @author Lens Protocol
 *
 * @notice This is a simple Lens CollectModule implementation, allowing customization of time to collect, number of collects,
 * splitting collect fee across multiple recipients, and whether only followers can collect.
 *
 */
contract FeeCollectModuleV2 is FeeModuleBase, FollowValidationModuleBase, ICollectModule {
    using SafeERC20 for IERC20;

    uint256 internal constant MAX_RECIPIENTS = 5;

    mapping(uint256 => mapping(uint256 => ProfilePublicationData))
        internal _dataByPublicationByProfile;

    error TooManyRecipients();
    error InvalidRecipientSplits();
    error RecipientSplitCannotBeZero();

    constructor(address hub, address moduleGlobals) ModuleBase(hub) FeeModuleBase(moduleGlobals) {}

    /**
     * @notice This collect module levies a fee on collects and supports referrals. Thus, we need to decode data.
     *
     * @param data The arbitrary data parameter, decoded into:
     *      uint160 amount: The currency total amount to levy.
     *      uint96 collectLimit: The maximum amount of collects.
     *      address currency: The currency address, must be internally whitelisted.
     *      uint16 referralFee: The referral fee to set.
     *      bool followerOnly: Whether only followers should be able to collect.
     *      uint72 endTimestamp: The end timestamp after which collecting is impossible.
     *      RecipientData[] recipients: Array of RecipientData items to split collect fees across multiple recipients.
     *
     * @return An abi encoded bytes parameter, which is the same as the passed data parameter.
     */
    function initializePublicationCollectModule(
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) external override onlyHub returns (bytes memory) {
        FeeCollectModuleV2InitData memory initData = abi.decode(data, (FeeCollectModuleV2InitData));
        if (
            !_currencyWhitelisted(initData.currency) ||
            initData.referralFee > BPS_MAX ||
            (initData.endTimestamp < block.timestamp && initData.endTimestamp > 0)
        ) revert Errors.InitParamsInvalid();

        _dataByPublicationByProfile[profileId][pubId].amount = initData.amount;
        _dataByPublicationByProfile[profileId][pubId].collectLimit = initData.collectLimit;
        _dataByPublicationByProfile[profileId][pubId].currency = initData.currency;
        _dataByPublicationByProfile[profileId][pubId].referralFee = initData.referralFee;
        _dataByPublicationByProfile[profileId][pubId].followerOnly = initData.followerOnly;
        _dataByPublicationByProfile[profileId][pubId].endTimestamp = initData.endTimestamp;

        // Validate recipient array is formed properly
        // and store recipients in mapping.
        // Both operations done in function below to save gas on unnecessary loop
        _validateAndStoreRecipients(initData.recipients, profileId, pubId);

        return data;
    }

    /**
     * @dev Processes a collect by:
     *  1. Ensuring the collector is a follower if followerOnly mode == true
     *  2. Ensuring the current timestamp is less than or equal to the collect end timestamp
     *  2. Ensuring the collect does not pass the collect limit
     *  3. Charging a fee
     */
    function processCollect(
        uint256 referrerProfileId,
        address collector,
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) external override onlyHub {
        if (_dataByPublicationByProfile[profileId][pubId].followerOnly)
            _checkFollowValidity(profileId, collector);

        uint256 endTimestamp = _dataByPublicationByProfile[profileId][pubId].endTimestamp;
        uint256 collectLimit = _dataByPublicationByProfile[profileId][pubId].collectLimit;
        uint96 currentCollects = _dataByPublicationByProfile[profileId][pubId].currentCollects;

        if (collectLimit != 0 && currentCollects == collectLimit) {
            revert Errors.MintLimitExceeded();
        } else if (block.timestamp > endTimestamp && endTimestamp != 0) {
            revert Errors.CollectExpired();
        } else {
            _dataByPublicationByProfile[profileId][pubId].currentCollects = ++currentCollects;
            if (referrerProfileId == profileId) {
                _processCollect(collector, profileId, pubId, data);
            } else {
                _processCollectWithReferral(referrerProfileId, collector, profileId, pubId, data);
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
    function getPublicationData(uint256 profileId, uint256 pubId)
        external
        view
        returns (ProfilePublicationData memory)
    {
        return _dataByPublicationByProfile[profileId][pubId];
    }

    function _processCollect(
        address collector,
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) internal {
        uint256 amount = _dataByPublicationByProfile[profileId][pubId].amount;
        address currency = _dataByPublicationByProfile[profileId][pubId].currency;
        _validateDataIsExpected(data, currency, amount);

        (address treasury, uint16 treasuryFee) = _treasuryData();
        uint256 treasuryAmount = (amount * treasuryFee) / BPS_MAX;

        // Send amount after treasury cut, to all recipients
        RecipientData[] memory recipients = _dataByPublicationByProfile[profileId][pubId]
            .recipients;
        _transferToRecipients(currency, collector, amount - treasuryAmount, recipients);

        if (treasuryAmount > 0) {
            IERC20(currency).safeTransferFrom(collector, treasury, treasuryAmount);
        }
    }

    function _processCollectWithReferral(
        uint256 referrerProfileId,
        address collector,
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) internal {
        uint256 amount = _dataByPublicationByProfile[profileId][pubId].amount;
        address currency = _dataByPublicationByProfile[profileId][pubId].currency;
        _validateDataIsExpected(data, currency, amount);

        uint256 referralFee = _dataByPublicationByProfile[profileId][pubId].referralFee;
        address treasury;
        uint256 treasuryAmount;

        // Avoids stack too deep
        {
            uint16 treasuryFee;
            (treasury, treasuryFee) = _treasuryData();
            treasuryAmount = (amount * treasuryFee) / BPS_MAX;
        }

        uint256 adjustedAmount = amount - treasuryAmount;

        if (referralFee != 0) {
            // The reason we levy the referral fee on the adjusted amount is so that referral fees
            // don't bypass the treasury fee, in essence referrals pay their fair share to the treasury.
            uint256 referralAmount = (adjustedAmount * referralFee) / BPS_MAX;
            if (referralAmount != 0) {
                adjustedAmount = adjustedAmount - referralAmount;

                address referralRecipient = IERC721(HUB).ownerOf(referrerProfileId);

                // Send referral fee in normal ERC20 tokens
                IERC20(currency).safeTransferFrom(collector, referralRecipient, referralAmount);
            }
        }

        // Send amount after treasury and referral fee, to all recipients
        RecipientData[] memory recipients = _dataByPublicationByProfile[profileId][pubId]
            .recipients;
        _transferToRecipients(currency, collector, adjustedAmount, recipients);

        if (treasuryAmount != 0) {
            IERC20(currency).safeTransferFrom(collector, treasury, treasuryAmount);
        }
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
            _dataByPublicationByProfile[profileId][pubId].recipients.push(recipients[0]);
        } else {
            // Check recipient splits sum to 10 000 BPS (100%)
            uint256 totalSplits;
            for (i; i < len; ) {
                if (recipients[i].recipient == address(0)) revert Errors.InitParamsInvalid();
                if (recipients[i].split == 0) revert RecipientSplitCannotBeZero();
                totalSplits += recipients[i].split;

                // Store each recipient while looping - avoids extra gas costs in successful cases
                _dataByPublicationByProfile[profileId][pubId].recipients.push(recipients[i]);

                unchecked {
                    ++i;
                }
            }

            if (totalSplits != BPS_MAX) revert InvalidRecipientSplits();
        }
    }

    function _transferToRecipients(
        address currency,
        address from,
        uint256 amount,
        RecipientData[] memory recipients
    ) internal {
        (uint256 i, uint256 len) = (0, recipients.length);

        // If only 1 recipient, transfer full amount and skip split calculations
        if (len == 1 && amount != 0) {
            IERC20(currency).safeTransferFrom(from, recipients[0].recipient, amount);
        } else {
            uint256 splitAmount;
            for (i; i < len; ) {
                splitAmount = (amount * recipients[i].split) / BPS_MAX;
                if (splitAmount != 0)
                    IERC20(currency).safeTransferFrom(from, recipients[i].recipient, splitAmount);

                unchecked {
                    ++i;
                }
            }
        }
    }
}
