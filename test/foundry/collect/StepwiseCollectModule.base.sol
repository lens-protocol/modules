// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import 'forge-std/Test.sol';
import '../BaseSetup.t.sol';
import 'contracts/collect/StepwiseCollectModule.sol';

contract StepwiseCollectModuleBase is BaseSetup {
    StepwiseCollectModule immutable stepwiseCollectModule;

    uint256 constant DEFAULT_COLLECT_LIMIT = 3;
    uint16 constant REFERRAL_FEE_BPS = 250;

    // Deploy & Whitelist StepwiseCollectModule
    constructor() BaseSetup() {
        vm.prank(deployer);
        stepwiseCollectModule = new StepwiseCollectModule(hubProxyAddr, address(moduleGlobals));
        vm.prank(governance);
        hub.whitelistCollectModule(address(stepwiseCollectModule), true);
    }
}
