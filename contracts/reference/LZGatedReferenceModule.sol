// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IReferenceModule} from '@aave/lens-protocol/contracts/interfaces/IReferenceModule.sol';
import {ModuleBase, Errors} from "@aave/lens-protocol/contracts/core/modules/ModuleBase.sol";
import {FollowValidationModuleBase} from '@aave/lens-protocol/contracts/core/modules/FollowValidationModuleBase.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {ILensHub} from "@aave/lens-protocol/contracts/interfaces/ILensHub.sol";
import {DataTypes} from "@aave/lens-protocol/contracts/libraries/DataTypes.sol";
import {LzApp} from "../lz/LzApp.sol";

/**
 * @title LZGatedReferenceModule
 *
 * @notice A Lens Reference Module that allows publication creators to gate who can comment/mirror their post with
 * ERC20 or ERC721 balances held on other chains.
 */
contract LZGatedReferenceModule is FollowValidationModuleBase, IReferenceModule, LzApp {
  struct GatedReferenceData {
    address tokenContract; // the remote contract to read from
    uint256 balanceThreshold; // result of balanceOf() should be greater than or equal to
    uint16 remoteChainId; // the remote chainId to read against
  }

  event InitReferenceModule(uint256 indexed profileId, uint256 indexed pubId, address tokenContract, uint256 balanceThreshold, uint16 chainId);

  error CommentOrMirrorInvalid();

  mapping (uint256 => mapping (uint256 => GatedReferenceData)) public gatedReferenceDataPerPub; // profileId => pubId => gated reference data
  mapping (uint256 => mapping (uint256 => mapping (uint256 => bool))) public validatedReferencers; // profileIdPointed => pubId => profiles which have been validated

  /**
   * @dev contract constructor
   * @param hub LensHub
   * @param _lzEndpoint: LayerZero endpoint on this chain to relay messages
   * @param remoteChainIds: whitelisted destination chain ids (supported by LayerZero)
   * @param remoteProxies: proxy destination contracts (deployed by us)
   */
  constructor(
    address hub,
    address _lzEndpoint,
    uint16[] memory remoteChainIds,
    bytes[] memory remoteProxies
  ) ModuleBase(hub) LzApp(_lzEndpoint, msg.sender, remoteChainIds, remoteProxies) {}

  /**
   * @notice Initialize this reference module for the given profile/publication
   *
   * @param profileId The profile ID of the profile creating the pub
   * @param pubId The pub to init this reference module to
   * @param data The arbitrary data parameter, which in this particular module initialization will be just ignored.
   *
   * @return bytes Empty bytes.
   */
  function initializeReferenceModule(uint256 profileId, uint256 pubId, bytes calldata data)
    external
    override
    onlyHub
    returns (bytes memory)
  {
    (
      address tokenContract,
      uint256 balanceThreshold,
      uint16 chainId
    ) = abi.decode(data, (address, uint256, uint16));

    if (address(tokenContract) == address(0) || _lzRemoteLookup[chainId].length == 0) {
      revert Errors.InitParamsInvalid();
    }

    // anyone can read this data before attempting to follow the given profile
    gatedReferenceDataPerPub[profileId][pubId] = GatedReferenceData({
      remoteChainId: chainId,
      tokenContract: tokenContract,
      balanceThreshold: balanceThreshold
    });

    emit InitReferenceModule(profileId, pubId, tokenContract, balanceThreshold, chainId);

    return new bytes(0);
  }

  /**
   * @dev Process a comment by:
   * - checking that we have already validated the commentor through our `LZGatedProxy` on a remote chain
   */
  function processComment(
    uint256 profileId,
    uint256 profileIdPointed,
    uint256 pubIdPointed,
    bytes calldata // data
  ) external view override onlyHub {
    if (!validatedReferencers[profileIdPointed][pubIdPointed][profileId]) {
      revert CommentOrMirrorInvalid();
    }
  }

  /**
   * @dev Process a mirror by:
   * - checking that we have already validated the mirrorer through our `LZGatedProxy` on a remote chain
   */
  function processMirror(
    uint256 profileId,
    uint256 profileIdPointed,
    uint256 pubIdPointed,
    bytes calldata // data
  ) external view override onlyHub {
    if (!validatedReferencers[profileIdPointed][pubIdPointed][profileId]) {
      revert CommentOrMirrorInvalid();
    }
  }

  /**
   * @dev Callback from our `LZGatedProxy` contract deployed on a remote chain, signals that the comment/mirror
   * is validated
   * NOTE: this function is actually non-blocking in that it does not explicitly revert and catches external errors
   */
  function _blockingLzReceive(
    uint16 _srcChainId,
    bytes memory _srcAddress,
    uint64 _nonce,
    bytes memory _payload
  ) internal override {
    (bool isComment,,,) = abi.decode(_payload, (bool, address, uint256, bytes));

    // parse the payload for either #commentWithSig or #mirrorWithSig
    string memory error = isComment ? _handleComment(_srcChainId, _payload) : _handleMirror(_srcChainId, _payload);

    if (bytes(error).length > 0) {
      emit MessageFailed(_srcChainId, _srcAddress, _nonce, _payload, error);
    }
  }

  /**
   * @dev Decodes the `payload` for Lens#commentWithSig
   * @return error an error string if the call failed, else empty string
   */
  function _handleComment(uint16 _srcChainId, bytes memory _payload) internal returns (string memory error) {
    (,address token, uint256 threshold, DataTypes.CommentWithSigData memory commentSig) = abi.decode(
      _payload,
      (bool, address, uint256, DataTypes.CommentWithSigData)
    );

    GatedReferenceData memory data = gatedReferenceDataPerPub[commentSig.profileIdPointed][commentSig.pubIdPointed];

    // validate that remote check was against the contract/threshold defined
    if (data.remoteChainId != _srcChainId || data.balanceThreshold != threshold || data.tokenContract != token) {
      return error = "InvalidRemoteInput";
    }

    // @TODO: hash the vars vs deeply nested?
    validatedReferencers[commentSig.profileIdPointed][commentSig.pubIdPointed][commentSig.profileId] = true;

    try ILensHub(HUB).commentWithSig(commentSig) {
      error = "";
    } catch Error (string memory reason) {
      error = reason;
    }

    delete validatedReferencers[commentSig.profileIdPointed][commentSig.pubIdPointed][commentSig.profileId];
  }

  /**
   * @dev Decodes the `payload` for Lens#mirrorWithSig
   * @return error an error string if the call failed, else empty string
   */
  function _handleMirror(uint16 _srcChainId, bytes memory _payload) internal returns (string memory error) {
    (,address token, uint256 threshold, DataTypes.MirrorWithSigData memory mirrorSig) = abi.decode(
      _payload,
      (bool, address, uint256, DataTypes.MirrorWithSigData)
    );

    GatedReferenceData memory data = gatedReferenceDataPerPub[mirrorSig.profileIdPointed][mirrorSig.pubIdPointed];

    // validate that remote check was against the contract/threshold defined
    if (data.remoteChainId != _srcChainId || data.balanceThreshold != threshold || data.tokenContract != token) {
      return error = "InvalidRemoteInput";
    }

    // @TODO: hash the vars vs deeply nested?
    validatedReferencers[mirrorSig.profileIdPointed][mirrorSig.pubIdPointed][mirrorSig.profileId] = true;

    try ILensHub(HUB).mirrorWithSig(mirrorSig) {
      error = "";
    } catch Error (string memory reason) {
      error = reason;
    }

    delete validatedReferencers[mirrorSig.profileIdPointed][mirrorSig.pubIdPointed][mirrorSig.profileId];
  }
}
