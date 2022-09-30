// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import 'forge-std/Test.sol';
import '../BaseSetup.t.sol';
import 'contracts/collect/FeeCollectModuleV2.sol';

contract FreeCollectModuleV2Test is BaseSetup {
    // TODO fix this
    address public moduleGlobals = address(1234);

    FeeCollectModuleV2 immutable feeCollectModuleV2;

    // Deploy & Whitelist FeeCollectModuleV2
    constructor() BaseSetup() {
        vm.prank(deployer);
        feeCollectModuleV2 = new FeeCollectModuleV2(hubProxyAddr, moduleGlobals);
        vm.prank(governance);
        hub.whitelistReferenceModule(address(feeCollectModuleV2), true);
    }

    function setUp() public {}

    /*//////////////////////////////////////////////////////////////
                                NEGATIVES
    //////////////////////////////////////////////////////////////*/

    function testCannotPostWithUnwhitelistedCurrency() public {}

    /*//////////////////////////////////////////////////////////////
                                SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function testScen1() public {}
}
