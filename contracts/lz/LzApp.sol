// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "@rari-capital/solmate/src/auth/Owned.sol";
import "./interfaces/ILayerZeroReceiver.sol";
import "./interfaces/ILayerZeroUserApplicationConfig.sol";
import "./interfaces/ILayerZeroEndpoint.sol";

/**
 * @title LzApp
 * @notice LayerZero-enabled contract that can have multiple remote chain ids.
 */
abstract contract LzApp is Owned, ILayerZeroReceiver, ILayerZeroUserApplicationConfig {
  error NotZeroAddress();
  error ArrayMismatch();
  error OnlyEndpoint();
  error RemoteNotFound();
  error OnlyTrustedRemote();
  error NotAccepting();

  event MessageFailed(uint16 _srcChainId, bytes _srcAddress, uint64 _nonce, bytes _payload, string _reason);

  ILayerZeroEndpoint public immutable lzEndpoint;

  address public zroPaymentAddress; // the address of the ZRO token holder who would pay for the transaction

  mapping (uint16 => bytes) internal _lzRemoteLookup; // chainId (lz) => endpoint

  /**
   * @dev contract constructor
   * @param _lzEndpoint: The LZ endpoint contract deployed on this chain
   * @param owner: The contract owner
   * @param remoteChainIds: remote chain ids to set as trusted remotes
   * @param remoteContracts: remote contracts to set as trusted remotes
   */
  constructor(
    address _lzEndpoint,
    address owner,
    uint16[] memory remoteChainIds,
    bytes[] memory remoteContracts
  ) Owned(owner) {
    if (_lzEndpoint == address(0)) { revert NotZeroAddress(); }
    if (remoteChainIds.length != remoteContracts.length) { revert ArrayMismatch(); }

    lzEndpoint = ILayerZeroEndpoint(_lzEndpoint);

    uint256 length = remoteChainIds.length;
    for (uint256 i = 0; i < length;) {
      _lzRemoteLookup[remoteChainIds[i]] = remoteContracts[i];
      unchecked { i++; }
    }
  }

  /**
   * @dev not accepting native tokens
   */
  receive() external virtual payable { revert NotAccepting(); }

  /**
   * @dev receives a cross-chain message from the lz endpoint contract deployed on this chain
   * NOTE: this is non-blocking in the sense that it does not explicitly revert, but of course does not catch all
   * potential errors thrown.
   * @param _srcChainId: the remote chain id
   * @param _srcAddress: the remote contract sending the message
   * @param _nonce: the message nonce
   * @param _payload: the message payload
   */
  function lzReceive(
    uint16 _srcChainId,
    bytes memory _srcAddress,
    uint64 _nonce,
    bytes memory _payload
  ) public virtual override {
    if (msg.sender != address(lzEndpoint)) {
      emit MessageFailed(_srcChainId, _srcAddress, _nonce, _payload, 'OnlyEndpoint');
    }

    bytes memory trustedRemote = _lzRemoteLookup[_srcChainId];
    if (_srcAddress.length != trustedRemote.length || keccak256(_srcAddress) != keccak256(trustedRemote)) {
      emit MessageFailed(_srcChainId, _srcAddress, _nonce, _payload, 'OnlyTrustedRemote');
    }

    _blockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
  }

  function setTrustedRemote(uint16 _srcChainId, bytes calldata _srcAddress) external onlyOwner {
    _lzRemoteLookup[_srcChainId] = _srcAddress;
  }

  // @dev generic config for LayerZero user Application
  function setConfig(
    uint16 _version,
    uint16 _chainId,
    uint _configType,
    bytes calldata _config
  ) external override onlyOwner {
    lzEndpoint.setConfig(_version, _chainId, _configType, _config);
  }

  function setSendVersion(uint16 _version) external override onlyOwner {
    lzEndpoint.setSendVersion(_version);
  }

  function setReceiveVersion(uint16 _version) external override onlyOwner {
    lzEndpoint.setReceiveVersion(_version);
  }

  function setZroPaymentAddress(address _zroPaymentAddress) external onlyOwner {
    zroPaymentAddress = _zroPaymentAddress;
  }

  function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) external override onlyOwner {
    lzEndpoint.forceResumeReceive(_srcChainId, _srcAddress);
  }

  function getConfig(uint16 _version, uint16 _chainId, address, uint _configType) external view returns (bytes memory) {
    return lzEndpoint.getConfig(_version, _chainId, address(this), _configType);
  }

  function _lzSend(
    uint16 _dstChainId,
    bytes memory _payload,
    address payable _refundAddress,
    bytes memory _adapterParams
  ) internal virtual {
    if (_lzRemoteLookup[_dstChainId].length == 0) { revert RemoteNotFound(); }

    lzEndpoint.send{value: msg.value}(
      _dstChainId,
      _lzRemoteLookup[_dstChainId],
      _payload,
      _refundAddress,
      zroPaymentAddress,
      _adapterParams
    );
  }

  // @dev to be overriden by the concrete class
  function _blockingLzReceive(
    uint16 _srcChainId,
    bytes memory _srcAddress,
    uint64 _nonce,
    bytes memory _payload
  ) internal virtual;
}
