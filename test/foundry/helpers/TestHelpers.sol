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

    function getCreatedProfileIdFromEvents(Vm.Log[] memory entries) public pure returns (uint256) {
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == profileCreatedEventTopic) {
                return uint256(entries[i].topics[1]); // 0 is always event topic
            }
        }
    }

    function getCreatedPubIdFromEvents(Vm.Log[] memory entries) public pure returns (uint256) {
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == postCreatedEventTopic) {
                return uint256(entries[i].topics[2]); // 0 is always event topic
            }
        }
    }
}
