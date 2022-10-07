// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.10;

import {Errors} from '@aave/lens-protocol/contracts/libraries/Errors.sol';
import {FeeModuleBase} from '@aave/lens-protocol/contracts/core/modules/FeeModuleBase.sol';
import {ICollectModule} from '@aave/lens-protocol/contracts/interfaces/ICollectModule.sol';
import {ModuleBase} from '@aave/lens-protocol/contracts/core/modules/ModuleBase.sol';
import {FollowValidationModuleBase} from '@aave/lens-protocol/contracts/core/modules/FollowValidationModuleBase.sol';

import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {IPoolDataProvider} from '../interfaces/IPoolDataProvider.sol';
import {IPool} from '@aave/core-v3/contracts/interfaces/IPool.sol';

import {EIP712} from '@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/**
 * @notice A struct containing the necessary data to execute collect actions on a publication.
 *
 * @param amount The collecting cost associated with this publication.
 * @param currency The currency associated with this publication.
 * @param collectLimit The maximum number of collects for this publication. 0 for no limit.
 * @param currentCollects The current number of collects for this publication.
 * @param recipient The recipient address associated with this publication.
 * @param referralFee The referral fee associated with this publication.
 * @param followerOnly True if only followers of publisher may collect the post.
 * @param endTimestamp The end timestamp after which collecting is impossible. 0 for no expiry.
 */
struct ProfilePublicationData {
    uint256 amount;
    address currency;
    uint96 collectLimit;
    uint96 currentCollects;
    address recipient;
    uint16 referralFee;
    bool followerOnly;
    uint72 endTimestamp;
}

/**
 * @title AaveFeeCollectModule
 * @author Lens Protocol
 *
 * @notice Extend the LimitedFeeCollectModule to deposit all received fees into the Aave Polygon Market (if applicable for the asset) and send the resulting aTokens to the beneficiary.
 */
contract AaveFeeCollectModule is FeeModuleBase, FollowValidationModuleBase, ICollectModule {
    using SafeERC20 for IERC20;

    // Pool Address Provider on Polygon for Aave v3 - set in constructor
    IPoolAddressesProvider public immutable POOL_ADDRESSES_PROVIDER;

    address public aavePool;

    mapping(uint256 => mapping(uint256 => ProfilePublicationData))
        internal _dataByPublicationByProfile;

    constructor(
        address hub,
        address moduleGlobals,
        IPoolAddressesProvider poolAddressesProvider
    ) ModuleBase(hub) FeeModuleBase(moduleGlobals) {
        POOL_ADDRESSES_PROVIDER = poolAddressesProvider;

        // Retrieve Aave pool address on module deployment
        aavePool = POOL_ADDRESSES_PROVIDER.getPool();
    }

    /**
     * @dev Anyone can call this function to update Aave v3 addresses.
     */
    function updateAavePoolAddress() public {
        aavePool = POOL_ADDRESSES_PROVIDER.getPool();
    }

    /**
     * @notice This collect module levies a fee on collects and supports referrals. Thus, we need to decode data.
     *
     * @param data The arbitrary data parameter, decoded into:
     *      uint96 collectLimit: The maximum amount of collects.
     *      uint256 amount: The currency total amount to levy.
     *      address currency: The currency address, must be internally whitelisted.
     *      address recipient: The custom recipient address to direct earnings to.
     *      uint16 referralFee: The referral fee to set.
     *      bool followerOnly: Whether only followers should be able to collect.
     *      uint72 endTimestamp: The end timestamp after which collecting is impossible.
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
            address currency,
            address recipient,
            uint16 referralFee,
            bool followerOnly,
            uint72 endTimestamp
        ) = abi.decode(data, (uint96, uint256, address, address, uint16, bool, uint72));
        if (
            !_currencyWhitelisted(currency) ||
            recipient == address(0) ||
            referralFee > BPS_MAX ||
            (endTimestamp < block.timestamp && endTimestamp > 0)
        ) revert Errors.InitParamsInvalid();

        _dataByPublicationByProfile[profileId][pubId].collectLimit = collectLimit;
        _dataByPublicationByProfile[profileId][pubId].amount = amount;
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
        address recipient = _dataByPublicationByProfile[profileId][pubId].recipient;
        uint256 treasuryAmount = (amount * treasuryFee) / BPS_MAX;

        _transferFromAndDepositToAaveIfApplicable(
            currency,
            collector,
            recipient,
            amount - treasuryAmount
        );

        if (treasuryAmount > 0) {
            IERC20(currency).safeTransferFrom(collector, treasury, treasuryAmount);
        }
    }

    function _transferFromAndDepositToAaveIfApplicable(
        address currency,
        address from,
        address beneficiary,
        uint256 amount
    ) internal {
        // First, transfer funds to this contract
        IERC20(currency).safeTransferFrom(from, address(this), amount);
        IERC20(currency).approve(aavePool, amount);

        // Then, attempt to supply funds in Aave v3, sending aTokens to beneficiary
        try IPool(aavePool).supply(currency, amount, beneficiary, 0) {} catch {
            // If supply() above fails, send funds directly to beneficiary
            IERC20(currency).safeTransfer(beneficiary, amount);
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

        _transferFromAndDepositToAaveIfApplicable(currency, collector, recipient, adjustedAmount);

        if (treasuryAmount > 0) {
            IERC20(currency).safeTransferFrom(collector, treasury, treasuryAmount);
        }
    }
}
