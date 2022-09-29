// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IReferenceModule} from '@aave/lens-protocol/contracts/interfaces/IReferenceModule.sol';
import {ModuleBase} from '@aave/lens-protocol/contracts/core/modules/ModuleBase.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {Errors} from '@aave/lens-protocol/contracts/libraries/Errors.sol';

interface IToken {
    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @notice A struct containing the necessary data to execute TokenGated references.
 *
 * @param tokenAddress The address of ERC20/ERC721 token used for gating the reference
 * @param minThreshold The minimum balance threshold of the gated token required to execute a reference
 */
struct GateParams {
    address tokenAddress;
    uint256 minThreshold;
}

/**
 * @title TokenGatedReferenceModule
 * @author Lens Protocol
 *
 * @notice A reference module that validates that the user who tries to reference has a required minimum balance of ERC20/ERC721 token.
 */
contract TokenGatedReferenceModule is ModuleBase, IReferenceModule {
    uint256 internal constant UINT256_BYTES = 32;

    event TokenGatedReferencePublicationCreated(
        uint256 indexed profileId,
        uint256 indexed pubId,
        address tokenAddress,
        uint256 minThreshold
    );

    error NotEnoughBalance();

    mapping(uint256 => mapping(uint256 => GateParams)) internal _gateParamsByPublicationByProfile;

    constructor(address hub) ModuleBase(hub) {}

    /**
     * @dev The gating token address and minimum balance threshold is passed during initialization in data field (see `GateParams` struct)
     *
     * @inheritdoc IReferenceModule
     */
    function initializeReferenceModule(
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) external override onlyHub returns (bytes memory) {
        GateParams memory gateParams = abi.decode(data, (GateParams));

        // Checking if the tokenAddress resembles ERC20/ERC721 token (by calling balanceOf() function)
        (bool success, bytes memory result) = gateParams.tokenAddress.staticcall(
            abi.encodeWithSignature('balanceOf(address)', address(this))
        );
        // We don't check if the contract exists cause we expect the return data anyway
        if (gateParams.minThreshold == 0 || !success || result.length != UINT256_BYTES)
            revert Errors.InitParamsInvalid();

        _gateParamsByPublicationByProfile[profileId][pubId] = gateParams;
        emit TokenGatedReferencePublicationCreated(
            profileId,
            pubId,
            gateParams.tokenAddress,
            gateParams.minThreshold
        );
        return data;
    }

    /**
     * @notice Validates that the commenting profile's owner has enough balance of the gating token.
     */
    function processComment(
        uint256 profileId,
        uint256 profileIdPointed,
        uint256 pubIdPointed,
        bytes calldata data
    ) external view override onlyHub {
        _validateTokenBalance(profileId, profileIdPointed, pubIdPointed);
    }

    /**
     * @notice Validates that the mirroring profile's owner has enough balance of the gating token.
     */
    function processMirror(
        uint256 profileId,
        uint256 profileIdPointed,
        uint256 pubIdPointed,
        bytes calldata data
    ) external view override onlyHub {
        _validateTokenBalance(profileId, profileIdPointed, pubIdPointed);
    }

    /**
     * @dev Validates the profile's owner balance of gating token.
     * @dev Can work with both ERC20 and ERC721 as both interfaces support balanceOf() call
     */
    function _validateTokenBalance(
        uint256 profileId,
        uint256 profileIdPointed,
        uint256 pubIdPointed
    ) internal view {
        GateParams memory gateParams = _gateParamsByPublicationByProfile[profileIdPointed][
            pubIdPointed
        ];
        if (
            IToken(gateParams.tokenAddress).balanceOf(IERC721(HUB).ownerOf(profileId)) <
            gateParams.minThreshold
        ) {
            revert NotEnoughBalance();
        }
    }
}
