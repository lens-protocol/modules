// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import 'forge-std/Script.sol';

contract ForkManagement is Script {
    using stdJson for string;

    function loadJson() internal returns (string memory) {
        string memory root = vm.projectRoot();
        string memory path = string(abi.encodePacked(root, '/addresses.json'));
        string memory json = vm.readFile(path);
        return json;
    }

    function checkNetworkParams(string memory json, string memory targetEnv)
        internal
        returns (string memory network, uint256 chainId)
    {
        network = json.readString(string(abi.encodePacked('.', targetEnv, '.network')));
        chainId = json.readUint(string(abi.encodePacked('.', targetEnv, '.chainId')));

        console.log('\nTarget environment:', targetEnv);
        console.log('Network:', network);
        if (block.chainid != chainId) revert('Wrong chainId');
        console.log('ChainId:', chainId);
    }

    function getNetwork(string memory json, string memory targetEnv)
        internal
        returns (string memory)
    {
        return json.readString(string(abi.encodePacked('.', targetEnv, '.network')));
    }
}
