// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {DataTypes} from '@aave/lens-protocol/contracts/libraries/DataTypes.sol';
import {FollowValidationModuleBase} from '@aave/lens-protocol/contracts/core/modules/FollowValidationModuleBase.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {IFollowModule} from '@aave/lens-protocol/contracts/interfaces/IFollowModule.sol';
import {ILensHub} from '@aave/lens-protocol/contracts/interfaces/ILensHub.sol';
import {IReferenceModule} from '@aave/lens-protocol/contracts/interfaces/IReferenceModule.sol';
import {ModuleBase} from '@aave/lens-protocol/contracts/core/modules/ModuleBase.sol';

/**
 * @notice Struct representing the module configuration for certain publication.
 *
 * @param commentsRestricted Indicates if the comment operation is restricted or open to everyone.
 * @param mirrorsRestricted Indicates if the mirror operation is restricted or open to everyone.
 * @param degreesOfSeparation The max degrees of separation allowed for restricted operations.
 */
struct ModuleConfig {
    bool commentsRestricted;
    bool mirrorsRestricted;
    uint8 degreesOfSeparation;
}

/**
 * @title DegreesOfSeparationReferenceModule
 * @author Lens Protocol
 *
 * @notice This reference module allows to set a degree of separation `n`, and then allows to comment/mirror only to
 * profiles that are at most at `n` degrees of separation from the author of the root publication.
 */
contract DegreesOfSeparationReferenceModule is FollowValidationModuleBase, IReferenceModule {
    error InvalidDegreesOfSeparation();
    error OperationDisabled();
    error ProfilePathExceedsDegreesOfSeparation();

    /**
     * @dev Because of the "Six degrees of separation" theory, in the long term, setting up 5, 6 or more degrees of
     * separation will be almost equivalent to turning off the restriction.
     * If we also take into account the gas cost of performing the validations on-chain, makes sense to only support up
     * to 4 degrees of separation.
     */
    uint8 constant MAX_DEGREES_OF_SEPARATION = 4;

    mapping(uint256 => mapping(uint256 => ModuleConfig)) internal _moduleConfigByPubByProfile;

    constructor(address hub) ModuleBase(hub) {}

    /**
     * @notice Initializes data for a given publication being published. This can only be called by the hub.
     *
     * @param profileId The token ID of the profile publishing the publication.
     * @param pubId The associated publication's LensHub publication ID.
     * @param data Arbitrary data passed from the user to be decoded.
     *
     * @return bytes An abi encoded byte array encapsulating the execution's state changes. This will be emitted by the
     * hub alongside the collect module's address and should be consumed by front ends.
     */
    function initializeReferenceModule(
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) external override onlyHub returns (bytes memory) {
        (bool commentsRestricted, bool mirrorsRestricted, uint8 degreesOfSeparation) = abi.decode(
            data,
            (bool, bool, uint8)
        );
        if (degreesOfSeparation > MAX_DEGREES_OF_SEPARATION) {
            revert InvalidDegreesOfSeparation();
        }
        _moduleConfigByPubByProfile[profileId][pubId] = ModuleConfig(
            commentsRestricted,
            mirrorsRestricted,
            degreesOfSeparation
        );
        return data;
    }

    /**
     * @notice Processes a comment action referencing a given publication. This can only be called by the hub.
     *
     * @dev It will apply the degrees of separation restriction if the publication has `commentsRestricted` enabled.
     *
     * @param profileId The token ID of the profile associated with the publication being published.
     * @param profileIdPointed The profile ID of the profile associated the publication being referenced.
     * @param pubIdPointed The publication ID of the publication being referenced.
     * @param data Encoded data containing the array of profile IDs representing the follower path between the owner of
     * the author of the root publication and the profile authoring the comment.
     */
    function processComment(
        uint256 profileId,
        uint256 profileIdPointed,
        uint256 pubIdPointed,
        bytes calldata data
    ) external view override onlyHub {
        if (_moduleConfigByPubByProfile[profileIdPointed][pubIdPointed].commentsRestricted) {
            _validateDegreesOfSeparationRestriction(
                profileId,
                profileIdPointed,
                _moduleConfigByPubByProfile[profileIdPointed][pubIdPointed].degreesOfSeparation,
                abi.decode(data, (uint256[]))
            );
        }
    }

    /**
     * @notice Processes a mirror action referencing a given publication. This can only be called by the hub.
     *
     * @dev It will apply the degrees of separation restriction if the publication has `mirrorsRestricted` enabled.
     *
     * @param profileId The token ID of the profile associated with the publication being published.
     * @param profileIdPointed The profile ID of the profile associated the publication being referenced.
     * @param pubIdPointed The publication ID of the publication being referenced.
     * @param data Encoded data containing the array of profile IDs representing the follower path between the owner of
     * the author of the root publication and the profile authoring the mirror.
     */
    function processMirror(
        uint256 profileId,
        uint256 profileIdPointed,
        uint256 pubIdPointed,
        bytes calldata data
    ) external view override onlyHub {
        if (_moduleConfigByPubByProfile[profileIdPointed][pubIdPointed].mirrorsRestricted) {
            _validateDegreesOfSeparationRestriction(
                profileId,
                profileIdPointed,
                _moduleConfigByPubByProfile[profileIdPointed][pubIdPointed].degreesOfSeparation,
                abi.decode(data, (uint256[]))
            );
        }
    }

    /**
     * @notice Gets the module configuration for the given publication.
     *
     * @param profileId The token ID of the profile publishing the publication.
     * @param pubId The associated publication's LensHub publication ID.
     *
     * @return ModuleConfig The module configuration set for the given publication.
     */
    function getModuleConfig(uint256 profileId, uint256 pubId)
        external
        view
        returns (ModuleConfig memory)
    {
        return _moduleConfigByPubByProfile[profileId][pubId];
    }

    /**
     * @dev The data has encoded an array of integers, each integer is a profile ID, the whole array represents a path
     * of `n` profiles.
     *
     * Let's define `X --> Y` as `The owner of X is following Y`. Then, being `path[i]` the i-th profile in the path,
     * the following condition must be met for a given path of `n` profiles:
     *
     *    profileIdPointed --> path[0] --> path[1] --> path[2] --> ... --> path[n-2] --> path[n-1] --> profileId
     *
     * @param profileId The token ID of the profile associated with the publication being published.
     * @param profileIdPointed The profile ID of the profile associated the publication being referenced.
     * @param degreesOfSeparation The degrees of separations configured for the given publication.
     * @param profilePath The array of profile IDs representing the follower path between the owner of the author of the
     * root publication and the profile authoring the comment.
     */
    function _validateDegreesOfSeparationRestriction(
        uint256 profileId,
        uint256 profileIdPointed,
        uint8 degreesOfSeparation,
        uint256[] memory profilePath
    ) internal view {
        if (degreesOfSeparation == 0) {
            revert OperationDisabled();
        }
        if (profilePath.length > degreesOfSeparation - 1) {
            revert ProfilePathExceedsDegreesOfSeparation();
        }
        address follower = IERC721(HUB).ownerOf(profileIdPointed);
        if (profilePath.length > 0) {
            // Checks the owner of the profile authoring the root publication follows the first profile in the path.
            // In the previous notation: profileIdPointed --> path[0]
            _checkFollowValidity(profilePath[0], follower);
            // Checks each profile owner in the path is following the profile coming next, according the order.
            // In the previous notaiton: path[0] --> path[1] --> path[2] --> ... --> path[n-2] --> path[n-1]
            uint256 i;
            while (i < profilePath.length - 1) {
                follower = IERC721(HUB).ownerOf(profilePath[i]);
                unchecked {
                    ++i;
                }
                _checkFollowValidity(profilePath[i], follower);
            }
            // Checks the last profile in the path follows the profile commenting/mirroring.
            // In the previous notation: path[n-1] --> profileId
            follower = IERC721(HUB).ownerOf(profilePath[i]);
            _checkFollowValidity(profileId, follower);
        } else {
            // Checks the owner of the profile authoring the root publication follows the profile commenting/mirroring.
            // In the previous notation: profileIdPointed --> profileId
            _checkFollowValidity(profileId, follower);
        }
    }
}
