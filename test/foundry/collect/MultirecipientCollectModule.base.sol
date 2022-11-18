// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import 'forge-std/Test.sol';
import './BaseFeeCollectModule.base.sol';
import 'contracts/collect/MultirecipientFeeCollectModule.sol';

contract MultirecipientCollectModuleBase is BaseFeeCollectModuleBase {
    using stdJson for string;
    uint16 constant BPS_MAX = 10000;
    uint256 MAX_RECIPIENTS = 5;

    MultirecipientFeeCollectModule multirecipientFeeCollectModule;
    MultirecipientFeeCollectModuleInitData multirecipientExampleInitData;

    // Deploy & Whitelist MultirecipientFeeCollectModule
    constructor() {
        if (
            fork &&
            keyExists(string(abi.encodePacked('.', forkEnv, '.MultirecipientFeeCollectModule')))
        ) {
            multirecipientFeeCollectModule = MultirecipientFeeCollectModule(
                json.readAddress(
                    string(abi.encodePacked('.', forkEnv, '.MultirecipientFeeCollectModule'))
                )
            );
            console.log(
                'Testing against already deployed module at:',
                address(multirecipientFeeCollectModule)
            );
        } else {
            vm.prank(deployer);
            multirecipientFeeCollectModule = new MultirecipientFeeCollectModule(
                hubProxyAddr,
                address(moduleGlobals)
            );
        }
        baseFeeCollectModule = address(multirecipientFeeCollectModule);
        vm.startPrank(governance);
        hub.whitelistCollectModule(address(multirecipientFeeCollectModule), true);
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
