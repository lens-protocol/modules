// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import 'forge-std/Script.sol';
import 'forge-std/StdJson.sol';
import {StepwiseCollectModule} from 'contracts/collect/StepwiseCollectModule.sol';
import {MultirecipientFeeCollectModule} from 'contracts/collect/MultirecipientFeeCollectModule.sol';

contract DeployBase is Script {
    using stdJson for string;

    uint256 deployerPrivateKey;
    address deployer;
    address lensHubProxy;
    address moduleGlobals;

    function loadJson() internal returns (string memory) {
        string memory root = vm.projectRoot();
        string memory path = string(abi.encodePacked(root, '/addresses.json'));
        string memory json = vm.readFile(path);
        return json;
    }

    function checkNetworkParams(string memory json, string memory targetEnv) internal {
        string memory network = json.readString(
            string(abi.encodePacked('.', targetEnv, '.network'))
        );
        uint256 chainId = json.readUint(string(abi.encodePacked('.', targetEnv, '.chainId')));

        console.log('\nTarget environment:', targetEnv);
        console.log('Network:', network);
        if (block.chainid != chainId) revert('Wrong chainId');
        console.log('ChainId:', chainId);
    }

    function loadBaseAddresses(string memory json, string memory targetEnv) internal {
        lensHubProxy = json.readAddress(string(abi.encodePacked('.', targetEnv, '.LensHubProxy')));
        moduleGlobals = json.readAddress(
            string(abi.encodePacked('.', targetEnv, '.ModuleGlobals'))
        );
    }

    function loadPrivateKeys() internal {
        string memory mnemonic = vm.envString('MNEMONIC');

        if (bytes(mnemonic).length > 0) {
            (deployer, deployerPrivateKey) = deriveRememberKey(mnemonic, 0);
        } else {
            deployerPrivateKey = vm.envUint('PRIVATE_KEY');
            deployer = vm.addr(deployerPrivateKey);
        }

        console.log('\nDeployer address:', deployer);
        console.log('Deployer balance:', deployer.balance);
    }

    function run(string calldata targetEnv) external {
        string memory json = loadJson();
        checkNetworkParams(json, targetEnv);
        loadBaseAddresses(json, targetEnv);
        loadPrivateKeys();

        address module = deploy();
        console.log('New Deployment Address:', address(module));
    }

    function deploy() internal virtual returns (address) {}
}

contract DeployStepwiseCollectModule is DeployBase {
    function deploy() internal override returns (address) {
        console.log('\nContract: StepwiseCollectModule');
        console.log('Init params:');
        console.log('\tLensHubProxy:', lensHubProxy);
        console.log('\tModuleGlobals:', moduleGlobals);

        vm.startBroadcast(deployerPrivateKey);
        StepwiseCollectModule stepwiseCollectModule = new StepwiseCollectModule(
            lensHubProxy,
            moduleGlobals
        );
        vm.stopBroadcast();

        return address(stepwiseCollectModule);
    }
}

contract DeployMultirecipientFeeCollectModule is DeployBase {
    function deploy() internal override returns (address) {
        console.log('\nContract: MultirecipientFeeCollectModule');
        console.log('Init params:');
        console.log('\tLensHubProxy:', lensHubProxy);
        console.log('\tModuleGlobals:', moduleGlobals);

        vm.startBroadcast(deployerPrivateKey);
        MultirecipientFeeCollectModule module = new MultirecipientFeeCollectModule(
            lensHubProxy,
            moduleGlobals
        );
        vm.stopBroadcast();

        return address(module);
    }
}
