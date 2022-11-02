// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {ICollectModule} from '@aave/lens-protocol/contracts/interfaces/ICollectModule.sol';
import {Errors} from '@aave/lens-protocol/contracts/libraries/Errors.sol';
import {FeeModuleBase} from '../FeeModuleBase.sol';
import {ModuleBase} from '@aave/lens-protocol/contracts/core/modules/ModuleBase.sol';
import {FollowValidationModuleBase} from '@aave/lens-protocol/contracts/core/modules/FollowValidationModuleBase.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';

/**
 * @notice A struct containing the necessary data to execute collect actions on a publication.
 * @notice a, b, c are coefficients of a standard quadratic equation (ax^2+bx+c) curve.
 * @dev Variable sizes are optimized to fit in 3 slots.
 * @param currency The currency associated with this publication.
 * @param a The a multiplier of x^2 in quadratic equation (how quadratic is the curve)
 * @param referralFee The referral fee associated with this publication.
 * @param followerOnly Whether only followers should be able to collect.
 * @param recipient The recipient address associated with this publication.
 * @param b The b multiplier of x in quadratic equation (if a==0, how steep is the line)
 * @param endTimestamp The end timestamp after which collecting is impossible.
 * @param c The c constant in quadratic equation (aka start price)
 * @param currentCollects The current number of collects for this publication.
 * @param collectLimit The maximum number of collects for this publication (0 for unlimited)
 */
struct ProfilePublicationData {
    address currency; // 1st slot
    uint72 a;
    uint16 referralFee;
    bool followerOnly;
    address recipient; // 2nd slot
    uint56 b;
    uint40 endTimestamp;
    uint128 c; // 3rd slot
    uint64 currentCollects;
    uint64 collectLimit;
}

/**
 * @notice A struct containing the necessary data to initialize Stepwise Collect Module.
 *
 * @param collectLimit The maximum number of collects for this publication (0 for unlimited)
 * @param currency The currency associated with this publication.
 * @param recipient The recipient address associated with this publication.
 * @param referralFee The referral fee associated with this publication.
 * @param followerOnly Whether only followers should be able to collect.
 * @param endTimestamp The end timestamp after which collecting is impossible.
 * @param a The a multiplier of x^2 in quadratic equation (how quadratic is the curve) (9 decimals)
 * @param b The b multiplier of x in quadratic equation (if a==0, how steep is the line) (9 decimals)
 * @param c The c constant in quadratic equation (aka start price) (18 decimals)
 */
struct StepwiseCollectModuleInitData {
    uint64 collectLimit;
    address currency;
    address recipient;
    uint16 referralFee;
    bool followerOnly;
    uint40 endTimestamp;
    uint72 a;
    uint56 b;
    uint128 c;
}

/**
 * @title StepwiseCollectModule
 * @author Lens Protocol
 *
 * @notice This is a simple Lens CollectModule implementation, inheriting from the ICollectModule interface and
 * the FeeCollectModuleBase abstract contract.
 *
 * This module works by allowing limited collects for a publication within the allotted time with a changing fee.
 *
 * The fee is calculated based on a simple quadratic equation:
 *      Fee = a*x^2 + b*x + c,
 *      (where x is how many collects were already performed)
 *
 * a=b=0 makes it a constant-fee collect
 * a=0 makes it a linear-growing fee collect
 */
contract StepwiseCollectModule is FeeModuleBase, FollowValidationModuleBase, ICollectModule {
    using SafeERC20 for IERC20;

    // As there is hard storage optimisation of a,b,c parameters, the following decimals convention is assumed for fixed-point calculations:
    uint256 public constant A_DECIMALS = 1e9; // leaves 30 bits for fractional part, 42 bits for integer part
    uint256 public constant B_DECIMALS = 1e9; // leaves 30 bits for fractional part, 26 bits for integer part
    // For C the decimals will be equal to currency decimals

    mapping(uint256 => mapping(uint256 => ProfilePublicationData))
        internal _dataByPublicationByProfile;

    constructor(address hub, address moduleGlobals) FeeModuleBase(moduleGlobals) ModuleBase(hub) {}

    /**
     * @notice This collect module levies a fee on collects and supports referrals. Thus, we need to decode data.
     *
     * @param profileId The profile ID of the publication to initialize this module for.
     * @param pubId The publication ID to initialize this module for.
     * @param data The arbitrary data parameter, decoded into: StepwiseCollectModuleInitData struct
     * @return bytes An abi encoded bytes parameter, containing a struct with module initialization data.
     */
    function initializePublicationCollectModule(
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) external override onlyHub returns (bytes memory) {
        StepwiseCollectModuleInitData memory initData = abi.decode(
            data,
            (StepwiseCollectModuleInitData)
        );
        {
            if (
                !_currencyWhitelisted(initData.currency) ||
                initData.recipient == address(0) ||
                initData.referralFee > BPS_MAX ||
                (initData.endTimestamp != 0 && initData.endTimestamp < block.timestamp)
            ) revert Errors.InitParamsInvalid();
        }
        _dataByPublicationByProfile[profileId][pubId] = ProfilePublicationData({
            currency: initData.currency,
            a: initData.a,
            referralFee: initData.referralFee,
            followerOnly: initData.followerOnly,
            recipient: initData.recipient,
            b: initData.b,
            endTimestamp: initData.endTimestamp,
            c: initData.c,
            currentCollects: 0,
            collectLimit: initData.collectLimit
        });
        return data;
    }

    /**
     * @dev Processes a collect by:
     *  1. Ensuring the collector is a follower
     *  2. Ensuring the current timestamp is less than or equal to the collect end timestamp
     *  3. Ensuring the collect does not pass the collect limit
     *  4. Charging a fee
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
        if (endTimestamp != 0 && block.timestamp > endTimestamp) revert Errors.CollectExpired();

        if (
            _dataByPublicationByProfile[profileId][pubId].collectLimit != 0 &&
            _dataByPublicationByProfile[profileId][pubId].currentCollects >=
            _dataByPublicationByProfile[profileId][pubId].collectLimit
        ) {
            revert Errors.MintLimitExceeded();
        } else {
            unchecked {
                ++_dataByPublicationByProfile[profileId][pubId].currentCollects;
            }
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
     * @return ProfilePublicationData The ProfilePublicationData struct mapped to that publication.
     */
    function getPublicationData(uint256 profileId, uint256 pubId)
        external
        view
        returns (ProfilePublicationData memory)
    {
        return _dataByPublicationByProfile[profileId][pubId];
    }

    // TODO: Decide if we need a view function at all
    /**
     * @notice Estimates the amount next collect will cost for a given publication.
     * @notice Subject to front-running, thus some slippage should be added.
     *
     * @param profileId The token ID of the profile mapped to the publication to query.
     * @param pubId The publication ID of the publication to query.
     *
     * @return fee Collect fee
     */
    function previewFee(uint256 profileId, uint256 pubId) public view returns (uint256) {
        ProfilePublicationData memory data = _dataByPublicationByProfile[profileId][pubId];
        data.currentCollects++;
        return _calculateFee(data);
    }

    /**
     * @dev Calculates the collect fee using quadratic formula.
     *
     * @param data ProfilePublicationData from storage containing the publication parameters.
     *
     * @return fee Collect fee.
     */
    function _calculateFee(ProfilePublicationData memory data) internal pure returns (uint256) {
        // Because we already incremented the current collects in storage - we need to adjust it here.
        // This is done to allow the first collect price to be equal to c parameter (better UX)
        uint256 collects = data.currentCollects - 1;
        if (data.a == 0) return (uint256(data.b) * collects) / B_DECIMALS + data.c;
        return
            ((uint256(data.a) * collects * collects) / A_DECIMALS) +
            ((uint256(data.b) * collects) / B_DECIMALS) +
            data.c;
    }

    /**
     * @dev Calculates and processes the collect action.
     *
     * @param collector The address that collects the publicaton.
     * @param profileId The token ID of the profile mapped to the publication to query.
     * @param pubId The publication ID of the publication to query.
     * @param data Abi encoded bytes parameter, containing currency address and fee amount
     */
    function _processCollect(
        address collector,
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) internal {
        uint256 amount = _calculateFee(_dataByPublicationByProfile[profileId][pubId]);
        address currency = _dataByPublicationByProfile[profileId][pubId].currency;
        _validateDataIsExpected(data, currency, amount);

        if (amount > 0) {
            (address treasury, uint16 treasuryFee) = _treasuryData();
            address recipient = _dataByPublicationByProfile[profileId][pubId].recipient;
            uint256 treasuryAmount = (amount * treasuryFee) / BPS_MAX;
            uint256 adjustedAmount = amount - treasuryAmount;

            IERC20(currency).safeTransferFrom(collector, recipient, adjustedAmount);
            if (treasuryAmount > 0)
                IERC20(currency).safeTransferFrom(collector, treasury, treasuryAmount);
        }
    }

    /**
     * @dev Calculates and processes the collect action with referral.
     *
     * @param referrerProfileId The profile receiving referral fees.
     * @param collector The address that collects the publicaton.
     * @param profileId The token ID of the profile mapped to the publication to query.
     * @param pubId The publication ID of the publication to query.
     * @param data Abi encoded bytes parameter, containing currency address and fee amount
     */
    function _processCollectWithReferral(
        uint256 referrerProfileId,
        address collector,
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) internal {
        uint256 amount = _calculateFee(_dataByPublicationByProfile[profileId][pubId]);
        address currency = _dataByPublicationByProfile[profileId][pubId].currency;
        _validateDataIsExpected(data, currency, amount);

        if (amount > 0) {
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

                if (referralAmount > 0) {
                    adjustedAmount = adjustedAmount - referralAmount;

                    address referralRecipient = IERC721(HUB).ownerOf(referrerProfileId);

                    IERC20(currency).safeTransferFrom(collector, referralRecipient, referralAmount);
                }
            }
            address recipient = _dataByPublicationByProfile[profileId][pubId].recipient;

            IERC20(currency).safeTransferFrom(collector, recipient, adjustedAmount);
            if (treasuryAmount > 0)
                IERC20(currency).safeTransferFrom(collector, treasury, treasuryAmount);
        }
    }

    /**
     * @dev Validates if the desired data provided (currency and maximum amount) corresponds to actual values of the tx.
     *
     * @param data Abi encoded bytes parameter, containing currency address and fee amount
     * @param currency Currency of the fee.
     * @param amount Fee amount.
     */
    function _validateDataIsExpected(
        bytes calldata data,
        address currency,
        uint256 amount
    ) internal pure override {
        (address decodedCurrency, uint256 decodedMaxAmount) = abi.decode(data, (address, uint256));
        if (amount > decodedMaxAmount || decodedCurrency != currency)
            revert Errors.ModuleDataMismatch();
    }
}
