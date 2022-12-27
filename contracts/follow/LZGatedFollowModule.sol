// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {ModuleBase, Errors} from "@aave/lens-protocol/contracts/core/modules/ModuleBase.sol";
import {
  FollowValidatorFollowModuleBase
} from "@aave/lens-protocol/contracts/core/modules/follow/FollowValidatorFollowModuleBase.sol";
import {ILensHub} from "@aave/lens-protocol/contracts/interfaces/ILensHub.sol";
import {DataTypes} from "@aave/lens-protocol/contracts/libraries/DataTypes.sol";
import {LzApp} from "../lz/LzApp.sol";

/**
 * @title LZGatedFollowModule
 *
 * @notice A Lens Follow Module that allows profiles to gate their following with ERC20 or ERC721 balances held
 * on other chains.
 */
contract LZGatedFollowModule is FollowValidatorFollowModuleBase, LzApp {
  struct GatedFollowData {
    address tokenContract; // the remote contract to read from
    uint256 balanceThreshold; // result of balanceOf() should be greater than or equal to
    uint16 remoteChainId; // the remote chainId to read against
  }

  event InitFollowModule(uint256 indexed profileId, address tokenContract, uint256 balanceThreshold, uint16 chainId);

  mapping (uint256 => GatedFollowData) public gatedFollowPerProfile; // profileId => gated follow data
  mapping (uint256 => mapping (address => bool)) public validatedFollowers; // profileId => address which has been validated

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
   * @notice Initialize this follow module for the given profile
   *
   * @param profileId The profile ID of the profile to initialize this module for.
   * @param data The arbitrary data parameter, which in this particular module initialization will be just ignored.
   *
   * @return bytes Empty bytes.
   */
  function initializeFollowModule(uint256 profileId, bytes calldata data)
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
    gatedFollowPerProfile[profileId] = GatedFollowData({
      remoteChainId: chainId,
      tokenContract: tokenContract,
      balanceThreshold: balanceThreshold
    });

    emit InitFollowModule(profileId, tokenContract, balanceThreshold, chainId);

    return new bytes(0);
  }

  /**
   * @dev Process a follow by:
   * - checking that we have already validated the follower through our `LZGatedProxy` on a remote chain
   */
  function processFollow(
    address follower,
    uint256 profileId,
    bytes calldata // data
  ) external view override onlyHub {
    if (!validatedFollowers[profileId][follower]) {
      revert Errors.FollowInvalid();
    }
  }

  /**
   * @dev We don't need to execute any additional logic on transfers in this follow module.
   */
  function followModuleTransferHook(
    uint256 profileId,
    address from,
    address to,
    uint256 followNFTTokenId
  ) external override {}

  /**
   * @dev Callback from our `LZGatedProxy` contract deployed on a remote chain, signals that the follow is validated
   * NOTE: this function is actually non-blocking in that it does not explicitly revert and catches external errors
   */
  function _blockingLzReceive(
    uint16 _srcChainId,
    bytes memory _srcAddress,
    uint64 _nonce,
    bytes memory _payload
  ) internal override {
    (
      address token,
      uint256 threshold,
      DataTypes.FollowWithSigData memory followSig
    ) = abi.decode(_payload, (address, uint256, DataTypes.FollowWithSigData));

    uint256 profileId = followSig.profileIds[0];
    GatedFollowData memory data = gatedFollowPerProfile[profileId];

    // validate that remote check was against the contract/threshold defined
    if (data.remoteChainId != _srcChainId || data.balanceThreshold != threshold || data.tokenContract != token) {
      emit MessageFailed(_srcChainId, _srcAddress, _nonce, _payload, 'InvalidRemoteInput');
      return;
    }

    // allow the follow in the callback to #processFollow
    validatedFollowers[profileId][followSig.follower] = true;

    // use the signature to execute the follow
    try ILensHub(HUB).followWithSig(followSig) {}
    catch Error (string memory reason) {
      emit MessageFailed(_srcChainId, _srcAddress, _nonce, _payload, reason);
    }

    delete validatedFollowers[profileId][followSig.follower];
  }
}
