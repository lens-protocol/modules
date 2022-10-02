// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import 'forge-std/Test.sol';

// Deployments
import {LensHub} from '@aave/lens-protocol/contracts/core/LensHub.sol';
import {FollowNFT} from '@aave/lens-protocol/contracts/core/FollowNFT.sol';
import {CollectNFT} from '@aave/lens-protocol/contracts/core/CollectNFT.sol';
import {ModuleGlobals} from '@aave/lens-protocol/contracts/core/modules/ModuleGlobals.sol';
import {FreeCollectModule} from '@aave/lens-protocol/contracts/core/modules/collect/FreeCollectModule.sol';
import {TransparentUpgradeableProxy} from '@aave/lens-protocol/contracts/upgradeability/TransparentUpgradeableProxy.sol';
import {DataTypes} from '@aave/lens-protocol/contracts/libraries/DataTypes.sol';
import {Errors} from '@aave/lens-protocol/contracts/libraries/Errors.sol';

import {Currency} from '@aave/lens-protocol/contracts/mocks/Currency.sol';
import {NFT} from 'contracts/mocks/NFT.sol';

contract BaseSetup is Test {
    uint256 constant firstProfileId = 1;
    address constant deployer = address(1);
    address constant governance = address(2);
    address constant treasury = address(3);
    address constant publisher = address(4);
    address constant user = address(5);
    address constant userTwo = address(6);
    address immutable me = address(this); // Main test User is this (rather inheriting from this) contract

    string constant MOCK_HANDLE = 'handle.lens';
    string constant MOCK_URI = 'ipfs://QmUXfQWe43RKx31VzA2BnbwhSMW8WuaJvszFWChD59m76U';
    string constant OTHER_MOCK_URI =
        'https://ipfs.io/ipfs/QmTFLSXdEQ6qsSzaXaCSNtiv6wA56qq87ytXJ182dXDQJS';
    string constant MOCK_FOLLOW_NFT_URI =
        'https://ipfs.io/ipfs/QmU8Lv1fk31xYdghzFrLm6CiFcwVg7hdgV6BBWesu6EqLj';

    uint16 constant TREASURY_FEE_BPS = 50;
    uint16 constant TREASURY_FEE_MAX_BPS = 10000;

    address immutable hubProxyAddr;
    CollectNFT immutable collectNFT;
    FollowNFT immutable followNFT;
    LensHub immutable hubImpl;
    TransparentUpgradeableProxy immutable hubAsProxy;
    LensHub immutable hub;
    FreeCollectModule immutable freeCollectModule;
    Currency immutable currency;
    ModuleGlobals immutable moduleGlobals;
    NFT immutable nft;

    constructor() {
        ///////////////////////////////////////// Start deployments.
        vm.startPrank(deployer);

        // Precompute needed addresss.
        address followNFTAddr = computeCreateAddress(deployer, 1);
        address collectNFTAddr = computeCreateAddress(deployer, 2);
        hubProxyAddr = computeCreateAddress(deployer, 3);

        // Deploy implementation contracts.
        hubImpl = new LensHub(followNFTAddr, collectNFTAddr);
        followNFT = new FollowNFT(hubProxyAddr);
        collectNFT = new CollectNFT(hubProxyAddr);

        // Deploy and initialize proxy.
        bytes memory initData = abi.encodeWithSelector(
            hubImpl.initialize.selector,
            'Lens Protocol Profiles',
            'LPP',
            governance
        );
        hubAsProxy = new TransparentUpgradeableProxy(address(hubImpl), deployer, initData);

        // Cast proxy to LensHub interface.
        hub = LensHub(address(hubAsProxy));

        // Deploy the FreeCollectModule.
        freeCollectModule = new FreeCollectModule(hubProxyAddr);

        moduleGlobals = new ModuleGlobals(governance, treasury, TREASURY_FEE_BPS);

        currency = new Currency();
        nft = new NFT();

        vm.stopPrank();
        ///////////////////////////////////////// End deployments.

        ///////////////////////////////////////// Start governance actions.
        vm.startPrank(governance);

        // Set the state to unpaused.
        hub.setState(DataTypes.ProtocolState.Unpaused);

        // Whitelist the FreeCollectModule.
        hub.whitelistCollectModule(address(freeCollectModule), true);

        // Whitelist the test contract as a profile creator
        hub.whitelistProfileCreator(me, true);

        // Whitelist mock currency in ModuleGlobals
        moduleGlobals.whitelistCurrency(address(currency), true);

        vm.stopPrank();
        ///////////////////////////////////////// End governance actions.
    }

    function _toUint256Array(uint256 n) internal pure returns (uint256[] memory) {
        uint256[] memory ret = new uint256[](1);
        ret[0] = n;
        return ret;
    }

    function _toBytesArray(bytes memory n) internal pure returns (bytes[] memory) {
        bytes[] memory ret = new bytes[](1);
        ret[0] = n;
        return ret;
    }
}
