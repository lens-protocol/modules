// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {Errors} from '@aave/lens-protocol/contracts/libraries/Errors.sol';
import {FeeModuleBase} from '@aave/lens-protocol/contracts/core/modules/FeeModuleBase.sol';
import {ICollectModule} from '@aave/lens-protocol/contracts/interfaces/ICollectModule.sol';
import {ModuleBase} from '@aave/lens-protocol/contracts/core/modules/ModuleBase.sol';
import {FollowValidationModuleBase} from '@aave/lens-protocol/contracts/core/modules/FollowValidationModuleBase.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import {BaseFeeCollectModuleInitData, BaseProfilePublicationData, IBaseFeeCollectModule} from './IBaseFeeCollectModule.sol';

/**
 * @title BaseFeeCollectModule
 * @author Lens Protocol
 *
 * @notice This is an base Lens CollectModule implementation, allowing customization of time to collect, number of collects
 * and whether only followers can collect, charging a fee for collect and distributing it among Receiver/Referral/Treasury.
 * @dev Here we use "Base" terminology to anything that represents this base functionality (base structs, base functions, base storage).
 * @dev You can build your own collect modules on top of the "Base" by inheriting this contract and overriding functions.
 * @dev This contract is marked "abstract" as it requires you to implement initializePublicationCollectModule and getPublicationData functions when you inherit from it.
 * @dev See BaseFeeCollectModule as an example implementation.
 */
abstract contract BaseFeeCollectModule is
    FeeModuleBase,
    FollowValidationModuleBase,
    IBaseFeeCollectModule
{
    using SafeERC20 for IERC20;

    mapping(uint256 => mapping(uint256 => BaseProfilePublicationData))
        internal _dataByPublicationByProfile;

    constructor(address hub, address moduleGlobals) ModuleBase(hub) FeeModuleBase(moduleGlobals) {}

    /**
     * @dev Processes a collect by:
     *  1. Validating that collect action meets all needded criteria
     *  2. Processing the collect action either with or withour referral
     *
     * @inheritdoc ICollectModule
     */
    function processCollect(
        uint256 referrerProfileId,
        address collector,
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) external virtual onlyHub {
        _validateAndStoreCollect(referrerProfileId, collector, profileId, pubId, data);

        if (referrerProfileId == profileId) {
            _processCollect(collector, profileId, pubId, data);
        } else {
            _processCollectWithReferral(referrerProfileId, collector, profileId, pubId, data);
        }
    }

    // This function is not implemented because each Collect module has its own return data type
    // function getPublicationData(uint256 profileId, uint256 pubId) external view returns (.....) {}

    /**
     * @notice Returns the Base publication data for a given publication, or an empty struct if that publication was not
     * initialized with this module.
     *
     * @param profileId The token ID of the profile mapped to the publication to query.
     * @param pubId The publication ID of the publication to query.
     *
     * @return The BaseProfilePublicationData struct mapped to that publication.
     */
    function getBasePublicationData(uint256 profileId, uint256 pubId)
        public
        view
        virtual
        returns (BaseProfilePublicationData memory)
    {
        return _dataByPublicationByProfile[profileId][pubId];
    }

    /**
     * @notice Calculates and returns the collect fee of a publication.
     * @dev Override this function to use a different formula for the fee.
     *
     * @param profileId The token ID of the profile mapped to the publication to query.
     * @param pubId The publication ID of the publication to query.
     * @param data Any additional params needed to calculate the fee.
     *
     * @return The collect fee of the specified publication.
     */
    function calculateFee(
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) public view virtual returns (uint160) {
        return _dataByPublicationByProfile[profileId][pubId].amount;
    }

    /**
     * @dev Validates the Base parameters like:
     * 1) Is the currency whitelisted
     * 2) Is the referralFee in valid range
     * 3) Is the end of collects timestamp in valid range
     *
     * This should be called during initializePublicationCollectModule()
     *
     * @param baseInitData Module initialization data (see BaseFeeCollectModuleInitData struct)
     */
    function _validateBaseInitData(BaseFeeCollectModuleInitData memory baseInitData)
        internal
        virtual
    {
        if (
            !_currencyWhitelisted(baseInitData.currency) ||
            baseInitData.referralFee > BPS_MAX ||
            (baseInitData.endTimestamp != 0 && baseInitData.endTimestamp < block.timestamp)
        ) revert Errors.InitParamsInvalid();
    }

    /**
     * @dev Stores the initial module parameters
     *
     * This should be called during initializePublicationCollectModule()
     *
     * @param profileId The token ID of the profile publishing the publication.
     * @param pubId The publication ID.
     * @param baseInitData Module initialization data (see BaseFeeCollectModuleInitData struct)
     */
    function _storeBasePublicationCollectParameters(
        uint256 profileId,
        uint256 pubId,
        BaseFeeCollectModuleInitData memory baseInitData
    ) internal virtual {
        _dataByPublicationByProfile[profileId][pubId].amount = baseInitData.amount;
        _dataByPublicationByProfile[profileId][pubId].collectLimit = baseInitData.collectLimit;
        _dataByPublicationByProfile[profileId][pubId].currency = baseInitData.currency;
        _dataByPublicationByProfile[profileId][pubId].recipient = baseInitData.recipient;
        _dataByPublicationByProfile[profileId][pubId].referralFee = baseInitData.referralFee;
        _dataByPublicationByProfile[profileId][pubId].followerOnly = baseInitData.followerOnly;
        _dataByPublicationByProfile[profileId][pubId].endTimestamp = baseInitData.endTimestamp;
    }

    /**
     * @dev Validates the collect action by checking that:
     * 1) the collector is a follower (if enabled)
     * 2) the number of collects after the action doesn't surpass the collect limit (if enabled)
     * 3) the current block timestamp doesn't surpass the end timestamp (if enabled)
     *
     * This should be called during processCollect()
     *
     * @param referrerProfileId The LensHub profile token ID of the referrer's profile (only different in case of mirrors).
     * @param collector The collector address.
     * @param profileId The token ID of the profile associated with the publication being collected.
     * @param pubId The LensHub publication ID associated with the publication being collected.
     * @param data Arbitrary data __passed from the collector!__ to be decoded.
     */
    function _validateAndStoreCollect(
        uint256 referrerProfileId,
        address collector,
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) internal virtual {
        uint96 collectsAfter = ++_dataByPublicationByProfile[profileId][pubId].currentCollects;

        if (_dataByPublicationByProfile[profileId][pubId].followerOnly)
            _checkFollowValidity(profileId, collector);

        uint256 endTimestamp = _dataByPublicationByProfile[profileId][pubId].endTimestamp;
        uint256 collectLimit = _dataByPublicationByProfile[profileId][pubId].collectLimit;

        if (collectLimit != 0 && collectsAfter > collectLimit) {
            revert Errors.MintLimitExceeded();
        }
        if (endTimestamp != 0 && block.timestamp > endTimestamp) {
            revert Errors.CollectExpired();
        }
    }

    /**
     * @dev Internal processing of a collect:
     *  1. Calculation of fees
     *  2. Validation that fees are what collector expected
     *  3. Transfer of fees to recipient(-s) and treasury
     *
     * @param collector The address that will collect the post.
     * @param profileId The token ID of the profile associated with the publication being collected.
     * @param pubId The LensHub publication ID associated with the publication being collected.
     * @param data Arbitrary data __passed from the collector!__ to be decoded.
     */
    function _processCollect(
        address collector,
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) internal virtual {
        uint256 amount = calculateFee(profileId, pubId, data);
        address currency = _dataByPublicationByProfile[profileId][pubId].currency;
        _validateDataIsExpected(data, currency, amount);

        (address treasury, uint16 treasuryFee) = _treasuryData();
        uint256 treasuryAmount = (amount * treasuryFee) / BPS_MAX;

        // Send amount after treasury cut, to all recipients
        _transferToRecipients(currency, collector, profileId, pubId, amount - treasuryAmount);

        if (treasuryAmount > 0) {
            IERC20(currency).safeTransferFrom(collector, treasury, treasuryAmount);
        }
    }

    /**
     * @dev Internal processing of a collect with a referral(-s).
     *
     * Same as _processCollect, but also includes transfer to referral(-s):
     *  1. Calculation of fees
     *  2. Validation that fees are what collector expected
     *  3. Transfer of fees to recipient(-s), referral(-s) and treasury
     *
     * @param referrerProfileId The address of the referral.
     * @param collector The address that will collect the post.
     * @param profileId The token ID of the profile associated with the publication being collected.
     * @param pubId The LensHub publication ID associated with the publication being collected.
     * @param data Arbitrary data __passed from the collector!__ to be decoded.
     */
    function _processCollectWithReferral(
        uint256 referrerProfileId,
        address collector,
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) internal virtual {
        uint256 amount = calculateFee(profileId, pubId, data);
        address currency = _dataByPublicationByProfile[profileId][pubId].currency;
        _validateDataIsExpected(data, currency, amount);

        address treasury;
        uint256 treasuryAmount;

        // Avoids stack too deep
        {
            uint16 treasuryFee;
            (treasury, treasuryFee) = _treasuryData();
            treasuryAmount = (amount * treasuryFee) / BPS_MAX;
        }

        uint256 adjustedAmount = amount - treasuryAmount;
        adjustedAmount = _transferToReferrals(
            currency,
            referrerProfileId,
            collector,
            profileId,
            pubId,
            adjustedAmount,
            data
        );

        _transferToRecipients(currency, collector, profileId, pubId, adjustedAmount);

        if (treasuryAmount > 0) {
            IERC20(currency).safeTransferFrom(collector, treasury, treasuryAmount);
        }
    }

    /**
     * @dev Tranfers the fee to recipient(-s)
     *
     * Override this to add additional functionality (e.g. multiple recipients)
     *
     * @param currency Currency of the transaction
     * @param collector The address that collects the post (and pays the fee).
     * @param profileId The token ID of the profile associated with the publication being collected.
     * @param pubId The LensHub publication ID associated with the publication being collected.
     * @param amount Amount to transfer to recipient(-s)
     */
    function _transferToRecipients(
        address currency,
        address collector,
        uint256 profileId,
        uint256 pubId,
        uint256 amount
    ) internal virtual {
        address recipient = _dataByPublicationByProfile[profileId][pubId].recipient;

        if (amount > 0) {
            IERC20(currency).safeTransferFrom(collector, recipient, amount);
        }
    }

    /**
     * @dev Tranfers the part of fee to referral(-s)
     *
     * Override this to add additional functionality (e.g. multiple referrals)
     *
     * @param currency Currency of the transaction
     * @param referrerProfileId The address of the referral.
     * @param collector The address that collects the post (and pays the fee).
     * @param profileId The token ID of the profile associated with the publication being collected.
     * @param pubId The LensHub publication ID associated with the publication being collected.
     * @param adjustedAmount Amount of the fee after subtracting the Treasury part.
     * @param data Arbitrary data __passed from the collector!__ to be decoded.
     */
    function _transferToReferrals(
        address currency,
        uint256 referrerProfileId,
        address collector,
        uint256 profileId,
        uint256 pubId,
        uint256 adjustedAmount,
        bytes calldata data
    ) internal virtual returns (uint256) {
        uint256 referralFee = _dataByPublicationByProfile[profileId][pubId].referralFee;
        if (referralFee != 0) {
            // The reason we levy the referral fee on the adjusted amount is so that referral fees
            // don't bypass the treasury fee, in essence referrals pay their fair share to the treasury.
            uint256 referralAmount = (adjustedAmount * referralFee) / BPS_MAX;
            if (referralAmount > 0) {
                adjustedAmount = adjustedAmount - referralAmount;

                address referralRecipient = IERC721(HUB).ownerOf(referrerProfileId);

                // Send referral fee in normal ERC20 tokens
                IERC20(currency).safeTransferFrom(collector, referralRecipient, referralAmount);
            }
        }
        return adjustedAmount;
    }
}
