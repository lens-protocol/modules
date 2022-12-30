// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {ModuleBase, Errors} from "@aave/lens-protocol/contracts/core/modules/ModuleBase.sol";
import {ICollectModule} from '@aave/lens-protocol/contracts/interfaces/ICollectModule.sol';
import {FollowValidationModuleBase} from '@aave/lens-protocol/contracts/core/modules/FollowValidationModuleBase.sol';
import {ILensHub} from "@aave/lens-protocol/contracts/interfaces/ILensHub.sol";
import {DataTypes} from "@aave/lens-protocol/contracts/libraries/DataTypes.sol";
import {NonblockingLzApp} from "../lz/NonblockingLzApp.sol";

/**
 * @title LZGatedCollectModule
 *
 * @notice A Lens Collect Module that allows profiles to gate who can collect their post with ERC20 or ERC721 balances
 * held on other chains.
 */
contract LZGatedCollectModule is FollowValidationModuleBase, ICollectModule, NonblockingLzApp {
  struct GatedCollectData {
    address tokenContract; // the remote contract to read from
    uint256 balanceThreshold; // result of balanceOf() should be greater than or equal to
    uint16 remoteChainId; // the remote chainId to read against
  }

  event InitCollectModule(
    uint256 indexed profileId,
    uint256 indexed pubId,
    address tokenContract,
    uint256 balanceThreshold,
    uint16 chainId
  );

  mapping (uint256 => mapping (uint256 => GatedCollectData)) public gatedCollectDataPerPub; // profileId => pubId => gated collect data
  mapping (uint256 => mapping (uint256 => mapping (address => bool))) public validatedCollectors; // profileIdPointed => pubId => profiles which have been validated

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
  ) ModuleBase(hub) NonblockingLzApp(_lzEndpoint, msg.sender, remoteChainIds, remoteProxies) {}

  /**
   * @notice Initialize this collect module for the given profile/publication
   *
   * @param profileId The profile ID of the profile creating the pub
   * @param pubId The pub to init this reference module to
   * @param data The arbitrary data parameter, which in this particular module initialization will be just ignored.
   *
   * @return bytes Empty bytes.
   */
  function initializePublicationCollectModule(
    uint256 profileId,
    uint256 pubId,
    bytes calldata data
  ) external override onlyHub returns (bytes memory) {
    (
      address tokenContract,
      uint256 balanceThreshold,
      uint16 chainId
    ) = abi.decode(data, (address, uint256, uint16));

    if (address(tokenContract) == address(0) || _lzRemoteLookup[chainId].length == 0) {
      revert Errors.InitParamsInvalid();
    }

    // anyone can read this data before attempting to follow the given profile
    gatedCollectDataPerPub[profileId][pubId] = GatedCollectData({
      remoteChainId: chainId,
      tokenContract: tokenContract,
      balanceThreshold: balanceThreshold
    });

    emit InitCollectModule(profileId, pubId, tokenContract, balanceThreshold, chainId);

    return new bytes(0);
  }

  /**
   * @dev Process a collect by:
   * - checking that we have already validated the collector through our `LZGatedProxy` on a remote chain
   */
  function processCollect(
    uint256, // referrerProfileId
    address collector,
    uint256 profileId,
    uint256 pubId,
    bytes calldata // data
  ) external view override onlyHub {
    if (!validatedCollectors[profileId][pubId][collector]) {
      revert Errors.CollectNotAllowed();
    }
  }

  /**
   * @dev Callback from our `LZGatedProxy` contract deployed on a remote chain, signals that the collect is validated
   */
  function _nonblockingLzReceive(
    uint16 _srcChainId,
    bytes memory _srcAddress,
    uint64 _nonce,
    bytes memory _payload
  ) internal override {
    (
      address token,
      uint256 threshold,
      DataTypes.CollectWithSigData memory collectSig
    ) = abi.decode(_payload, (address, uint256, DataTypes.CollectWithSigData));

    GatedCollectData memory data = gatedCollectDataPerPub[collectSig.profileId][collectSig.pubId];

    // validate that remote check was against the contract/threshold defined
    if (data.remoteChainId != _srcChainId || data.balanceThreshold != threshold || data.tokenContract != token) {
      revert InvalidRemoteInput();
    }

    // @TODO: hash the vars vs deeply nested?
    validatedCollectors[collectSig.profileId][collectSig.pubId][collectSig.collector] = true;

    // use the signature to execute the collect
    ILensHub(HUB).collectWithSig(collectSig);

    delete validatedCollectors[collectSig.profileId][collectSig.pubId][collectSig.collector];
  }
}
