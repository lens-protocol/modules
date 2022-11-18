// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import 'forge-std/Test.sol';
import '../BaseSetup.t.sol';
import 'contracts/reference/TokenGatedReferenceModule.sol';

// import '../helpers/TestHelpers.sol';

contract TokenGatedReferenceModuleBase is BaseSetup {
    using stdJson for string;
    TokenGatedReferenceModule tokenGatedReferenceModule;

    // Deploy & Whitelist TokenGatedReferenceModule
    constructor() BaseSetup() {
        if (
            fork && keyExists(string(abi.encodePacked('.', forkEnv, '.TokenGatedReferenceModule')))
        ) {
            tokenGatedReferenceModule = TokenGatedReferenceModule(
                json.readAddress(
                    string(abi.encodePacked('.', forkEnv, '.TokenGatedReferenceModule'))
                )
            );
            console.log(
                'Testing against already deployed module at:',
                address(tokenGatedReferenceModule)
            );
        } else {
            vm.prank(deployer);
            tokenGatedReferenceModule = new TokenGatedReferenceModule(hubProxyAddr);
        }
        vm.prank(governance);
        hub.whitelistReferenceModule(address(tokenGatedReferenceModule), true);
    }
}
