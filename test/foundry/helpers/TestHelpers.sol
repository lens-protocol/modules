// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Vm} from 'forge-std/Test.sol';

library TestHelpers {
    // TODO: Replace these constants with Events.***.selector after upping to Solidity >=0.8.15
    bytes32 constant profileCreatedEventTopic =
        keccak256(
            'ProfileCreated(uint256,address,address,string,string,address,bytes,string,uint256)'
        );

    bytes32 constant postCreatedEventTopic =
        keccak256('PostCreated(uint256,uint256,string,address,bytes,address,bytes,uint256)');

    bytes32 constant mirrorCreatedEventTopic =
        keccak256('MirrorCreated(uint256,uint256,uint256,uint256,bytes,address,bytes,uint256)');

    bytes32 constant transferEventTopic = keccak256('Transfer(address,address,uint256)');

    function getCreatedProfileIdFromEvents(Vm.Log[] memory entries) public pure returns (uint256) {
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == profileCreatedEventTopic) {
                return uint256(entries[i].topics[1]); // 0 is always event topic
            }
        }
        revert('No Profile creation event found');
    }

    function getCreatedPubIdFromEvents(Vm.Log[] memory entries) public pure returns (uint256) {
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == postCreatedEventTopic) {
                return uint256(entries[i].topics[2]); // 0 is always event topic
            }
        }
        revert('No Publication creation event found');
    }

    function getCreatedMirrorIdFromEvents(Vm.Log[] memory entries) public pure returns (uint256) {
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == mirrorCreatedEventTopic) {
                return uint256(entries[i].topics[2]); // 0 is always event topic
            }
        }
        revert('No Mirror creation event found');
    }

    function getTransferFromEvents(
        Vm.Log[] memory entries,
        address from,
        address to
    ) public pure returns (uint256) {
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == transferEventTopic) {
                if (
                    entries[i].topics[1] == bytes32(abi.encode(from)) &&
                    entries[i].topics[2] == bytes32(abi.encode(to))
                ) {
                    return abi.decode(entries[i].data, (uint256)); // 0 is always event topic
                }
            }
        }
        revert('No Transfer event found');
    }
}
