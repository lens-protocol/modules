// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import 'forge-std/Test.sol';
import './BaseFeeCollectModule.base.sol';
import 'contracts/collect/MultirecipientFeeCollectModule.sol';

contract InheritedCollectModuleBase is BaseFeeCollectModuleBase {
    uint16 constant BPS_MAX = 10000;

    FeeCollectModuleV2 immutable feeCollectModuleV2;
    FeeCollectModuleV2InitData inheritedExampleInitData;

    // Deploy & Whitelist FeeCollectModuleV2
    constructor() {
        vm.prank(deployer);
        baseFeeCollectModule = new FeeCollectModuleV2(hubProxyAddr, address(moduleGlobals));
        feeCollectModuleV2 = new FeeCollectModuleV2(hubProxyAddr, address(moduleGlobals));
        vm.startPrank(governance);
        hub.whitelistCollectModule(address(feeCollectModuleV2), true);
        hub.whitelistCollectModule(address(baseFeeCollectModule), true);
        vm.stopPrank();
    }

    function getEncodedInitData() internal virtual override returns (bytes memory) {
        inheritedExampleInitData.amount = exampleInitData.amount;
        inheritedExampleInitData.collectLimit = exampleInitData.collectLimit;
        inheritedExampleInitData.currency = exampleInitData.currency;
        inheritedExampleInitData.referralFee = exampleInitData.referralFee;
        inheritedExampleInitData.followerOnly = exampleInitData.followerOnly;
        inheritedExampleInitData.endTimestamp = exampleInitData.endTimestamp;
        if (inheritedExampleInitData.recipients.length == 0)
            inheritedExampleInitData.recipients.push(
                RecipientData({recipient: exampleInitData.recipient, split: BPS_MAX})
            );

        return abi.encode(inheritedExampleInitData);
    }
}
