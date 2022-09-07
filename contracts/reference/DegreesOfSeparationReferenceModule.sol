// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {DataTypes} from '@aave/lens-protocol/contracts/libraries/DataTypes.sol';
import {Errors} from '@aave/lens-protocol/contracts/libraries/Errors.sol';
import {Events} from '@aave/lens-protocol/contracts/libraries/Events.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {IFollowModule} from '@aave/lens-protocol/contracts/interfaces/IFollowModule.sol';
import {ILensHub} from '@aave/lens-protocol/contracts/interfaces/ILensHub.sol';
import {IReferenceModule} from '@aave/lens-protocol/contracts/interfaces/IReferenceModule.sol';
import {ModuleBase} from '@aave/lens-protocol/contracts/core/modules/ModuleBase.sol';

/**
 * @title DegreesOfSeparationReferenceModule
 * @author Lens Protocol
 *
 * @notice This reference module allows to set a degree of separation N, and then allows to comment only to profiles
 * that are at most at N degrees of separation from the author of the root publication.
 */
contract DegreesOfSeparationReferenceModule is ModuleBase, IReferenceModule {
    event DegreesOfSeparationSet(
        uint256 indexed profileId,
        uint256 indexed pubId,
        uint8 degreesOfSeparation
    );

    error InvalidDegreesOfSeparation();
    error CommentsDisabled();
    error InvalidProfilePathLength();

    uint8 public immutable MAX_DEGREES_OF_SEPARATION = 6;
    mapping(uint256 => mapping(uint256 => uint8)) internal _degreesOfSeparationByPubByProfile;

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
    ) external override returns (bytes memory) {
        uint8 degreesOfSeparation = abi.decode(data, (uint8));
        if (degreesOfSeparation > MAX_DEGREES_OF_SEPARATION) {
            revert InvalidDegreesOfSeparation();
        }
        _degreesOfSeparationByPubByProfile[profileId][pubId] = degreesOfSeparation;
        return data;
    }

    /**
     * @notice Processes a comment action referencing a given publication. This can only be called by the hub.
     *
     * @dev The data has encoded an array of integers, each integer is a profile ID, the whole array represents a path
     * of n profiles.
     *
     * Let's define `X --> Y` as `The owner of X is following Y`. Then, being `path[i]` the i-th profile in the path,
     * the following condition must be met:
     *
     *    profileIdPointed --> path[0] --> path[1] --> path[2] --> ... --> path[n-2] --> path[n-1] --> profileId
     *
     * @param profileId The token ID of the profile associated with the publication being published.
     * @param profileIdPointed The profile ID of the profile associated the publication being referenced.
     * @param pubIdPointed The publication ID of the publication being referenced.
     * @param data Encoded data containing the array of profile IDs representing the follower path.
     *
     */
    function processComment(
        uint256 profileId,
        uint256 profileIdPointed,
        uint256 pubIdPointed,
        bytes calldata data
    ) external view override {
        uint8 degreesOfSeparation = _degreesOfSeparationByPubByProfile[profileIdPointed][
            pubIdPointed
        ];
        if (degreesOfSeparation == 0) {
            revert CommentsDisabled();
        }
        uint256[] memory profilePath = abi.decode(data, (uint256[]));
        if (profilePath.length == 0 || profilePath.length > degreesOfSeparation) {
            revert InvalidProfilePathLength();
        }
        address follower;
        // Checks the owner of the profile authoring the root publication follows the first profile in the given path.
        // In the previous notation: profileIdPointed --> path[0]
        follower = IERC721(HUB).ownerOf(profileIdPointed);
        _checkFollowValidity(profilePath[0], follower);
        // Checks each profile owner in the path is following the profile coming next, according the given order.
        // In the previous notaiton: path[0] --> path[1] --> path[2] --> ... --> path[n-2] --> path[n-1]
        for (uint256 i = 0; i < profilePath.length - 1; ) {
            follower = IERC721(HUB).ownerOf(profilePath[i]);
            unchecked {
                ++i;
            }
            _checkFollowValidity(profilePath[i], follower);
        }
        // Checks the last profile in the given path follows the profile authoring the comment.
        // In the previous notation: path[n-1] --> profileId
        follower = IERC721(HUB).ownerOf(profilePath[profilePath.length - 1]);
        _checkFollowValidity(profileId, follower);
    }

    /**
     * @notice Processes a mirror action without putting any restriction on it.
     *
     * @param profileId The token ID of the profile associated with the publication being published.
     * @param profileIdPointed The profile ID of the profile associated the publication being referenced.
     * @param pubIdPointed The publication ID of the publication being referenced.
     * @param data Arbitrary data.
     */
    function processMirror(
        uint256 profileId,
        uint256 profileIdPointed,
        uint256 pubIdPointed,
        bytes calldata data
    ) external view override {
        // Allows anyone to mirror the publication.
    }

    /**
     * @notice Sets the degrees of separation for the given publication.
     *
     * @param profileId The token ID of the profile publishing the publication.
     * @param pubId The associated publication's LensHub publication ID.
     * @param degreesOfSeparation The degrees of separation to set for the given publication.
     */
    function setDegreesOfSeparation(
        uint256 profileId,
        uint256 pubId,
        uint8 degreesOfSeparation
    ) external {
        // TODO: Struct uint248 + bool; One slot and we have a boolean to flag the publication is being used.abi
        //       Otherwise we will be emiting an invalid/useless event.
        if (degreesOfSeparation > MAX_DEGREES_OF_SEPARATION) {
            revert InvalidDegreesOfSeparation();
        }
        _degreesOfSeparationByPubByProfile[profileId][pubId] = degreesOfSeparation;
        emit DegreesOfSeparationSet(profileId, pubId, degreesOfSeparation);
    }

    /**
     * @notice Gets the degrees of separation set for the given publication.
     *
     * @param profileId The token ID of the profile publishing the publication.
     * @param pubId The associated publication's LensHub publication ID.
     *
     * @return uint8 The degrees of separation set for the given publication.
     */
    function getDegreesOfSeparation(uint256 profileId, uint256 pubId)
        external
        view
        returns (uint8)
    {
        return _degreesOfSeparationByPubByProfile[profileId][pubId];
    }

    /**
     * @notice Validates whether a given user is following a given profile.
     *
     * @dev It will revert if the user is not following the profile except the case when the user is the profile owner.
     *
     * @param profileId The ID of the profile that should be followed by the given user.
     * @param user The address of the user that should be following the given profile.
     */
    function _checkFollowValidity(uint256 profileId, address user) internal view {
        DataTypes.ProfileStruct memory followedProfile = ILensHub(HUB).getProfile(profileId);
        bool isFollowing;
        if (followedProfile.followModule != address(0)) {
            isFollowing = IFollowModule(followedProfile.followModule).isFollowing(
                profileId,
                user,
                0
            );
        } else {
            isFollowing =
                followedProfile.followNFT != address(0) &&
                IERC721(followedProfile.followNFT).balanceOf(user) != 0;
        }
        if (!isFollowing && IERC721(HUB).ownerOf(profileId) != user) {
            revert Errors.FollowInvalid();
        }
    }
}
