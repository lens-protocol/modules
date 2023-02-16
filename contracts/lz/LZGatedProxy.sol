// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {DataTypes} from "@aave/lens-protocol/contracts/libraries/DataTypes.sol";
import {LzApp} from "@layerzerolabs/solidity-examples/contracts/lzApp/LzApp.sol";

/**
 * @title LZGatedProxy
 * @notice This contract acts as a proxy for our `LZGated*` Lens modules in order to read
 * token balances from remote contracts on any chain supported by LayerZero.
 */
contract LZGatedProxy is LzApp {
  error InsufficientBalance();
  error NotAccepting();

  bytes public remoteFollowModule; // LZGatedFollowModule
  bytes public remoteReferenceModule; // LZGatedReferenceModule
  bytes public remoteCollectModule; // LZGatedCollectModule
  uint16 public remoteChainId; // lz chain id

  address public zroPaymentAddress; // the address of the ZRO token holder who would pay for all transactions

  bytes internal remoteFollowModulePacked; // remote address concated with local address packed into 40 bytes
  bytes internal remoteReferenceModulePacked;
  bytes internal remoteCollectModulePacked;

  /**
   * @dev contract constructor
   * @param _lzEndpoint: The lz endpoint contract deployed on this chain
   * @param _remoteChainId: remote chain id to be set as the trusted remote
   * @param _remoteFollowModule: trusted follow module on the remote chain
   * @param _remoteReferenceModule: trusted reference module on the remote chain
   * @param _remoteCollectModule: trusted collect module on the remote chain
   */
  constructor(
    address _lzEndpoint,
    uint16 _remoteChainId,
    bytes memory _remoteFollowModule,
    bytes memory _remoteReferenceModule,
    bytes memory _remoteCollectModule
  ) LzApp(_lzEndpoint) {
    remoteFollowModule = _remoteFollowModule;
    remoteReferenceModule = _remoteReferenceModule;
    remoteCollectModule = _remoteCollectModule;
    remoteChainId = _remoteChainId;

    remoteFollowModulePacked = abi.encodePacked(_remoteFollowModule, address(this));
    remoteReferenceModulePacked = abi.encodePacked(_remoteReferenceModule, address(this));
    remoteCollectModulePacked = abi.encodePacked(_remoteCollectModule, address(this));
  }

  /**
   * @notice validate a token balance on this chain before relaying the intent to follow a Lens profile on the remote
   * chain.
   * NOTE: callers of this function MUST pass the exact values for `tokenContract` and `balanceThreshold` returned from
   * the call to LZGatedFollowModule.gatedFollowPerProfile(profileId) - or the transaction on the remote chain WILL
   * revert.
   * @param tokenContract: the ERC20/ERC721 contract set by the `profileId` to check a balance against
   * @param balanceThreshold: the amount of tokens required in order for a successful follow
   * @param lzCustomGasAmount: custom gas amount that is paid for lz.send()
   * @param followSig: the follow signature expected by the LensHub
   */
  function relayFollowWithSig(
    address tokenContract,
    uint256 balanceThreshold,
    uint256 lzCustomGasAmount,
    DataTypes.FollowWithSigData memory followSig
  ) external payable {
    if (!_checkThreshold(followSig.follower, tokenContract, balanceThreshold)) { revert InsufficientBalance(); }

    _lzSend(
      remoteFollowModulePacked,
      abi.encode(
        tokenContract,
        balanceThreshold,
        followSig
      ),
      payable(msg.sender),
      _getAdapterParams(lzCustomGasAmount)
    );
  }

  /**
   * @notice validate a token balance on this chain before relaying the intent to comment on a Lens post on the remote
   * chain.
   * NOTE: callers of this function MUST pass the exact values for `tokenContract` and `balanceThreshold` returned from
   * NOTE: we validate that `sender` is the owner of `commentSig.profileId` on the remote chain for sanity
   * the call to LZGatedReferenceModule.gatedReferenceDataPerPub(profileIdPointed, pubIdPointed) - or the transaction
   * on the remote chain WILL revert.
   * @param sender: the account wishing to perform the comment action
   * @param tokenContract: the ERC20/ERC721 contract set by the `profileId` to check a balance against
   * @param balanceThreshold: the amount of tokens required in order for a successful follow
   * @param lzCustomGasAmount: custom gas amount that is paid for lz.send()
   * @param commentSig: the comment signature expected by the LensHub
   */
  function relayCommentWithSig(
    address sender,
    address tokenContract,
    uint256 balanceThreshold,
    uint256 lzCustomGasAmount,
    DataTypes.CommentWithSigData memory commentSig
  ) external payable {
    if (!_checkThreshold(sender, tokenContract, balanceThreshold)) { revert InsufficientBalance(); }

    _lzSend(
      remoteReferenceModulePacked,
      abi.encode(
        true, // isComment
        sender,
        tokenContract,
        balanceThreshold,
        commentSig
      ),
      payable(msg.sender),
      _getAdapterParams(lzCustomGasAmount)
    );
  }

  /**
   * @notice validate a token balance on this chain before relaying the intent to mirror a Lens post on the remote
   * chain.
   * NOTE: callers of this function MUST pass the exact values for `tokenContract` and `balanceThreshold` returned from
   * NOTE: we validate that `sender` is the owner of `mirrorSig.profileId` on the remote chain for sanity
   * the call to LZGatedReferenceModule.gatedReferenceDataPerPub(profileIdPointed, pubIdPointed) - or the transaction
   * on the remote chain WILL revert.
   * @param sender: the account wishing to perform the mirror action
   * @param tokenContract: the ERC20/ERC721 contract set by the `profileId` to check a balance against
   * @param balanceThreshold: the amount of tokens required in order for a successful follow
   * @param lzCustomGasAmount: custom gas amount that is paid for lz.send()
   * @param mirrorSig: the mirror signature expected by the LensHub
   */
  function relayMirrorWithSig(
    address sender,
    address tokenContract,
    uint256 balanceThreshold,
    uint256 lzCustomGasAmount,
    DataTypes.MirrorWithSigData memory mirrorSig
  ) external payable {
    if (!_checkThreshold(sender, tokenContract, balanceThreshold)) { revert InsufficientBalance(); }

    _lzSend(
      remoteReferenceModulePacked,
      abi.encode(
        false, // isComment
        sender,
        tokenContract,
        balanceThreshold,
        mirrorSig
      ),
      payable(msg.sender),
      _getAdapterParams(lzCustomGasAmount)
    );
  }

  /**
   * @notice validate a token balance on this chain before relaying the intent to collect a Lens post on the remote
   * chain.
   * NOTE: callers of this function MUST pass the exact values for `tokenContract` and `balanceThreshold` returned from
   * the call to LZGatedCollectModule.gatedCollectDataPerPub(profileId, pubId) - or the transaction
   * on the remote chain WILL revert.
   * @param tokenContract: the ERC20/ERC721 contract set by the `profileId` to check a balance against
   * @param balanceThreshold: the amount of tokens required in order for a successful follow
   * @param lzCustomGasAmount: custom gas amount that is paid for lz.send()
   * @param collectSig: the collect signature expected by the LensHub
   */
  function relayCollectWithSig(
    address tokenContract,
    uint256 balanceThreshold,
    uint256 lzCustomGasAmount,
    DataTypes.CollectWithSigData calldata collectSig
  ) external payable {
    if (!_checkThreshold(collectSig.collector, tokenContract, balanceThreshold)) { revert InsufficientBalance(); }

    _lzSend(
      remoteCollectModulePacked,
      abi.encode(
        tokenContract,
        balanceThreshold,
        collectSig
      ),
      payable(msg.sender),
      _getAdapterParams(lzCustomGasAmount)
    );
  }

  /**
   * notice Estimate the lz fees (native / ZRO) for #relayFollowWithSig
   */
  function estimateFeesFollow(
    address tokenContract,
    uint256 balanceThreshold,
    uint256 lzCustomGasAmount,
    DataTypes.FollowWithSigData memory followSig
  ) external view returns (uint256 nativeFee, uint256 zroFee) {
    (nativeFee, zroFee) = lzEndpoint.estimateFees(
      remoteChainId,
      address(this),
      abi.encode(
        tokenContract,
        balanceThreshold,
        followSig
      ),
      zroPaymentAddress != address(0), // _payInZRO
      _getAdapterParams(lzCustomGasAmount)
    );
  }

  /**
   * @notice Estimate the lz fees (native / ZRO) for #relayCollectWithSig
   */
  function estimateFeesCollect(
    address tokenContract,
    uint256 balanceThreshold,
    uint256 lzCustomGasAmount,
    DataTypes.CollectWithSigData calldata collectSig
  ) external view returns (uint256 nativeFee, uint256 zroFee) {
    (nativeFee, zroFee) = lzEndpoint.estimateFees(
      remoteChainId,
      address(this),
      abi.encode(
        tokenContract,
        balanceThreshold,
        collectSig
      ),
      zroPaymentAddress != address(0), // _payInZRO
      _getAdapterParams(lzCustomGasAmount)
    );
  }

  /**
   * notice Estimate the lz fees (native / ZRO) for #relayMirrorWithSig
   */
  function estimateFeesMirror(
    address sender,
    address tokenContract,
    uint256 balanceThreshold,
    uint256 lzCustomGasAmount,
    DataTypes.MirrorWithSigData memory mirrorSig
  ) external view returns (uint256 nativeFee, uint256 zroFee) {
    (nativeFee, zroFee) = lzEndpoint.estimateFees(
      remoteChainId,
      address(this),
      abi.encode(
        false, // isComment
        sender,
        tokenContract,
        balanceThreshold,
        mirrorSig
      ),
      zroPaymentAddress != address(0), // _payInZRO
      _getAdapterParams(lzCustomGasAmount)
    );
  }

  /**
   * notice Estimate the lz fees (native / ZRO) for #relayCommentWithSig
   */
  function estimateFeesComment(
    address sender,
    address tokenContract,
    uint256 balanceThreshold,
    uint256 lzCustomGasAmount,
    DataTypes.CommentWithSigData memory commentSig
  ) external view returns (uint256 nativeFee, uint256 zroFee) {
    (nativeFee, zroFee) = lzEndpoint.estimateFees(
      remoteChainId,
      address(this),
      abi.encode(
        true, // isComment
        sender,
        tokenContract,
        balanceThreshold,
        commentSig
      ),
      zroPaymentAddress != address(0), // _payInZRO
      _getAdapterParams(lzCustomGasAmount)
    );
  }

  /**
   * @notice allows the contract owner to set the `_zroPaymentAddress` responsible for paying all transactions in ZRO
   */
  function setZroPaymentAddress(address _zroPaymentAddress) external onlyOwner {
    zroPaymentAddress = _zroPaymentAddress;
  }

  /**
   * @notice allows the contract owner to set the remote chain id in the case of a change from LZ
   * @param _chainId: the new trusted remote chain id
   */
  function setRemoteChainId(uint16 _chainId) external onlyOwner {
    remoteChainId = _chainId;
  }

  /**
   * @dev not accepting native tokens
   */
  receive() external payable { revert NotAccepting(); }

  /**
   * @dev sends a cross-chain message to the lz endpoint contract deployed on this chain, to be relayed
   * NOTE: we override due to having multiple trusted remotes on `remoteChainId`
   * @param _remoteContractPacked: the contract address on the remote chain to receive the message,
   * @param _payload: the actual message to be relayed
   * @param _refundAddress: the address on this chain to receive the refund - excess paid for gas
   * @param _adapterParams: the custom adapter params to use in sending this message
   */
  function _lzSend(
    bytes storage _remoteContractPacked,
    bytes memory _payload,
    address payable _refundAddress,
    bytes memory _adapterParams
  ) internal {
    lzEndpoint.send{value: msg.value}(
      remoteChainId,
      _remoteContractPacked,
      _payload,
      _refundAddress,
      zroPaymentAddress,
      _adapterParams
    );
  }

  /**
   * @dev not processing messages received
   */
  function _blockingLzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64 _nonce, bytes memory _payload) internal override {}

  /**
   * @dev Check that `account` meets the `balanceThreshold` of held tokens in `tokenContract`; we use the standard
   * `#balanceOf` function signature for ERC721 and ERC20, and simply return false on any error thrown.
   */
  function _checkThreshold(address account, address tokenContract, uint256 balanceThreshold) private returns (bool) {
    (
      bool success,
      bytes memory result
    ) = tokenContract.call(abi.encodeWithSignature("balanceOf(address)", account));

    if (!success) return false;

    (uint256 balance) = abi.decode(result, (uint256));

    return balance >= balanceThreshold;
  }

  /**
   * @dev returns the adapter params (version 1) required to override the gas provided for the tx on the destination
   * chain: https://layerzero.gitbook.io/docs/evm-guides/advanced/relayer-adapter-parameters
   */
  function _getAdapterParams(uint256 gasAmount) private pure returns (bytes memory adapterParams) {
    adapterParams = gasAmount > 0
      ? abi.encodePacked(uint16(1), gasAmount)
      : bytes("");
  }
}
