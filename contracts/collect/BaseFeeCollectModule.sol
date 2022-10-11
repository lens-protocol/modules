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
 * @param recipient Recipient of collect fees.
 */
struct ProfilePublicationData {
    uint160 amount;
    uint96 collectLimit;
    address currency;
    uint96 currentCollects;
    address recipient;
    uint16 referralFee;
    bool followerOnly;
    uint72 endTimestamp;
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
 * @param recipient Recipient of collect fees.
 */
struct CollectModuleInitData {
    uint160 amount;
    uint96 collectLimit;
    address currency;
    uint16 referralFee;
    bool followerOnly;
    uint72 endTimestamp;
    address recipient;
}

/**
 * @title BaseFeeCollectModule
 * @author Lens Protocol
 *
 * @notice This is a base Lens CollectModule implementation, allowing customization of time to collect, number of collects
 * and whether only followers can collect.
 * You can build your own collect modules by inheriting this contract and overriding functions.
 */
contract BaseFeeCollectModule is FeeModuleBase, FollowValidationModuleBase, ICollectModule {
    using SafeERC20 for IERC20;

    mapping(uint256 => mapping(uint256 => ProfilePublicationData))
        internal _dataByPublicationByProfile;

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
    ) external virtual override onlyHub returns (bytes memory) {
        _validateInitData(profileId, pubId, data);
        _beforeStoreHook(profileId, pubId, data);
        _storePublicationCollectParameters(profileId, pubId, data);
        _afterStoreHook(profileId, pubId, data);
        return data;
    }

    function _validateInitData(
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) internal virtual {
        CollectModuleInitData memory initData = _decodeStandardInitParameters(data);
        if (
            !_currencyWhitelisted(initData.currency) ||
            initData.referralFee > BPS_MAX ||
            (initData.endTimestamp < block.timestamp && initData.endTimestamp > 0)
        ) revert Errors.InitParamsInvalid();
    }

    function _decodeStandardInitParameters(bytes calldata data)
        internal
        virtual
        returns (CollectModuleInitData memory)
    {
        return abi.decode(data, (CollectModuleInitData));
    }

    function _beforeStoreHook(
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) internal virtual {}

    function _afterStoreHook(
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) internal virtual {}

    function _storePublicationCollectParameters(
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) internal virtual {
        CollectModuleInitData memory initData = _decodeStandardInitParameters(data);

        // Saving the whole thing in one write operation as a struct saves 221 gas:
        _dataByPublicationByProfile[profileId][pubId] = ProfilePublicationData({
            amount: initData.amount,
            collectLimit: initData.collectLimit,
            currency: initData.currency,
            currentCollects: 0,
            recipient: initData.recipient,
            referralFee: initData.referralFee,
            followerOnly: initData.followerOnly,
            endTimestamp: initData.endTimestamp
        });
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
        uint96 currentCollects = _validateCollect(
            referrerProfileId,
            collector,
            profileId,
            pubId,
            data
        );
        _dataByPublicationByProfile[profileId][pubId].currentCollects = ++currentCollects;
        if (referrerProfileId == profileId) {
            _processCollect(collector, profileId, pubId, data);
        } else {
            _processCollectWithReferral(referrerProfileId, collector, profileId, pubId, data);
        }
    }

    function _validateCollect(
        uint256 referrerProfileId,
        address collector,
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) internal virtual returns (uint96) {
        if (_dataByPublicationByProfile[profileId][pubId].followerOnly)
            _checkFollowValidity(profileId, collector);

        uint256 endTimestamp = _dataByPublicationByProfile[profileId][pubId].endTimestamp;
        uint256 collectLimit = _dataByPublicationByProfile[profileId][pubId].collectLimit;
        uint96 currentCollects = _dataByPublicationByProfile[profileId][pubId].currentCollects;

        if (collectLimit != 0 && currentCollects == collectLimit) {
            revert Errors.MintLimitExceeded();
        }
        if (block.timestamp > endTimestamp && endTimestamp != 0) {
            revert Errors.CollectExpired();
        }

        return currentCollects;
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

    /**
     * @notice Calculates and returns the collect fee of a publication.
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

    function _processCollect(
        address collector,
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) internal {
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

    function _processCollectWithReferral(
        uint256 referrerProfileId,
        address collector,
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) internal {
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
            adjustedAmount
        );

        _transferToRecipients(currency, collector, profileId, pubId, adjustedAmount);

        if (treasuryAmount != 0) {
            IERC20(currency).safeTransferFrom(collector, treasury, treasuryAmount);
        }
    }

    function _transferToReferrals(
        address currency,
        uint256 referrerProfileId,
        address collector,
        uint256 profileId,
        uint256 pubId,
        uint256 adjustedAmount
    ) internal virtual returns (uint256) {
        uint256 referralFee = _dataByPublicationByProfile[profileId][pubId].referralFee;
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
        return adjustedAmount;
    }
}
