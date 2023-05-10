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

/**
 * @notice A struct for the campaign parameters
 *
 * @param merkleRoot The merkle tree root for the accounts whitelisted for mirror rewards
 * @param currency The ERC20 payment token; must be whitelisted by Lens Protocol
 * @param budget The total amount of `currency` for the mirror reward pool (decrements)
 * @param totalProfiles The total profiles/mirrors the budget is allocated for
 * @param budgetPerMirror The amount of `currency` available per profile as the mirror reward
 * @param clientFees The total amount of `currency` reserved for client fees (decrements)
 * @param clientFeePerMirror The amount of `currency` available as the client fee on each mirror
 */
struct CampaignParams {
  bytes32 merkleRoot;
  address currency;
  uint256 budget;
  uint256 totalProfiles;
  uint256 budgetPerMirror;
  uint256 clientFees;
  uint256 clientFeePerMirror;
}

/**
 * @title TargetedCampaignReferenceModule
 * @author Carlos Beltran <carlos@madfinance.xyz>
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
  error OnlyWhitelistedClients();

  event TargetedCampaignReferencePublicationCreated(
    uint256 profileId,
    uint256 pubId,
    address currency,
    uint256 budget,
    uint256 budgetPerMirror,
    uint256 clientFeePerMirror
  );
  event TargetedCampaignReferencePublicationClosed(
    uint256 profileId,
    uint256 pubId,
    uint256 budgetRemainingPlusFees
  );
  event SetProtocolFeeBps(uint256 value);
  event SetClientFeeBps(uint256 value);
  event SetClientWhitelist(address client, bool value);
  event WithdrawProtocolFees(address currency, uint256 value);
  event WithdrawClientFees(address client, address currency, uint256 value);

  uint256 public constant PROTOCOL_FEE_BPS_MAX = 2000; // 20%
  uint256 public constant CLIENT_FEE_BPS_MAX = 1000; // 10%
  uint256 public protocolFeeBps;
  uint256 public clientFeeBps;

  mapping (uint256 => mapping (uint256 => mapping (uint256 => bool))) public campaignRewardClaimed; // profileIdPointed => pubIdPointed => profileId => didClaim
  mapping (address => uint256) public protocolFeesPerCurrency; // token => fees accrued
  mapping (address => mapping (address => uint256)) public clientFeesPerCurrency; // address => token => fees accrued
  mapping (address => bool) public whitelistedClients; // address => isWhitelisted

  mapping (uint256 => mapping (uint256 => CampaignParams)) internal _campaignParamsPerProfilePerPub; // profileId => pubId => campaign

  /**
   * @dev contract constructor
   * @param hub LensHub
   * @param moduleGlobals Module globals
   * @param _protocolFeeBps Protocol fee bps to take on the campaign budget
   * @param _protocolFeeBps Client fee bps to take on the campaign budget
   */
  constructor(
    address hub,
    address moduleGlobals,
    uint256 _protocolFeeBps,
    uint256 _clientFeeBps
  ) ModuleBase(hub) FeeModuleBase(moduleGlobals) Ownable() {
    protocolFeeBps = _protocolFeeBps;
    clientFeeBps = _clientFeeBps;

    emit SetProtocolFeeBps(_protocolFeeBps);
    emit SetClientFeeBps(_clientFeeBps);
  }

  /**
   * @notice Initialize this reference module for the given profile/publication
   *
   * @param profileId The profile ID of the profile creating the pub
   * @param pubId The pub to init this reference module to
   * @param data The arbitrary data parameter, which in this particular module contains some data for `CampaignParams`
   *
   * @return bytes Empty bytes.
   */
  function initializeReferenceModule(
    uint256 profileId,
    uint256 pubId,
    bytes calldata data
  ) external override onlyHub returns (bytes memory) {
    (
      bytes32 merkleRoot,
      address currency,
      uint256 budget,
      uint256 totalProfiles
    ) = abi.decode(data, (bytes32, address, uint256, uint256));

    _validateInitParams(merkleRoot, currency, budget, totalProfiles);

    address account = IERC721(HUB).ownerOf(profileId);
    uint256 protocolFee = getProtocolFee(budget);
    uint256 clientFee = getClientFee(budget);
    uint256 budgetPlusFees = budget + protocolFee + clientFee;

    _validateBalanceAndAllowance(account, currency, budgetPlusFees);

    uint256 budgetPerMirror = budget / totalProfiles;
    uint256 clientFeePerMirror = clientFee / totalProfiles;

    _storeCampaignParams(
      profileId,
      pubId,
      merkleRoot,
      currency,
      budget,
      totalProfiles,
      budgetPerMirror,
      clientFee,
      clientFeePerMirror
    );

    // transfer the full payment to this contract; we accrue fees
    IERC20(currency).transferFrom(account, address(this), budgetPlusFees);
    protocolFeesPerCurrency[currency] += protocolFee;

    emit TargetedCampaignReferencePublicationCreated(
      profileId,
      pubId,
      currency,
      budget,
      budgetPerMirror,
      clientFeePerMirror
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

    // if they chose not to include data, just process the mirror. if they include malformed data, that's on them
    if (data.length == 0) return;

    // has this profile already claimed?
    if (campaignRewardClaimed[profileIdPointed][pubIdPointed][profileId]) return;

    // decode input
    (
      bytes32[] memory merkleProof,
      uint256 index,
      address clientAddress
    ) = abi.decode(data, (bytes32[], uint256, address));

    // if the profile is whitelisted to receive rewards
    if (_validateMerkleProof(params.merkleRoot, profileId, index, merkleProof)) {
      address account = IERC721(HUB).ownerOf(profileId);

      // send the rewards
      IERC20(params.currency).transfer(account, params.budgetPerMirror);

      // process the client fee, if any and if address is whitelisted
      if (params.clientFees > 0 && whitelistedClients[clientAddress]) {
        clientFeesPerCurrency[clientAddress][params.currency] += params.clientFeePerMirror;

        params.clientFees = params.clientFees - params.clientFeePerMirror;
      }

      // update storage
      params.budget = params.budget - params.budgetPerMirror;
      campaignRewardClaimed[profileIdPointed][pubIdPointed][profileId] = true;

      // if no budget remaining, remove it from storage
      if (params.budget == 0) {
        // keep the unclaimed client fees
        if (params.clientFees > 0) {
          protocolFeesPerCurrency[params.currency] += params.clientFees;
        }

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

    CampaignParams memory params = _campaignParamsPerProfilePerPub[profileId][pubId];

    if (params.budget == 0) revert NotFound();

    delete _campaignParamsPerProfilePerPub[profileId][pubId];

    uint256 protocolFee = getProtocolFee(params.budget); // the owed fees for the remaining budget
    uint256 budgetPlusFees = params.budget + params.clientFees + protocolFee;

    IERC20(params.currency).transfer(msg.sender, budgetPlusFees);

    emit TargetedCampaignReferencePublicationClosed(profileId, pubId, budgetPlusFees);
  }

  // @TODO: logImpressionWithSig

  /**
   * @notice Returns the remaining budget for a publication's campaign, if any
   * @param profileId The profile id that created the campaign
   * @param pubId The pub id
   */
  function getBudgetRemainingForPublication(uint256 profileId, uint256 pubId) public view returns (uint256) {
    return _campaignParamsPerProfilePerPub[profileId][pubId].budget;
  }

  /**
   * @notice Returns the client fee per mirror for a publication
   * @param profileId The profile id that created the campaign
   * @param pubId The pub id
   */
  function getClientFeePerMirrorForPublication(uint256 profileId, uint256 pubId) public view returns (uint256) {
    return _campaignParamsPerProfilePerPub[profileId][pubId].clientFeePerMirror;
  }

  /**
   * @notice Returns the merkle root for a publication's campaign, if any
   * @param profileId The profile id that created the campaign
   * @param pubId The pub id
   */
  function getMerkleRootForPublication(uint256 profileId, uint256 pubId) public view returns (bytes32) {
    return _campaignParamsPerProfilePerPub[profileId][pubId].merkleRoot;
  }

  /**
   * @notice Calculates and returns the protocol fee for the given `budget`
   */
  function getProtocolFee(uint256 budget) public view returns (uint256) {
    return (budget * protocolFeeBps) / 10000;
  }

  /**
   * @notice Calculates and returns the client fee for the given `budget`; this is the incentive for lens apps to
   * feature the promoted publications
   */
  function getClientFee(uint256 budget) public view returns (uint256) {
    if (clientFeeBps == 0) return 0;

    return (budget * clientFeeBps) / 10000;
  }

  /**
   * @notice Allows the contract owner to set the protocol fee bps, provided it's below the defined max
   * @param _protocolFeeBps The new protocol fee bps
   */
  function setProtocolFeeBps(uint256 _protocolFeeBps) external onlyOwner {
    if (_protocolFeeBps > PROTOCOL_FEE_BPS_MAX) revert AboveMax();

    protocolFeeBps = _protocolFeeBps;

    emit SetProtocolFeeBps(_protocolFeeBps);
  }

  /**
   * @notice Allows the contract owner to set the client fee bps, provided it's below the defined max
   * @param _clientFeeBps The new client fee bps
   */
  function setClientFeeBps(uint256 _clientFeeBps) external onlyOwner {
    if (_clientFeeBps > CLIENT_FEE_BPS_MAX) revert AboveMax();

    clientFeeBps = _clientFeeBps;

    emit SetClientFeeBps(_clientFeeBps);
  }

  /**
   * @notice Allows the contract owner toggle the whitelisting of a lens client for fees
   * @param client The lens client
   * @param isWhitelisted Whether the given client can claim mirror fees
   */
  function setClientWhitelist(address client, bool isWhitelisted) external onlyOwner {
    whitelistedClients[client] = isWhitelisted;

    emit SetClientWhitelist(client, isWhitelisted);
  }

  /**
   * @notice Allows whitelisted clients to withdraw their fees for a given `currency`, if any
   * @param currency The currency to withdraw fees for
   */
  function withdrawClientFees(address currency) external {
    if (!whitelistedClients[msg.sender]) revert OnlyWhitelistedClients();

    if (clientFeesPerCurrency[msg.sender][currency] > 0) {
      uint256 fees = clientFeesPerCurrency[msg.sender][currency];

      clientFeesPerCurrency[msg.sender][currency] = 0;

      IERC20(currency).transfer(msg.sender, fees);

      emit WithdrawClientFees(msg.sender, currency, fees);
    }
  }

  /**
   * @notice Allows the contract owner to withdraw protocol fees for a given `currency`, if any
   * @param currency The currency to withdraw fees for
   */
  function withdrawProtocolFees(address currency) external onlyOwner {
    if (protocolFeesPerCurrency[currency] > 0) {
      uint256 fees = protocolFeesPerCurrency[currency];

      protocolFeesPerCurrency[currency] = 0;

      IERC20(currency).transfer(msg.sender, fees);

      emit WithdrawProtocolFees(currency, fees);
    }
  }

  /**
   * @dev Reverts if any of the module init params are invalid, ex: `currency` not whitelisted or empty values
   */
  function _validateInitParams(
    bytes32 merkleRoot,
    address currency,
    uint256 budget,
    uint256 totalProfiles
  ) private view {
    if (
      budget == 0 ||
      totalProfiles == 0 ||
      merkleRoot == bytes32(0)
    ) revert Errors.InitParamsInvalid();
  }

  /**
   * @dev Reverts if
   * - `account` does not have the balance to cover the budget + fees
   * - `account` has not approved sufficient allowance
   */
  function _validateBalanceAndAllowance(
    address account,
    address currency,
    uint256 budgetPlusFees
  ) private view {
    if (IERC20(currency).balanceOf(account) < budgetPlusFees)
      revert NotEnoughBalance();

    if (IERC20(currency).allowance(account, address(this)) < budgetPlusFees)
      revert NotEnoughAllowance();
  }

  /**
   * @dev Moves everything needed for `CampaignParams` into storage
   */
  function _storeCampaignParams(
    uint256 profileId,
    uint256 pubId,
    bytes32 merkleRoot,
    address currency,
    uint256 budget,
    uint256 totalProfiles,
    uint256 budgetPerMirror,
    uint256 clientFee,
    uint256 clientFeePerMirror
  ) private {
    _campaignParamsPerProfilePerPub[profileId][pubId] = CampaignParams({
      merkleRoot: merkleRoot,
      currency: currency,
      budget: budget,
      totalProfiles: totalProfiles,
      budgetPerMirror: budgetPerMirror,
      clientFees: clientFee,
      clientFeePerMirror: clientFeePerMirror
    });
  }

  /**
   * @dev Validate whether the given `merkleProof` is in the tree for `merkleRoot`
   */
  function _validateMerkleProof(
    bytes32 merkleRoot,
    uint256 profileId,
    uint256 index,
    bytes32[] memory merkleProof
  ) internal pure returns (bool) {
    bytes32 node = keccak256(abi.encodePacked(profileId, index));

    return MerkleProof.verify(merkleProof, merkleRoot, node);
  }
}
