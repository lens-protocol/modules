// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import 'forge-std/Test.sol';
import '../BaseSetup.t.sol';
import 'contracts/reference/TokenGatedReferenceModule.sol';

// import '../helpers/TestHelpers.sol';

contract TokenGatedReferenceModuleBase is BaseSetup {
    TokenGatedReferenceModule immutable tokenGatedReferenceModule;

    // Deploy & Whitelist TokenGatedReferenceModule
    constructor() BaseSetup() {
        vm.prank(deployer);
        tokenGatedReferenceModule = new TokenGatedReferenceModule(hubProxyAddr);
        vm.prank(governance);
        hub.whitelistReferenceModule(address(tokenGatedReferenceModule), true);
    }
}
