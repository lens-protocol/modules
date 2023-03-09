// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@rari-capital/solmate/src/auth/Owned.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IMadSBT} from "@madfi/protocol/contracts/interfaces/IMadSBT.sol";

/**
 * @title MockMadSBT
 * @dev Use with MadRewardCollectModule; keeps track of reward units per collection and its collectors. The actual
 * MadSBT is a modified ERC721 without transfer functionality, but we can use the ERC721 for testing
 */
contract MockMadSBT is IMadSBT, ERC721, Owned {
  error OnlyCollectModule();
  error OnlyTokenOwner();
  error BadTokenOrHost();

  address public collectModule;
  uint256 public genesisProfileId = 1; // // MadFi Collection

  uint128 public createRewardUnit = 100; // reward on #createCollection + Bounty create (only on 1st bid accepted)
  uint128 public mintRewardUnit = 25; // reward on MadSBT mint
  uint128 public collectRewardUnit = 10; // reward on collect

  mapping (uint256 => CollectionData) public collectionData; // collectionId => MadSBT collection data

  uint256 internal _collectionIdCounter; // counter for collections; 1-based

  mapping (address => mapping (uint256 => uint128)) internal _interimRewardUnits;

  modifier onlyCollectModule() {
    if (msg.sender != collectModule) revert OnlyCollectModule();
    _;
  }

  /**
   * @dev contract constructor
   */
  constructor() ERC721("Mad Finance SBT", "MadSBT") Owned(msg.sender) {}

  /**
   * Creates a new collection with a fixed `uri` across tokens. Can only be called from our collect module.
   * Also creates an SF IDA index using `profileId` as the pointer
   * @param creator the collection creator
   * @param profileId the lens profile collectionId of the collection creator
   * @param _availableSupply The available supply of tokens
   * @param _uri the metadata uri to be used for all tokens minted in this collection
   */
  function createCollection(
    address creator,
    uint256 profileId,
    uint256 _availableSupply,
    string memory _uri
  ) external onlyCollectModule returns (uint256) {
    unchecked { _collectionIdCounter++; }

    collectionData[_collectionIdCounter].availableSupply = _availableSupply;
    collectionData[_collectionIdCounter].creatorId = profileId;
    collectionData[_collectionIdCounter].uri = _uri;

    _handleRewardsUpdate(genesisProfileId, creator, createRewardUnit);

    return _collectionIdCounter;
  }

  /**
   * @notice Attempts to mint a single token for the `account`, depending of the profile's active collection.
   * @param account the account to mint the nft for
   * @param collectionId the token to mint
   * @param profileId the lens profile id of the collection creator
   */
  function mint(
    address account,
    uint256 collectionId,
    uint256 profileId
  ) external onlyCollectModule returns (bool success) {
    // if we're at the supply cap, do not mint
    uint256 _supply = collectionData[collectionId].totalSupply + collectionData[collectionId].totalRedeemed;
    if (_supply + 1 > collectionData[collectionId].availableSupply) return false;

    unchecked { collectionData[collectionId].totalSupply++; }

    _mint(account, 1); // mint them the soulbound nft
    _handleRewardsUpdate(profileId, account, mintRewardUnit); // set their share of the rewards

    return true;
  }

  /**
   * @notice Updates the rewards counter for `account` at index ``
   * @param account the account to update the rewards for
   * @param collectionId the collection id
   * @param profileId the lens profile id of the collection creator
   * @param amount the amount to increment the reward counter by
   */
  function handleRewardsUpdate(
    address account,
    uint256 collectionId,
    uint256 profileId,
    uint128 amount
  ) external onlyCollectModule {
    uint128 currentUnits = _getCurrentRewards(collectionData[collectionId].creatorId, account);

    // it will be 0 if they don't own the NFT
    if (currentUnits != 0) {
      // increment their share of the rewards
      _handleRewardsUpdate(profileId, account, currentUnits + amount);
    }
  }

  /**
   * @notice Allows the user to burn their token
   * @param tokenId: the token id from a collection
   */
  function burn(uint256 tokenId) external override(IMadSBT) {
    if (ownerOf(tokenId) != msg.sender) revert OnlyTokenOwner();

    _burn(tokenId);

    // remove their share of the rewards
    _handleRewardsUpdate(collectionData[tokenId].creatorId, msg.sender, 0); // @TODO: maybe delete instead?

    unchecked {
      collectionData[tokenId].totalSupply--;
      collectionData[tokenId].totalRedeemed++;
    }
  }

  // @dev not used in this mock
  function distributeRewards(uint256 collectionId, uint256 totalAmount) external onlyOwner {}

  // @dev not used in this mock
  function redeemInterimRewardUnits(uint256) external override {}

  function contractURI() external pure returns (string memory) {
    return "";
  }

  function creatorProfileId(uint256 collectionId) public view returns (uint256) {
    return collectionData[collectionId].creatorId;
  }

  /**
   * @notice Returns true if the `account` has minted a token from `collectionId`
   */
  function hasMinted(address account, uint256 collectionId) public view returns (bool) {
    if (collectionId > _collectionIdCounter) return false;

    if (_getCurrentRewards(collectionData[collectionId].creatorId, account) == 0) return false;

    return true;
  }

  function rewardUnitsOf(address account, uint256 collectionId) public view returns (uint128) {
    return _getCurrentRewards(collectionData[collectionId].creatorId, account);
  }

  function setCollectModule(address _collectModule) external onlyOwner {
    collectModule = _collectModule;
  }

  function setMintRewardUnit(uint128 _mintRewardUnit) external onlyOwner {
    mintRewardUnit = _mintRewardUnit;
  }

  function setCollectRewardUnit(uint128 _collectRewardUnit) external onlyOwner {
    collectRewardUnit = _collectRewardUnit;
  }

  function _handleRewardsUpdate(uint256 indexId, address subscriber, uint128 newUnits) internal {
    _interimRewardUnits[subscriber][indexId] = newUnits;
  }

  function _getCurrentRewards(uint256 indexId, address subscriber) internal view returns (uint128 units) {
    units = _interimRewardUnits[subscriber][indexId];
  }
}
