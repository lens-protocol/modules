// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {ICollectModule} from '@aave/lens-protocol/contracts/interfaces/ICollectModule.sol';
import {Errors} from '@aave/lens-protocol/contracts/libraries/Errors.sol';
import {FeeModuleBase} from '@aave/lens-protocol/contracts/core/modules/FeeModuleBase.sol';
import {ModuleBase} from '@aave/lens-protocol/contracts/core/modules/ModuleBase.sol';
import {FollowValidationModuleBase} from '@aave/lens-protocol/contracts/core/modules/FollowValidationModuleBase.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';

/**
 * @notice A struct containing parameters for the standard curve quadratic equation (ax^2+bx+c).
 * @dev Has to be a separate struct to avoid stack-too-deep
 * @param a The a multiplier of x^2 in quadratic equation (how quadratic is the curve)
 * @param b The b multiplier of x in quadratic equation (if a==0, how steep is the line)
 * @param c The c constant in quadratic equation (aka start price)
 */
struct CurveParameters {
    uint256 a;
    uint256 b;
    uint256 c;
}

/**
 * @notice A struct containing the necessary data to execute collect actions on a publication.
 *
 * @param collectLimit The maximum number of collects for this publication.
 * @param currentCollects The current number of collects for this publication.
 * @param currency The currency associated with this publication.
 * @param recipient The recipient address associated with this publication.
 * @param referralFee The referral fee associated with this publication.
 * @param followerOnly Whether only followers should be able to collect.
 * @param endTimestamp The end timestamp after which collecting is impossible.
 * @param curveParams Quadratic equation curve parameters.
 */
struct ProfilePublicationData {
    uint256 currentCollects;
    uint256 collectLimit;
    address currency;
    address recipient;
    uint16 referralFee;
    bool followerOnly;
    uint40 endTimestamp;
    CurveParameters curveParams;
}

// TODO: The above can be optimized to take only 3 slots:
// TODO: But sacrificing value ranges or precision (which in this case doesn't really matter?)
// struct ProfilePublicationData {
//     address currency; //////// 160 // 1nd slot
//     bool followerOnly; /////// 8
//     uint16 referralFee; ////// 16
//     uint72 a; //////////////// 72

//     uint56 b; //////////////// 56 // 2st slot
//     address recipient; /////// 160
//     uint40 endTimestamp; ///// 40

//     uint128 c; /////////////// 128 // 3rd slot
//     uint64 collectLimit; ///// 64
//     uint64 currentCollects; // 64
// }

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
 * a=0 makes it a linear-growing fee collect.
 */
contract StepwiseCollectModule is FeeModuleBase, FollowValidationModuleBase, ICollectModule {
    using SafeERC20 for IERC20;

    mapping(uint256 => mapping(uint256 => ProfilePublicationData))
        internal _dataByPublicationByProfile;

    constructor(address hub, address moduleGlobals) FeeModuleBase(moduleGlobals) ModuleBase(hub) {}

    /**
     * @notice This collect module levies a fee on collects and supports referrals. Thus, we need to decode data.
     *
     * @param profileId The profile ID of the publication to initialize this module for's publishing profile.
     * @param pubId The publication ID of the publication to initialize this module for.
     * @param data The arbitrary data parameter, decoded into:
     *      uint256 collectLimit: The maximum amount of collects.
     *      uint256 amount: The currency total amount to levy.
     *      address currency: The currency address, must be internally whitelisted.
     *      address recipient: The custom recipient address to direct earnings to.
     *      uint16 referralFee: The referral fee to set.
     *      bool followerOnly: Whether only followers should be able to collect.
     *      uint40 endTimestamp: The end timestamp after which collecting is impossible.
     *      uint256 a: The a multiplier of x^2 in quadratic equation (how quadratic is the curve)
     *      uint256 b: The b multiplier of x in quadratic equation (if a==0, how steep is the line)
     *      uint256 c: The c constant in quadratic equation (aka start price)
     *
     * @return bytes An abi encoded bytes parameter, containing (in order): collectLimit, amount, currency, recipient, referral fee & end timestamp.
     */
    function initializePublicationCollectModule(
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) external override onlyHub returns (bytes memory) {
        unchecked {
            (
                uint256 collectLimit,
                address currency,
                address recipient,
                uint16 referralFee,
                bool followerOnly,
                uint40 endTimestamp,
                CurveParameters memory curveParams
            ) = abi.decode(
                    data,
                    (uint256, address, address, uint16, bool, uint40, CurveParameters)
                );
            {
                if (
                    collectLimit == 0 ||
                    !_currencyWhitelisted(currency) ||
                    recipient == address(0) ||
                    referralFee > BPS_MAX ||
                    endTimestamp <= block.timestamp
                ) revert Errors.InitParamsInvalid();
            }
            _dataByPublicationByProfile[profileId][pubId] = ProfilePublicationData(
                collectLimit,
                0,
                currency,
                recipient,
                referralFee,
                followerOnly,
                endTimestamp,
                curveParams
            );
            return
                abi.encode(
                    collectLimit,
                    currency,
                    recipient,
                    referralFee,
                    followerOnly,
                    endTimestamp,
                    curveParams
                );
        }
    }

    /**
     * @dev Processes a collect by:
     *  1. Ensuring the collector is a follower
     *  2. Ensuring the current timestamp is less than or equal to the collect end timestamp
     *  3. Ensuring the collect does not pass the collect limit
     *  4. Charging a fee
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
        if (block.timestamp > endTimestamp) revert Errors.CollectExpired();

        if (
            _dataByPublicationByProfile[profileId][pubId].currentCollects >=
            _dataByPublicationByProfile[profileId][pubId].collectLimit
        ) {
            revert Errors.MintLimitExceeded();
        } else {
            ++_dataByPublicationByProfile[profileId][pubId].currentCollects;
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
     * @return ProfilepublicationData The ProfilePublicationData struct mapped to that publication.
     */
    function getPublicationData(uint256 profileId, uint256 pubId)
        external
        view
        returns (ProfilePublicationData memory)
    {
        return _dataByPublicationByProfile[profileId][pubId];
    }

    // TODO: Decide if we want to expose it publicly (for easier frontend calculation/verification of how much you need to pay?)
    function calculateFee(ProfilePublicationData memory data) public pure returns (uint256) {
        // TODO: Probably unnecessary optimization - verify if it's necessary:
        if (data.curveParams.a == 0 && data.curveParams.b == 0) return data.curveParams.c;
        if (data.curveParams.a == 0)
            return (data.curveParams.b * data.currentCollects) / 1e18 + data.curveParams.c; // TODO: Decide on decimals of 1.0 and move 1e18 to constants
        return
            ((data.curveParams.a * data.currentCollects * data.currentCollects) / 1e18) +
            ((data.curveParams.b * data.currentCollects) / 1e18) +
            data.curveParams.c;
    }

    function _processCollect(
        address collector,
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) internal {
        uint256 amount = calculateFee(_dataByPublicationByProfile[profileId][pubId]);
        address currency = _dataByPublicationByProfile[profileId][pubId].currency;
        // _validateDataIsExpected(data, currency, amount); // TODO: Decide what to do with that verification - it will not work here. Probably just override?

        (address treasury, uint16 treasuryFee) = _treasuryData();
        address recipient = _dataByPublicationByProfile[profileId][pubId].recipient;
        uint256 treasuryAmount = (amount * treasuryFee) / BPS_MAX;
        uint256 adjustedAmount = amount - treasuryAmount;

        IERC20(currency).safeTransferFrom(collector, recipient, adjustedAmount);
        if (treasuryAmount > 0)
            IERC20(currency).safeTransferFrom(collector, treasury, treasuryAmount);
    }

    function _processCollectWithReferral(
        uint256 referrerProfileId,
        address collector,
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) internal {
        uint256 amount = calculateFee(_dataByPublicationByProfile[profileId][pubId]);
        address currency = _dataByPublicationByProfile[profileId][pubId].currency;
        // _validateDataIsExpected(data, currency, amount); // TODO: Decide what to do with that verification - it will not work here. Probably just override?

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
        if (treasuryAmount > 0)
            IERC20(currency).safeTransferFrom(collector, treasury, treasuryAmount);
    }
}
