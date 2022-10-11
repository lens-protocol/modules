// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {Errors} from '@aave/lens-protocol/contracts/libraries/Errors.sol';
import {FeeModuleBase} from '@aave/lens-protocol/contracts/core/modules/FeeModuleBase.sol';
import {ICollectModule} from '@aave/lens-protocol/contracts/interfaces/ICollectModule.sol';
import {ModuleBase} from '@aave/lens-protocol/contracts/core/modules/ModuleBase.sol';
import {FollowValidationModuleBase} from '@aave/lens-protocol/contracts/core/modules/FollowValidationModuleBase.sol';

import {IERC4626} from '@openzeppelin/contracts/interfaces/IERC4626.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/**
 * @notice A struct containing the necessary data to execute collect actions on a publication.
 *
 * @param collectLimit The maximum number of collects for this publication.
 * @param currentCollects The current number of collects for this publication.
 * @param amount The collecting cost associated with this publication.
 * @param vault The ERC4626 compatible vault in which fees are deposited.
 * @param currency The currency associated with this publication.
 * @param recipient The recipient address associated with this publication.
 * @param referralFee The referral fee associated with this publication.
 * @param endTimestamp The end timestamp after which collecting is impossible.
 */
struct ProfilePublicationData {
    uint256 amount;
    address vault; // ERC4626 Vault in which fees are deposited
    uint96 collectLimit;
    address currency;
    uint96 currentCollects;
    address recipient;
    uint16 referralFee;
    bool followerOnly;
    uint72 endTimestamp;
}

/**
 * @title ERC4626FeeCollectModule
 * @author Lens Protocol
 *
 * @notice Extend the LimitedFeeCollectModule to deposit all received fees into an ERC-4626 compatible vault and send the resulting shares to the beneficiary.
 */
contract ERC4626FeeCollectModule is FeeModuleBase, FollowValidationModuleBase, ICollectModule {
    using SafeERC20 for IERC20;

    mapping(uint256 => mapping(uint256 => ProfilePublicationData))
        internal _dataByPublicationByProfile;

    constructor(address hub, address moduleGlobals) ModuleBase(hub) FeeModuleBase(moduleGlobals) {}

    /**
     * @notice This collect module levies a fee on collects and supports referrals. Thus, we need to decode data.
     *
     * @param data The arbitrary data parameter, decoded into:
     *      uint96 collectLimit: The maximum amount of collects. 0 for no limit.
     *      uint256 amount: The currency total amount to levy.
     *      address vault: The ERC4626 compatible vault in which fees are deposited.
     *      address recipient: The custom recipient address to direct earnings to.
     *      uint16 referralFee: The referral fee to set.
     *      bool followerOnly: Whether only followers should be able to collect.
     *      uint72 endTimestamp: The end timestamp after which collecting is impossible. 0 for no expiry.
     *
     * @return An abi encoded bytes parameter, which is the same as the passed data parameter.
     */
    function initializePublicationCollectModule(
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) external override onlyHub returns (bytes memory) {
        (
            uint96 collectLimit,
            uint256 amount,
            address vault,
            address recipient,
            uint16 referralFee,
            bool followerOnly,
            uint72 endTimestamp
        ) = abi.decode(data, (uint96, uint256, address, address, uint16, bool, uint72));

        // Get fee currency from vault's asset instead of publication params
        address currency = IERC4626(vault).asset();

        if (
            !_currencyWhitelisted(currency) ||
            vault == address(0) ||
            recipient == address(0) ||
            referralFee > BPS_MAX ||
            (endTimestamp < block.timestamp && endTimestamp > 0)
        ) revert Errors.InitParamsInvalid();

        _dataByPublicationByProfile[profileId][pubId].collectLimit = collectLimit;
        _dataByPublicationByProfile[profileId][pubId].amount = amount;
        _dataByPublicationByProfile[profileId][pubId].vault = vault;
        _dataByPublicationByProfile[profileId][pubId].currency = currency;
        _dataByPublicationByProfile[profileId][pubId].recipient = recipient;
        _dataByPublicationByProfile[profileId][pubId].referralFee = referralFee;
        _dataByPublicationByProfile[profileId][pubId].followerOnly = followerOnly;
        _dataByPublicationByProfile[profileId][pubId].endTimestamp = endTimestamp;

        return data;
    }

    /**
     * @dev Processes a collect by:
     *  1. Ensuring the collector is a follower if followerOnly mode == true
     *  2. Ensuring the current timestamp is less than or equal to the collect end timestamp
     *  2. Ensuring the collect does not pass the collect limit
     *  3. Charging a fee
     *
     * @inheritdoc ICollectModule
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

        if (collectLimit != 0 && currentCollects >= collectLimit) {
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

        address vault = _dataByPublicationByProfile[profileId][pubId].vault;

        (address treasury, uint16 treasuryFee) = _treasuryData();
        address recipient = _dataByPublicationByProfile[profileId][pubId].recipient;
        uint256 treasuryAmount = (amount * treasuryFee) / BPS_MAX;

        _transferFromAndDepositInVaultIfApplicable(
            currency,
            vault,
            collector,
            recipient,
            amount - treasuryAmount
        );

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

            // Send referral fee in normal ERC20 tokens
            IERC20(currency).safeTransferFrom(collector, referralRecipient, referralAmount);
        }
        address recipient = _dataByPublicationByProfile[profileId][pubId].recipient;

        _transferFromAndDepositInVaultIfApplicable(
            currency,
            _dataByPublicationByProfile[profileId][pubId].vault,
            collector,
            recipient,
            adjustedAmount
        );

        if (treasuryAmount > 0) {
            IERC20(currency).safeTransferFrom(collector, treasury, treasuryAmount);
        }
    }

    function _transferFromAndDepositInVaultIfApplicable(
        address currency,
        address vault,
        address from,
        address beneficiary,
        uint256 amount
    ) internal {
        // First, transfer funds to this contract
        IERC20(currency).safeTransferFrom(from, address(this), amount);
        IERC20(currency).approve(vault, amount);

        // Then, attempt to deposit funds in vault, sending shares to beneficiary
        try IERC4626(vault).deposit(amount, beneficiary) {} catch {
            // If deposit() above fails, send funds directly to beneficiary
            IERC20(currency).safeTransfer(beneficiary, amount);
        }
    }
}
