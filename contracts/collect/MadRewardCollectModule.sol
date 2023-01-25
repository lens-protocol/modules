// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {ICollectModule} from "@aave/lens-protocol/contracts/interfaces/ICollectModule.sol";
import {ModuleBase, Errors} from "@aave/lens-protocol/contracts/core/modules/ModuleBase.sol";
import {ILensHub} from "@aave/lens-protocol/contracts/interfaces/ILensHub.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IMadSBT} from "@madfi/protocol/contracts/interfaces/IMadSBT.sol";

/**
 * @title MadRewardCollectModule is a Lens Collect Module that allows creators to reward their most engaged followers.
 * The relationship between the creator and the follower starts with the creator initializing a post with this module,
 * and creating a MadSBT collection; everyone that collects the post gets a soulbound NFT minted. From that point on,
 * the follower accumulates rewards tokens on that MadSBT for collecting/commenting/mirroring the creator's posts.
 */
contract MadRewardCollectModule is ICollectModule, ModuleBase {
  event InitCollectModule(uint256 profileId, uint256 pubId, uint256 collectionId);

  mapping (uint256 => uint256) public activeCollectionPerProfile; // profileId => collectionId
  mapping (uint256 => mapping (uint256 => uint256)) public activeCollectionPerPubId; // profileId => pubId => collectionId

  IMadSBT public madSBT;

  error NoZeroAddress();
  error NotCollectionCreator();
  error NotFollowing();

  /**
   * @dev contract constructor
   * @param hub: LensHub
   * @param _madSBT: MadSBT contract
   */
  constructor(address hub, address _madSBT) ModuleBase(hub) {
    if (_madSBT == address(0) || hub == address(0)) { revert NoZeroAddress(); }

    madSBT = IMadSBT(_madSBT);
  }

  /**
   * @notice This collect module either (1) creates a MadSBT collection to mint for collectors or (2) validates that
   * the profile is re-using a previous MadSBT collection to reward collectors
   *
   * @param profileId The profile ID of the profile to initialize this module for.
   * @param pubId The publication ID of the post
   * @param data The arbitrary data parameter, decoded into:
   *      uint256 existingCollectionId: An existing MadSBT collection to associate this post's rewards with
   *      string uri: The uri to use for all tokens minted from the collection
   *      uint256 availableSupply: The available supply of tokens
   *
   * @return bytes An abi encoded bytes parameter, which is the same as the passed data parameter.
   */
  function initializePublicationCollectModule(
    uint256 profileId,
    uint256 pubId,
    bytes calldata data
  ) external override onlyHub returns (bytes memory) {
    (
      uint256 existingCollectionId,
      uint256 availableSupply,
      string memory uri
    ) = abi.decode(data, (uint256, uint256, string));

    uint256 _collectionId = existingCollectionId;

    if (existingCollectionId != 0) {
      if (madSBT.creatorProfileId(existingCollectionId) != profileId) revert NotCollectionCreator();

      // nothing else to do
    } else if (existingCollectionId == 0) {
      if (bytes(uri).length == 0 || availableSupply == 0) revert Errors.InitParamsInvalid();

      _collectionId = madSBT.createCollection(
        profileId,
        availableSupply,
        uri
      );

      activeCollectionPerProfile[profileId] = _collectionId;
    }

    activeCollectionPerPubId[profileId][pubId] = _collectionId;

    emit InitCollectModule(profileId, pubId, _collectionId);

    return data;
  }

  /**
   * @dev Process a collect by
   * - if the collector is not following the creator, revert
   * - if the post has an associated collectionId to be minted, attempt to mint it for the collector
   * - else update the reward index for the collector by `madSBT.collectRewardUnit`
   */
  function processCollect(
    uint256, // referrerProfileId
    address collector,
    uint256 profileId,
    uint256 pubId,
    bytes calldata // data
  ) external override onlyHub {
    // must be following the creator
    if (!_isFollowing(profileId, collector)) revert NotFollowing();

    uint256 collectionId = activeCollectionPerPubId[profileId][pubId];

    // attempt to mint the associated MadSBT collection
    if (madSBT.balanceOf(collector, collectionId) == 0) {
      // revert if we are at the supply cap
      if (!madSBT.mint(collector, collectionId, profileId)) revert Errors.CollectNotAllowed();
    } else {
      // simply update the rewards for existing MadSBT holder
      madSBT.handleRewardsUpdate(collector, collectionId, profileId, madSBT.collectRewardUnit());
    }
  }

  /**
   * @dev Return whether the `follower` is following lens profile `profileId`
   * TODO: this will change as of lens v2
   */
  function _isFollowing(uint256 profileId, address follower) internal view returns (bool) {
    address followNFT = ILensHub(HUB).getFollowNFT(profileId);

    return followNFT != address(0) && IERC721(followNFT).balanceOf(follower) != 0;
  }
}
