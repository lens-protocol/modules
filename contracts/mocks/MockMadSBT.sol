// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@rari-capital/solmate/src/auth/Owned.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IMadSBT} from "@madfi/protocol/contracts/interfaces/IMadSBT.sol";

/**
 * @title MockMadSBT
 * @dev Use with MadRewardCollectModule; keeps track of reward units per collection and its collectors. The actual
 * MadSBT is a modified ERC1155 without transfer functionality, but we can use the ERC1155 for testing
 */
contract MockMadSBT is IMadSBT, ERC1155, Owned {
  error OnlyCollectModule();
  error OnlyTokenOwner();
  error BadTokenOrHost();

  address public collectModule;
  string public name;
  string public symbol;

  uint128 public mintRewardUnit = 100; // reward on MadSBT mint
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
  constructor() Owned(msg.sender) ERC1155("") {
    name = "MadFi SBT";
    symbol = "MAD-SBT";
  }

  /**
   * Creates a new collection with a fixed `uri` across tokens. Can only be called from our collect module.
   * Also creates an SF IDA index using `profileId` as the pointer
   * @param profileId the lens profile collectionId of the collection creator
   * @param _availableSupply The available supply of tokens
   * @param _uri the metadata uri to be used for all tokens minted in this collection
   */
  function createCollection(
    uint256 profileId,
    uint256 _availableSupply,
    string memory _uri
  ) external onlyCollectModule returns (uint256) {
    unchecked { _collectionIdCounter++; }

    collectionData[_collectionIdCounter].availableSupply = _availableSupply;
    collectionData[_collectionIdCounter].creatorId = profileId;
    collectionData[_collectionIdCounter].uri = _uri;

    emit URI(_uri, _collectionIdCounter);

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

    _mint(account, collectionId, 1, ""); // mint them the soulbound nft
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
    if (balanceOf(account, collectionId) == 0) return;

    uint128 currentUnits = _getCurrentRewards(collectionData[collectionId].creatorId, account);

    // increment their share of the rewards
    _handleRewardsUpdate(profileId, account, currentUnits + amount);
  }

  /**
   * @notice Allows the user to burn their token
   * @param collectionId: the token id from a collection
   */
  function burn(uint256 collectionId) external override(IMadSBT) {
    if (balanceOf(msg.sender, collectionId) == 0) revert OnlyTokenOwner();

    _burn(msg.sender, collectionId, 1);

    // remove their share of the rewards
    _handleRewardsUpdate(collectionData[collectionId].creatorId, msg.sender, 0); // @TODO: maybe delete instead?

    unchecked {
      collectionData[collectionId].totalSupply--;
      collectionData[collectionId].totalRedeemed++;
    }
  }

  // @dev not used in this mock
  function distributeRewards(uint256 collectionId, uint256 totalAmount) external onlyOwner {}

  // @dev not used in this mock
  function redeemInterimRewardUnits(uint256) external override {}

  function uri(uint256 collectionId) public view override(IMadSBT, ERC1155) returns (string memory) {
    return collectionData[collectionId].uri;
  }

  function contractURI() external pure returns (string memory) {
    return "";
  }

  function totalSupply(uint256 collectionId) public view returns (uint256) {
    return collectionData[collectionId].totalSupply;
  }

  function availableSupply(uint256 collectionId) public view returns (uint256) {
    return collectionData[collectionId].availableSupply;
  }

  function creatorProfileId(uint256 collectionId) public view returns (uint256) {
    return collectionData[collectionId].creatorId;
  }

  function balanceOf(address account, uint256 collectionId)
    public
    override(IMadSBT, ERC1155)
    view
    returns (uint256)
  {
    return ERC1155.balanceOf(account, collectionId);
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
