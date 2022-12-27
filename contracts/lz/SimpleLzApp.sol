// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "@rari-capital/solmate/src/auth/Owned.sol";
import "./interfaces/ILayerZeroUserApplicationConfig.sol";
import "./interfaces/ILayerZeroEndpoint.sol";

/**
 * @title SimpleLzApp
 * @notice LayerZero-enabled contract that has only one trusted remote chain and sends messages cross-chain (does NOT
 * receive) to remote contracts provided by the concrete class.
 * NOTE: this contract is ownable only to set layerzero configs.
 */
abstract contract SimpleLzApp is Owned, ILayerZeroUserApplicationConfig {
  error NotZeroAddress();

  ILayerZeroEndpoint public immutable lzEndpoint; // lz endpoint contract deployed on this chain

  uint16 public remoteChainId; // lz chain id
  address public zroPaymentAddress; // the address of the ZRO token holder who would pay for all transactions

  /**
   * @dev contract constructor
   * @param _lzEndpoint: the lz endpoint contract deployed on this chain
   * @param _owner: the Contract owner
   * @param _remoteChainId: remote chain id to be set as the trusted remote
   */
  constructor(address _lzEndpoint, address _owner, uint16 _remoteChainId) Owned(_owner) {
    if (_lzEndpoint == address(0)) { revert NotZeroAddress(); }

    lzEndpoint = ILayerZeroEndpoint(_lzEndpoint);
    remoteChainId = _remoteChainId;
  }

  /**
   * @notice generic config for LayerZero user application
   */
  function setConfig(
    uint16 _version,
    uint16 _chainId,
    uint _configType,
    bytes calldata _config
  ) external override onlyOwner {
    lzEndpoint.setConfig(_version, _chainId, _configType, _config);
  }

  /**
   * @notice allows the contract owner to set the lz config for send version
   */
  function setSendVersion(uint16 _version) external override onlyOwner {
    lzEndpoint.setSendVersion(_version);
  }

  /**
   * @notice allows the contract owner to set the lz config for receive version
   */
  function setReceiveVersion(uint16 _version) external override onlyOwner {
    lzEndpoint.setReceiveVersion(_version);
  }

  /**
   * @notice allows the contract owner to set the `_zroPaymentAddress` responsible for paying all transactions in ZRO
   */
  function setZroPaymentAddress(address _zroPaymentAddress) external onlyOwner {
    zroPaymentAddress = _zroPaymentAddress;
  }

  /**
   * @notice allows the contract owner to unblock the queue of messages
   */
  function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) external override onlyOwner {
    lzEndpoint.forceResumeReceive(_srcChainId, _srcAddress);
  }

  /**
   * @notice returns the lz config for this contract
   */
  function getConfig(uint16 _version, uint16 _chainId, address, uint _configType) external view returns (bytes memory) {
    return lzEndpoint.getConfig(_version, _chainId, address(this), _configType);
  }

  /**
   * @dev sends a cross-chain message to the lz endpoint contract deployed on this chain, to be relayed
   * @param _remoteContract: the trusted contract on the remote chain to receive the message
   * @param _payload: the actual message to be relayed
   * @param _refundAddress: the address on this chain to receive the refund - excess paid for gas
   * @param _adapterParams: the custom adapter params to use in sending this message
   */
  function _lzSend(
    bytes storage _remoteContract,
    bytes memory _payload,
    address payable _refundAddress,
    bytes memory _adapterParams
  ) internal virtual {
    // remote address concated with local address packed into 40 bytes
    bytes memory remoteAndLocalAddresses = abi.encodePacked(_remoteContract, address(this));

    lzEndpoint.send{value: msg.value}(
      remoteChainId,
      remoteAndLocalAddresses,
      _payload,
      _refundAddress,
      zroPaymentAddress,
      _adapterParams
    );
  }
}
