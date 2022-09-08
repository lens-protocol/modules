// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {Base64} from '@openzeppelin/contracts/utils/Base64.sol';
import {DataTypes} from '@aave/lens-protocol/contracts/libraries/DataTypes.sol';
import {EIP712} from '@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol';
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
import {Strings} from '@openzeppelin/contracts/utils/Strings.sol';

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
 * @notice A struct containing the publication composite identifier.
 *
 * @param profileId The token ID of the profile associated with the publication.
 * @param pubId The publication ID associated with the publication.
 */
struct Publication {
    uint256 profileId;
    uint256 pubId;
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
    EIP712,
    FeeModuleBase,
    FollowValidationModuleBase,
    LensNFTBase,
    ICollectModule
{
    using SafeERC20 for IERC20;

    error InvalidParameters();
    error OnlyOwner();

    event ModuleParametersUpdated(
        uint256 indexed profileId,
        uint256 indexed pubId,
        uint256 amount,
        address currency,
        address recipient,
        uint16 referralFee,
        bool followerOnly
    );

    uint256 internal _tokenIdCounter;

    mapping(uint256 => mapping(uint256 => ProfilePublicationData))
        internal _dataByPublicationByProfile;

    mapping(uint256 => Publication) internal _publicationByTokenId;

    constructor(address hub, address moduleGlobals)
        EIP712('UpdatableOwnableFeeCollectModule', '1')
        FeeModuleBase(moduleGlobals)
        ModuleBase(hub)
    {}

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for the given token.
     *
     * @param tokenId The ID of the token whose URI is being queried.
     *
     * @return string The corresponding token URI.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (!_exists(tokenId)) {
            revert Errors.TokenDoesNotExist();
        }
        string memory pubIdString = string(
            abi.encodePacked(
                Strings.toString(_publicationByTokenId[tokenId].profileId),
                '-',
                Strings.toString(_publicationByTokenId[tokenId].pubId)
            )
        );
        return
            string(
                abi.encodePacked(
                    'data:application/json;base64,',
                    Base64.encode(
                        abi.encodePacked(
                            '{ "name": "Ownership of Lens Publication #',
                            pubIdString,
                            '","description": "Owning this NFT allows the owner to change the collect parameters of the #',
                            pubIdString,
                            ' publication.", "image": "ipfs://bafkreifclgvhtotpoquwoo7enjof6xfqjbthukddkxagtykjfnc3kh6khm" }'
                        )
                    )
                )
            );
    }

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
        if (!_currencyWhitelisted(currency) || referralFee > BPS_MAX) {
            revert Errors.InitParamsInvalid();
        }

        unchecked {
            uint256 tokenId = ++_tokenIdCounter;
            _mint(IERC721(HUB).ownerOf(profileId), tokenId);
            _publicationByTokenId[tokenId] = Publication(profileId, pubId);
            _dataByPublicationByProfile[profileId][pubId].ownershipTokenId = tokenId;
        }
        _dataByPublicationByProfile[profileId][pubId].amount = amount;
        _dataByPublicationByProfile[profileId][pubId].currency = currency;
        _dataByPublicationByProfile[profileId][pubId].recipient = recipient;
        _dataByPublicationByProfile[profileId][pubId].referralFee = referralFee;
        _dataByPublicationByProfile[profileId][pubId].followerOnly = followerOnly;

        return data;
    }

    /**
     * @notice Process the collect operation over the given publication, in this case by charging a fee.
     *
     * @dev Only callable by the LensHub contract. It delegates the fee processing to
     * `_processCollectFeeWithoutReferral` or `_processCollectFeeWithReferral` depending if has referrer or not.
     *
     * @param referrerProfileId The LensHub profile token ID of the referrer's profile (only different in case of mirrors).
     * @param collector The collector address.
     * @param profileId The token ID of the profile associated with the publication being collected.
     * @param pubId The LensHub publication ID associated with the publication being collected.
     * @param data Custom data that must contain the expected fee currency and amount encoded.
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

    /**
     * @notice Allows the owner of the ownership-NFT corresponding to the given publication to update the parameters
     * required to do a successful collect operation.
     *
     * @param profileId The token ID of the profile associated with the publication.
     * @param pubId The publication ID associated with the publication.
     * @param amount The amount of fee charged for each collect.
     * @param currency The currency in which the amount is charged.
     * @param recipient The address that will receive the collect fees.
     * @param referralFee The percentage of the fee that will be transferred to the referrer in case of having one.
     * Measured in basis points, each basis point represents 0.01%.
     * @param followerOnly A boolean indicating whether followers are the only allowed to collect or not.
     */
    function updateModuleParameters(
        uint256 profileId,
        uint256 pubId,
        uint256 amount,
        address currency,
        address recipient,
        uint16 referralFee,
        bool followerOnly
    ) external virtual {
        _updateModuleParameters(
            profileId,
            pubId,
            amount,
            currency,
            recipient,
            referralFee,
            followerOnly,
            msg.sender
        );
    }

    /**
     * @notice Allows the owner of the ownership-NFT corresponding to the given publication to update the parameters
     * required to do a successful collect operation.
     *
     * @param profileId The token ID of the profile associated with the publication.
     * @param pubId The publication ID associated with the publication.
     * @param amount The amount of fee charged for each collect.
     * @param currency The currency in which the amount is charged.
     * @param recipient The address that will receive the collect fees.
     * @param referralFee The percentage of the fee that will be transferred to the referrer in case of having one.
     * Measured in basis points, each basis point represents 0.01%.
     * @param followerOnly A boolean indicating whether followers are the only allowed to collect or not.
     * @param operator The address that is executing this parameter update. Should match the recovered signer.
     * @param sig The EIP-712 signature for this operation.
     */
    function updateModuleParametersWithSig(
        uint256 profileId,
        uint256 pubId,
        uint256 amount,
        address currency,
        address recipient,
        uint16 referralFee,
        bool followerOnly,
        address operator,
        DataTypes.EIP712Signature calldata sig
    ) external virtual {
        _validateUpdateModuleParametersSignature(
            profileId,
            pubId,
            amount,
            currency,
            recipient,
            referralFee,
            followerOnly,
            operator,
            sig
        );
        _updateModuleParameters(
            profileId,
            pubId,
            amount,
            currency,
            recipient,
            referralFee,
            followerOnly,
            operator
        );
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

    /**
     * @notice Returns the underlying publication corresponding to the given token ID.
     *
     * @param tokenId The ID of the token whose underlying publication is being queried.
     *
     * @return PublicationStruct The PublicationStruct of the given publication.
     */
    function getPublicationByTokenId(uint256 tokenId)
        public
        view
        returns (DataTypes.PublicationStruct memory)
    {
        if (!_exists(tokenId)) {
            revert Errors.TokenDoesNotExist();
        }
        return
            ILensHub(HUB).getPub(
                _publicationByTokenId[tokenId].profileId,
                _publicationByTokenId[tokenId].pubId
            );
    }

    /**
     * @notice Process the collect fee without referral.
     *
     * @param collector The collector address.
     * @param profileId The token ID of the profile associated with the publication being collected.
     * @param pubId The LensHub publication ID associated with the publication being collected.
     * @param data Custom data that must contain the expected fee currency and amount encoded.
     */
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

    /**
     * @notice Process the collect fee with referral.
     *
     * @param referrerProfileId The LensHub profile token ID of the referrer's profile.
     * @param collector The collector address.
     * @param profileId The token ID of the profile associated with the publication being collected.
     * @param pubId The LensHub publication ID associated with the publication being collected.
     * @param data Custom data that must contain the expected fee currency and amount encoded.
     */
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

    /**
     * @notice Internal function to abstract the logic regarding the parameter updating.
     *
     * @param profileId The token ID of the profile associated with the publication.
     * @param pubId The publication ID associated with the publication.
     * @param amount The amount of fee charged for each collect.
     * @param currency The currency in which the amount is charged.
     * @param recipient The address that will receive the collect fees.
     * @param referralFee The percentage of the fee that will be transferred to the referrer in case of having one.
     * Measured in basis points, each basis point represents 0.01%.
     * @param followerOnly A boolean indicating whether followers are the only allowed to collect or not.
     * @param operator The address that is executing this parameter update.
     */
    function _updateModuleParameters(
        uint256 profileId,
        uint256 pubId,
        uint256 amount,
        address currency,
        address recipient,
        uint16 referralFee,
        bool followerOnly,
        address operator
    ) internal {
        if (ownerOf(_dataByPublicationByProfile[profileId][pubId].ownershipTokenId) != operator) {
            revert OnlyOwner();
        }
        if (!_currencyWhitelisted(currency) || referralFee > BPS_MAX) {
            revert InvalidParameters();
        }
        _dataByPublicationByProfile[profileId][pubId].amount = amount;
        _dataByPublicationByProfile[profileId][pubId].currency = currency;
        _dataByPublicationByProfile[profileId][pubId].recipient = recipient;
        _dataByPublicationByProfile[profileId][pubId].referralFee = referralFee;
        _dataByPublicationByProfile[profileId][pubId].followerOnly = followerOnly;
        emit ModuleParametersUpdated(
            profileId,
            pubId,
            amount,
            currency,
            recipient,
            referralFee,
            followerOnly
        );
    }

    /**
     * @notice Checks if the signature for the `updateModuleParametersWithSig` function is valid according EIP-712.
     *
     * @param profileId The token ID of the profile associated with the publication.
     * @param pubId The publication ID associated with the publication.
     * @param amount The amount of fee charged for each collect.
     * @param currency The currency in which the amount is charged.
     * @param recipient The address that will receive the collect fees.
     * @param referralFee The percentage of the fee that will be transferred to the referrer in case of having one.
     * Measured in basis points, each basis point represents 0.01%.
     * @param followerOnly A boolean indicating whether followers are the only allowed to collect or not.
     * @param operator The address that is executing this parameter update. Should match the recovered signer.
     * @param sig The EIP-712 signature for this operation.
     */
    function _validateUpdateModuleParametersSignature(
        uint256 profileId,
        uint256 pubId,
        uint256 amount,
        address currency,
        address recipient,
        uint16 referralFee,
        bool followerOnly,
        address operator,
        DataTypes.EIP712Signature calldata sig
    ) internal {
        unchecked {
            _validateRecoveredAddress(
                _calculateDigest(
                    abi.encode(
                        keccak256(
                            'UpdateModuleParametersWithSig(uint256 profileId,uint256 pubId,uint256 amount,address currency,address recipient,uint16 referralFee,bool followerOnly,uint256 nonce,uint256 deadline)'
                        ),
                        profileId,
                        pubId,
                        amount,
                        currency,
                        recipient,
                        referralFee,
                        followerOnly,
                        sigNonces[operator]++,
                        sig.deadline
                    )
                ),
                operator,
                sig
            );
        }
    }

    /**
     * @notice Calculates the digest for the given bytes according EIP-712 standard.
     *
     * @param message The message, as bytes, to calculate the digest from.
     */
    function _calculateDigest(bytes memory message) internal view returns (bytes32) {
        return keccak256(abi.encodePacked('\x19\x01', _domainSeparatorV4(), keccak256(message)));
    }
}
