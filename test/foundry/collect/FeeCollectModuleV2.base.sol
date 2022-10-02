// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import 'forge-std/Test.sol';
import '../BaseSetup.t.sol';
import 'contracts/collect/FeeCollectModuleV2.sol';

contract FeeCollectModuleV2Base is BaseSetup {
    FeeCollectModuleV2 immutable feeCollectModuleV2;

    uint256 constant DEFAULT_COLLECT_LIMIT = 3;
    uint16 constant REFERRAL_FEE_BPS = 250;

    // Deploy & Whitelist FeeCollectModuleV2
    constructor() BaseSetup() {
        vm.prank(deployer);
        feeCollectModuleV2 = new FeeCollectModuleV2(hubProxyAddr, address(moduleGlobals));
        vm.prank(governance);
        hub.whitelistCollectModule(address(feeCollectModuleV2), true);
    }
}
