// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import 'forge-std/Script.sol';
import 'forge-std/StdJson.sol';
import {StepwiseCollectModule} from 'contracts/collect/StepwiseCollectModule.sol';

contract DeployStepwiseCollect is Script {
    using stdJson for string;

    function run(string calldata target) external {
        string memory root = vm.projectRoot();
        string memory path = string(abi.encodePacked(root, '/addresses.json'));
        string memory json = vm.readFile(path);
        string memory network = json.readString(string(abi.encodePacked('.', target, '.network')));
        uint256 chainId = json.readUint(string(abi.encodePacked('.', target, '.chainId')));

        console.log('Target environment:', target);
        console.log('Network:', network);
        if (block.chainid != chainId) revert('Wrong chainId');
        console.log('ChainId:', chainId);
        console.log('Contract: StepwiseCollectModule');

        address lensHubProxy = json.readAddress(
            string(abi.encodePacked('.', target, '.LensHubProxy'))
        );
        address moduleGlobals = json.readAddress(
            string(abi.encodePacked('.', target, '.ModuleGlobals'))
        );

        console.log('LensHubProxy:', lensHubProxy);
        console.log('ModuleGlobals:', moduleGlobals);

        string memory mnemonic = vm.envString('MNEMONIC');
        (address deployer, uint256 deployerPrivateKey) = deriveRememberKey(mnemonic, 0);
        console.log('Deployer address:', deployer);
        console.log('Deployer balance:', deployer.balance);

        vm.startBroadcast(deployerPrivateKey);
        StepwiseCollectModule stepwiseCollectModule = new StepwiseCollectModule(
            lensHubProxy,
            moduleGlobals
        );
        vm.stopBroadcast();

        console.log('New Deployment Address:', address(stepwiseCollectModule));
    }
}
