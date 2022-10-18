// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import 'forge-std/Test.sol';
import '../BaseSetup.t.sol';
import {BaseFeeCollectModule} from 'contracts/collect/BaseFeeCollectModule.sol';
import {BaseCollectModuleInitData} from 'contracts/collect/AbstractCollectModule.sol';

contract BaseFeeCollectModuleBase is BaseSetup {
    address baseFeeCollectModule;

    BaseCollectModuleInitData exampleInitData;

    uint256 constant DEFAULT_COLLECT_LIMIT = 3;
    uint16 constant REFERRAL_FEE_BPS = 250;

    // Deploy & Whitelist BaseFeeCollectModule
    constructor() BaseSetup() {
        vm.prank(deployer);
        baseFeeCollectModule = address(
            new BaseFeeCollectModule(hubProxyAddr, address(moduleGlobals))
        );
        vm.prank(governance);
        hub.whitelistCollectModule(address(baseFeeCollectModule), true);
    }

    function getEncodedInitData() internal virtual returns (bytes memory) {
        return abi.encode(exampleInitData);
    }
}
