// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IReferenceModule} from '@aave/lens-protocol/contracts/interfaces/IReferenceModule.sol';
import {ModuleBase, Errors} from '@aave/lens-protocol/contracts/core/modules/ModuleBase.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ILensHub} from '@aave/lens-protocol/contracts/interfaces/ILensHub.sol';
import {DataTypes} from '@aave/lens-protocol/contracts/libraries/DataTypes.sol';
import {FeeModuleBase} from '@aave/lens-protocol/contracts/core/modules/FeeModuleBase.sol';
import {MerkleProof} from '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import {Strings} from '@openzeppelin/contracts/utils/Strings.sol';

import "hardhat/console.sol";

/**
 * @notice A struct for the campaign parameters
 *
 * @param merkleRoot The merkle tree root for the accounts whitelisted for mirror rewards
 * @param currency The ERC20 payment token; must be whitelisted by Lens Protocol
 * @param budget The total amount of `currency` for the mirror reward pool (decrements)
 * @param totalProfiles The total profiles/mirrors the budget is allocated for
 * @param budgetPerProfile The amount of `currency` available per profile as the mirror reward
 */
struct CampaignParams {
  bytes32 merkleRoot;
  address currency;
  uint256 budget;
  uint256 totalProfiles;
  uint256 budgetPerProfile;
}

/**
 * @title TargetedCampaignModule
 *
 * @notice A Lens Reference Module that allows publication creators to incentivize mirrors on their publication for
 * targeted campaigns - based on profile interests. When initializing this module, the creator provides the merkle root
 * for a list of curated profiles and the reward configuration. Whitelisted profiles that mirror the publication receive
 * a portion of the reward pool.
 *
 * NOTE: this contract is ownable in order to set protocol fee configs and withdraw fees accrued
 */
contract TargetedCampaignReferenceModule is ModuleBase, FeeModuleBase, Ownable, IReferenceModule {
  using Strings for uint256;

  error NotEnoughAllowance();
  error NotEnoughBalance();
  error AboveMax();
  error NotFound();

  event TargetedCampaignReferencePublicationCreated(
    uint256 profileId,
    uint256 pubId,
    address currency,
    uint256 budget,
    uint256 budgetPerProfile
  );
  event TargetedCampaignReferencePublicationClosed(
    uint256 profileId,
    uint256 pubId,
    uint256 budgetRemaining
  );

  uint256 public constant PROTOCOL_FEE_BPS_MAX = 2000; // 20%
  uint256 public protocolFeeBps;

  mapping (uint256 => mapping (uint256 => mapping (uint256 => bool))) public campaignRewardClaimed; // profileIdPointed => pubIdPointed => profileId => didClaim
  mapping (address => uint256) public protocolFeesPerCurrency; // token => fees accrued

  mapping (uint256 => mapping (uint256 => CampaignParams)) internal _campaignParamsPerProfilePerPub; // profileId => pubId => campaign

  /**
   * @dev contract constructor
   * @param hub LensHub
   * @param moduleGlobals Module globals
   * @param _protocolFeeBps Protocol fee bps to take on every mirror
   */
  constructor(
    address hub,
    address moduleGlobals,
    uint256 _protocolFeeBps
  ) ModuleBase(hub) FeeModuleBase(moduleGlobals) Ownable() {
    protocolFeeBps = _protocolFeeBps;
  }

  /**
   * @notice Initialize this reference module for the given profile/publication
   *
   * @param profileId The profile ID of the profile creating the pub
   * @param pubId The pub to init this reference module to
   * @param data The arbitrary data parameter, which in this particular module contains data for `CampaignParams`
   *
   * @return bytes Empty bytes.
   */
  function initializeReferenceModule(
    uint256 profileId,
    uint256 pubId,
    bytes calldata data
  ) external override onlyHub returns (bytes memory) {
    CampaignParams memory params = abi.decode(data, (CampaignParams));

    // validate the input
    if (
      !_currencyWhitelisted(params.currency) ||
      params.budget == 0 ||
      (params.budget / params.totalProfiles != params.budgetPerProfile) ||
      params.merkleRoot == bytes32(0)
    ) revert Errors.InitParamsInvalid();

    address account = IERC721(HUB).ownerOf(profileId);
    uint256 protocolFee = getProtocolFee(params.budget);
    uint256 budgetPlusFee = params.budget + protocolFee;

    if (IERC20(params.currency).balanceOf(account) < budgetPlusFee)
      revert NotEnoughBalance();

    if (IERC20(params.currency).allowance(account, address(this)) < budgetPlusFee)
      revert NotEnoughAllowance();

    // transfer the full payment to this contract; we accrue fees
    IERC20(params.currency).transferFrom(account, address(this), budgetPlusFee);

    protocolFeesPerCurrency[params.currency] += protocolFee;
    _campaignParamsPerProfilePerPub[profileId][pubId] = params;

    emit TargetedCampaignReferencePublicationCreated(
      profileId,
      pubId,
      params.currency,
      params.budget,
      params.budgetPerProfile
    );

    return new bytes(0);
  }

  /**
   * @dev Process a mirror by:
   * - do a lookup for the associated campaign params
   * - if there is budget remaining - reward the profile if they provided the proof of their presence in the merkle tree
   * - give a portion of the reward to the whitelisted client
   * - update the reward pool
   */
  function processMirror(
    uint256 profileId,
    uint256 profileIdPointed,
    uint256 pubIdPointed,
    bytes calldata data
  ) external override onlyHub {
    CampaignParams storage params = _campaignParamsPerProfilePerPub[profileIdPointed][pubIdPointed];

    // this catches two cases 1) nothing in storage for this pub and 2) no rewards left to distribute
    if (params.budget == 0) return;

    // has this profile already claimed?
    if (campaignRewardClaimed[profileIdPointed][pubIdPointed][profileId]) return;

    // @TODO: here decode the client and validate is whitelisted before sharing the fee
    (bytes32[] memory merkleProof, uint256 index) = abi.decode(data, (bytes32[], uint256));

    // if the profile is whitelisted to receive rewards
    if (_validateMerkleProof(params.merkleRoot, profileId, index, merkleProof)) {
      console.log("we in this biatch");
      address account = IERC721(HUB).ownerOf(profileId);

      // send the rewards
      IERC20(params.currency).transfer(account, params.budgetPerProfile);

      // update storage
      params.budget = params.budget - params.budgetPerProfile;
      campaignRewardClaimed[profileIdPointed][pubIdPointed][profileId] = true;

      // if no budget remaining, remove it from storage
      if (params.budget == 0) {
        delete _campaignParamsPerProfilePerPub[profileIdPointed][pubIdPointed];

        emit TargetedCampaignReferencePublicationClosed(profileIdPointed, pubIdPointed, 0);
      }
    }
  }

  /**
   * @dev we don't process comments
   */
  function processComment(
    uint256, // profileId
    uint256, // profileIdPointed
    uint256, // pubIdPointed
    bytes calldata // data
  ) external view override onlyHub {}

  /**
   * @notice Allows a publication owner to withdraw the remaining budget for their campaign, if any
   * @param profileId The profile id that created the campaign
   * @param pubId The pub id
   */
  function withdrawBudgetForPublication(uint256 profileId, uint256 pubId) external {
    address account = IERC721(HUB).ownerOf(profileId);

    if (msg.sender != account) revert Errors.NotProfileOwner();

    CampaignParams storage params = _campaignParamsPerProfilePerPub[profileId][pubId];

    if (params.budget == 0) revert NotFound();

    delete _campaignParamsPerProfilePerPub[profileId][pubId];

    IERC20(params.currency).transfer(msg.sender, params.budget);

    emit TargetedCampaignReferencePublicationClosed(profileId, pubId, params.budget);
  }

  /**
   * @notice Returns the remaining budget for a publication's campaign, if any
   * @param profileId The profile id that created the campaign
   * @param pubId The pub id
   */
  function getBudgetRemainingForPublication(uint256 profileId, uint256 pubId) public view returns (uint256) {
    return _campaignParamsPerProfilePerPub[profileId][pubId].budget;
  }

  /**
   * @notice Calculates and returns the protocol fee for the given `budget`
   */
  function getProtocolFee(uint256 budget) public view returns (uint256) {
    return (budget * protocolFeeBps) / 10000;
  }

  /**
   * @notice Allows the contract owner to set the protocol fee bps, provided it's below the defined max
   * @param _protocolFeeBps The new protocol fee bps
   */
  function setProtocolFeeBps(uint256 _protocolFeeBps) external onlyOwner {
    if (_protocolFeeBps > PROTOCOL_FEE_BPS_MAX) revert AboveMax();

    protocolFeeBps = _protocolFeeBps;
  }

  /**
   * @notice Allows the contract owner to withdraw protocol fees for a given `currency`, if any
   * @param currency The currency to withdraw fees for
   */
  function withdrawProtocolFees(address currency) external onlyOwner {
    if (protocolFeesPerCurrency[currency] > 0) {
      IERC20(currency).transfer(msg.sender, protocolFeesPerCurrency[currency]);
    }
  }

  /**
   * @dev Validate whether the given `merkleProof` is in the tree for `merkleRoot`
   */
  function _validateMerkleProof(
    bytes32 merkleRoot,
    uint256 profileId,
    uint256 index,
    bytes32[] memory merkleProof
  ) internal view returns (bool) {
    console.log("_validateMerkleProof");
    console.logBytes32(merkleRoot);
    console.logUint(profileId);
    console.logUint(index);
    console.log("merkleProof array 0,1");
    console.logBytes32(merkleProof[0]);
    console.logBytes32(merkleProof[1]);
    bytes32 node = keccak256(abi.encodePacked(profileId, index));

    return MerkleProof.verify(merkleProof, merkleRoot, node);
  }
}
