// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import 'forge-std/Test.sol';
import '../BaseSetup.t.sol';
import 'contracts/collect/StepwiseCollectModule.sol';

contract StepwiseCollectModuleBase is BaseSetup {
    using stdJson for string;
    StepwiseCollectModule stepwiseCollectModule;

    uint256 constant DEFAULT_COLLECT_LIMIT = 3;
    uint16 constant REFERRAL_FEE_BPS = 250;

    // Deploy & Whitelist StepwiseCollectModule
    constructor() BaseSetup() {
        if (fork && keyExists(string(abi.encodePacked('.', forkEnv, '.StepwiseCollectModule')))) {
            stepwiseCollectModule = StepwiseCollectModule(
                json.readAddress(string(abi.encodePacked('.', forkEnv, '.StepwiseCollectModule')))
            );
            console.log(
                'Testing against already deployed module at:',
                address(stepwiseCollectModule)
            );
        } else {
            vm.prank(deployer);
            stepwiseCollectModule = new StepwiseCollectModule(hubProxyAddr, address(moduleGlobals));
        }
        vm.prank(governance);
        hub.whitelistCollectModule(address(stepwiseCollectModule), true);
    }
}
