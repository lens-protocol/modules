// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import 'forge-std/Test.sol';
import './BaseFeeCollectModule.base.sol';
import 'contracts/collect/MultirecipientFeeCollectModule.sol';

contract MultirecipientCollectModuleBase is BaseFeeCollectModuleBase {
    uint16 constant BPS_MAX = 10000;
    uint256 MAX_RECIPIENTS = 5;

    MultirecipientFeeCollectModule immutable multirecipientFeeCollectModule;
    MultirecipientFeeCollectModuleInitData multirecipientExampleInitData;

    // Deploy & Whitelist MultirecipientFeeCollectModule
    constructor() {
        vm.prank(deployer);
        baseFeeCollectModule = address(
            new MultirecipientFeeCollectModule(hubProxyAddr, address(moduleGlobals))
        );

        multirecipientFeeCollectModule = new MultirecipientFeeCollectModule(
            hubProxyAddr,
            address(moduleGlobals)
        );
        vm.startPrank(governance);
        hub.whitelistCollectModule(address(multirecipientFeeCollectModule), true);
        hub.whitelistCollectModule(address(baseFeeCollectModule), true);
        vm.stopPrank();
    }

    function getEncodedInitData() internal virtual override returns (bytes memory) {
        multirecipientExampleInitData.amount = exampleInitData.amount;
        multirecipientExampleInitData.collectLimit = exampleInitData.collectLimit;
        multirecipientExampleInitData.currency = exampleInitData.currency;
        multirecipientExampleInitData.referralFee = exampleInitData.referralFee;
        multirecipientExampleInitData.followerOnly = exampleInitData.followerOnly;
        multirecipientExampleInitData.endTimestamp = exampleInitData.endTimestamp;
        if (multirecipientExampleInitData.recipients.length == 0)
            multirecipientExampleInitData.recipients.push(
                RecipientData({recipient: exampleInitData.recipient, split: BPS_MAX})
            );

        return abi.encode(multirecipientExampleInitData);
    }
}
