// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {Errors} from '@aave/lens-protocol/contracts/libraries/Errors.sol';
import {FeeModuleBase} from '@aave/lens-protocol/contracts/core/modules/FeeModuleBase.sol';
import {FollowValidationModuleBase} from '@aave/lens-protocol/contracts/core/modules/FollowValidationModuleBase.sol';
import {ICollectModule} from '@aave/lens-protocol/contracts/interfaces/ICollectModule.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC721} from '@openzeppelin/contracts/interfaces/IERC721.sol';
import {ILensHub} from '@aave/lens-protocol/contracts/interfaces/ILensHub.sol';
import {LensNFTBase} from '@aave/lens-protocol/contracts/core/base/LensNFTBase.sol';
import {ModuleBase} from '@aave/lens-protocol/contracts/core/modules/ModuleBase.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/**
 * @notice A struct containing the necessary data to execute collect actions on a publication.
 *
 * @param ownershipTokenId The token ID of the ownership NFT asociated with the publication.
 * @param amount The collecting cost associated with this publication.
 * @param currency The currency associated with this publication.
 * @param recipient The recipient address associated with this publication.
 * @param referralFee The referral fee associated with this publication.
 * @param followerOnly Whether only followers should be able to collect.
 */
struct ProfilePublicationData {
    uint256 ownershipTokenId;
    uint256 amount;
    address currency;
    address recipient;
    uint16 referralFee;
    bool followerOnly;
}

/**
 * @title UpdatableOwnableFeeCollectModule
 * @author Lens Protocol
 *
 * @notice A fee collect module that, for each publication that uses it, mints an ERC-721 ownership-NFT to its author.
 * Whoever owns the ownership-NFT has the rights to update the parameters required to do a successful collect operation
 * over its underlying publication.
 *
 */
contract UpdatableOwnableFeeCollectModule is
    FeeModuleBase,
    FollowValidationModuleBase,
    LensNFTBase,
    ICollectModule
{
    using SafeERC20 for IERC20;

    uint256 internal _tokenIdCounter;

    mapping(uint256 => mapping(uint256 => ProfilePublicationData))
        internal _dataByPublicationByProfile;

    constructor(address hub, address moduleGlobals) FeeModuleBase(moduleGlobals) ModuleBase(hub) {}

    /**
     * @notice This collect module levies a fee on collects and supports referrals. Thus, we need to decode data.
     *
     * @param profileId The token ID of the profile of the publisher, passed by the hub.
     * @param pubId The publication ID of the newly created publication, passed by the hub.
     * @param data The arbitrary data parameter, decoded into:
     *      uint256 amount: The currency total amount to levy.
     *      address currency: The currency address, must be internally whitelisted.
     *      address recipient: The custom recipient address to direct earnings to.
     *      uint16 referralFee: The referral fee to set.
     *      bool followerOnly: Whether only followers should be able to collect.
     *
     * @return bytes An abi encoded bytes parameter, which is the same as the passed data parameter.
     */
    function initializePublicationCollectModule(
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) external override onlyHub returns (bytes memory) {
        (
            uint256 amount,
            address currency,
            address recipient,
            uint16 referralFee,
            bool followerOnly
        ) = abi.decode(data, (uint256, address, address, uint16, bool));
        // NOTE: Intentionally removed the requirement of amount > 0
        if (!_currencyWhitelisted(currency) || recipient == address(0) || referralFee > BPS_MAX) {
            revert Errors.InitParamsInvalid();
        }

        _mint(IERC721(HUB).ownerOf(profileId), _tokenIdCounter);

        _dataByPublicationByProfile[profileId][pubId].ownershipTokenId = _tokenIdCounter;
        _dataByPublicationByProfile[profileId][pubId].amount = amount;
        _dataByPublicationByProfile[profileId][pubId].currency = currency;
        _dataByPublicationByProfile[profileId][pubId].recipient = recipient;
        _dataByPublicationByProfile[profileId][pubId].referralFee = referralFee;
        _dataByPublicationByProfile[profileId][pubId].followerOnly = followerOnly;

        unchecked {
            ++_tokenIdCounter;
        }

        return data;
    }

    /**
     * @dev Processes a collect by:
     *  1. Ensuring the collector is a follower
     *  2. Charging a fee
     */
    function processCollect(
        uint256 referrerProfileId,
        address collector,
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) external virtual override onlyHub {
        if (_dataByPublicationByProfile[profileId][pubId].followerOnly) {
            _checkFollowValidity(profileId, collector);
        }
        if (_dataByPublicationByProfile[profileId][pubId].amount > 0) {
            if (referrerProfileId == profileId) {
                _processCollect(collector, profileId, pubId, data);
            } else {
                _processCollectWithReferral(referrerProfileId, collector, profileId, pubId, data);
            }
        }
    }

    // NOTE: Intentionally omitted the requirement of amount > 0
    function updateModuleParameters(
        uint256 profileId,
        uint256 pubId,
        uint256 amount,
        address currency,
        address recipient,
        uint16 referralFee,
        bool followerOnly
    ) external virtual {
        if (ownerOf(_dataByPublicationByProfile[profileId][pubId].ownershipTokenId) == msg.sender) {
            if (
                !_currencyWhitelisted(currency) || recipient == address(0) || referralFee > BPS_MAX
            ) {
                revert Errors.InitParamsInvalid();
            } else {
                _dataByPublicationByProfile[profileId][pubId].amount = amount;
                _dataByPublicationByProfile[profileId][pubId].currency = currency;
                _dataByPublicationByProfile[profileId][pubId].recipient = recipient;
                _dataByPublicationByProfile[profileId][pubId].referralFee = referralFee;
                _dataByPublicationByProfile[profileId][pubId].followerOnly = followerOnly;
            }
        } else {
            revert('OnlyOwner');
        }
    }

    /**
     * @notice Returns the publication data for a given publication, or an empty struct if that publication was not
     * initialized with this module.
     *
     * @param profileId The token ID of the profile mapped to the publication to query.
     * @param pubId The publication ID of the publication to query.
     *
     * @return ProfilePublicationData The ProfilePublicationData struct mapped to that publication.
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
        address recipient = _dataByPublicationByProfile[profileId][pubId].recipient;
        uint256 treasuryAmount = (amount * treasuryFee) / BPS_MAX;
        uint256 adjustedAmount = amount - treasuryAmount;

        IERC20(currency).safeTransferFrom(collector, recipient, adjustedAmount);
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
            adjustedAmount = adjustedAmount - referralAmount;

            address referralRecipient = IERC721(HUB).ownerOf(referrerProfileId);

            IERC20(currency).safeTransferFrom(collector, referralRecipient, referralAmount);
        }
        address recipient = _dataByPublicationByProfile[profileId][pubId].recipient;

        IERC20(currency).safeTransferFrom(collector, recipient, adjustedAmount);
        if (treasuryAmount > 0) {
            IERC20(currency).safeTransferFrom(collector, treasury, treasuryAmount);
        }
    }
}
