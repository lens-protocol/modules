// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import 'forge-std/Test.sol';
import '../BaseSetup.t.sol';
import {SimpleFeeCollectModule} from 'contracts/collect/SimpleFeeCollectModule.sol';
import {BaseFeeCollectModuleInitData} from 'contracts/collect/base/IBaseFeeCollectModule.sol';

contract BaseFeeCollectModuleBase is BaseSetup {
    using stdJson for string;
    address baseFeeCollectModule;
    SimpleFeeCollectModule simpleFeeCollectModule;

    BaseFeeCollectModuleInitData exampleInitData;

    uint256 constant DEFAULT_COLLECT_LIMIT = 3;
    uint16 constant REFERRAL_FEE_BPS = 250;

    // Deploy & Whitelist BaseFeeCollectModule
    constructor() BaseSetup() {
        if (fork && keyExists(string(abi.encodePacked('.', forkEnv, '.SimpleFeeCollectModule')))) {
            simpleFeeCollectModule = SimpleFeeCollectModule(
                json.readAddress(string(abi.encodePacked('.', forkEnv, '.SimpleFeeCollectModule')))
            );
            baseFeeCollectModule = address(simpleFeeCollectModule);
            console.log(
                'Testing against already deployed module at:',
                address(baseFeeCollectModule)
            );
        } else {
            vm.prank(deployer);
            baseFeeCollectModule = address(
                new SimpleFeeCollectModule(hubProxyAddr, address(moduleGlobals))
            );
        }
        vm.prank(governance);
        hub.whitelistCollectModule(address(baseFeeCollectModule), true);
    }

    function getEncodedInitData() internal virtual returns (bytes memory) {
        return abi.encode(exampleInitData);
    }
}
