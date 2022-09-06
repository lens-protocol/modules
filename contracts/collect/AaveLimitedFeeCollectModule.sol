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
 * @param collectLimit The maximum number of collects for this publication.
 * @param currentCollects The current number of collects for this publication.
 * @param amount The collecting cost associated with this publication.
 * @param recipient The recipient address associated with this publication.
 * @param currency The currency associated with this publication.
 * @param referralFee The referral fee associated with this publication.
 */
struct ProfilePublicationData {
    uint256 collectLimit;
    uint256 currentCollects;
    uint256 amount;
    address recipient;
    address currency;
    uint16 referralFee;
}

error AaveMarketInactiveOrFrozen();

// TODO change name of module
// TODO add timed element

/**
 * @title AaveLimitedFeeCollectModule
 * @author Lens Protocol
 *
 * @notice Extend the LimitedFeeCollectModule to deposit all received fees into the Aave Polygon Market (if applicable for the asset) and send the resulting aTokens to the beneficiary.
 */
contract AaveLimitedFeeCollectModule is EIP712, FeeModuleBase, FollowValidationModuleBase, ICollectModule {
    using SafeERC20 for IERC20;

    // Pool Address Provider on Polygon for Aave v3
    IPoolAddressesProvider public constant POOL_ADDRESSES_PROVIDER =
        IPoolAddressesProvider(0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb);

    address public aavePoolDataProvider;
    address public aavePool;

    mapping(uint256 => mapping(uint256 => ProfilePublicationData))
        internal _dataByPublicationByProfile;

    address[] public reserves;

    constructor(
        address hub,
        address moduleGlobals,
        address _lendingPool
    ) EIP712('AaveLimitedFeeCollectModule', '1') ModuleBase(hub) FeeModuleBase(moduleGlobals) {
        // Retrieve Aave addresses on module deployment
        aavePoolDataProvider = POOL_ADDRESSES_PROVIDER.getPoolDataProvider();
        aavePool = POOL_ADDRESSES_PROVIDER.getPool();
    }

    /**
     * @dev Anyone can call this function to update Aave v3 addresses.
     */
    function updateAaveAddresses() public {
        aavePoolDataProvider = POOL_ADDRESSES_PROVIDER.getPoolDataProvider();
        aavePool = POOL_ADDRESSES_PROVIDER.getPool();
    }

    /**
     * @notice This collect module levies a fee on collects and supports referrals. Thus, we need to decode data.
     *
     * @param data The arbitrary data parameter, decoded into:
     *      uint256 collectLimit: The maximum amount of collects.
     *      uint256 amount: The currency total amount to levy.
     *      address currency: The currency address, must be internally whitelisted.
     *      address recipient: The custom recipient address to direct earnings to.
     *      uint16 referralFee: The referral fee to set.
     *
     * @return An abi encoded bytes parameter, which is the same as the passed data parameter.
     */
    function initializePublicationCollectModule(
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) external override onlyHub returns (bytes memory) {
        (
            uint256 collectLimit,
            uint256 amount,
            address currency,
            address recipient,
            uint16 referralFee
        ) = abi.decode(data, (uint256, uint256, address, address, uint16));
        if (
            collectLimit == 0 ||
            !_currencyWhitelisted(currency) ||
            recipient == address(0) ||
            referralFee > BPS_MAX ||
            amount < BPS_MAX
        ) revert Errors.InitParamsInvalid();

        // Get Aave v3 market config data for currency
        (, , , , , , , , bool isActive, bool isFrozen) = IPoolDataProvider(aavePoolDataProvider)
            .getReserveConfigurationData(currency);

        if (!isActive || isFrozen) revert AaveMarketInactiveOrFrozen();

        _dataByPublicationByProfile[profileId][pubId].collectLimit = collectLimit;
        _dataByPublicationByProfile[profileId][pubId].amount = amount;
        _dataByPublicationByProfile[profileId][pubId].currency = currency;
        _dataByPublicationByProfile[profileId][pubId].recipient = recipient;
        _dataByPublicationByProfile[profileId][pubId].referralFee = referralFee;

        return data;
    }

    /**
     * @dev Processes a collect by:
     *  1. Ensuring the collector is a follower
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
        _checkFollowValidity(profileId, collector);

        if (
            _dataByPublicationByProfile[profileId][pubId].currentCollects >=
            _dataByPublicationByProfile[profileId][pubId].collectLimit
        ) {
            revert Errors.MintLimitExceeded();
        } else {
            _dataByPublicationByProfile[profileId][pubId].currentCollects++;
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
        uint256 adjustedAmount = amount - treasuryAmount;

        _transferFromAndDepositToAaveIfApplicable(currency, collector, recipient, adjustedAmount);
        IERC20(currency).safeTransferFrom(collector, treasury, treasuryAmount);
    }

    function _transferFromAndDepositToAaveIfApplicable(
        address currency,
        address from,
        address beneficiary,
        uint256 amount
    ) internal {
        // TODO add try catch
        if (true) {
            IERC20(currency).safeTransferFrom(from, address(this), amount);
            IERC20(currency).approve(aavePool, amount);
            IPool(aavePool).supply(currency, amount, beneficiary, 0);
        } else {
            IERC20(currency).safeTransferFrom(from, beneficiary, amount);
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

        _transferFromAndDepositToAaveIfApplicable(currency, collector, recipient, adjustedAmount);

        IERC20(currency).safeTransferFrom(collector, treasury, treasuryAmount);
    }
}
