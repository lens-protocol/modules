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
import {ForkManagement} from 'script/helpers/ForkManagement.sol';

import {Currency} from '@aave/lens-protocol/contracts/mocks/Currency.sol';
import {NFT} from 'contracts/mocks/NFT.sol';

contract BaseSetup is Test, ForkManagement {
    using stdJson for string;

    string forkEnv;
    bool fork;
    string network;
    string json;
    uint256 forkBlockNumber;

    uint256 firstProfileId;
    address deployer;
    address governance;
    address treasury;

    address constant publisher = address(4);
    address constant user = address(5);
    address constant userTwo = address(6);
    address constant userThree = address(7);
    address constant userFour = address(8);
    address constant userFive = address(9);
    address immutable me = address(this);

    string constant MOCK_HANDLE = 'mock';
    string constant MOCK_URI = 'ipfs://QmUXfQWe43RKx31VzA2BnbwhSMW8WuaJvszFWChD59m76U';
    string constant OTHER_MOCK_URI =
        'https://ipfs.io/ipfs/QmTFLSXdEQ6qsSzaXaCSNtiv6wA56qq87ytXJ182dXDQJS';
    string constant MOCK_FOLLOW_NFT_URI =
        'https://ipfs.io/ipfs/QmU8Lv1fk31xYdghzFrLm6CiFcwVg7hdgV6BBWesu6EqLj';

    uint16 TREASURY_FEE_BPS;
    uint16 constant TREASURY_FEE_MAX_BPS = 10000;

    address hubProxyAddr;
    CollectNFT collectNFT;
    FollowNFT followNFT;
    LensHub hubImpl;
    TransparentUpgradeableProxy hubAsProxy;
    LensHub hub;
    FreeCollectModule freeCollectModule;
    Currency currency;
    ModuleGlobals moduleGlobals;
    NFT nft;

    // TODO: Replace with forge-std/StdJson.sol::keyExists(...) when/if this PR is approved:
    //       https://github.com/foundry-rs/forge-std/pull/226
    function keyExists(string memory key) internal returns (bool) {
        return json.parseRaw(key).length > 0;
    }

    function loadBaseAddresses(string memory json, string memory targetEnv) internal virtual {
        bytes32 PROXY_IMPLEMENTATION_STORAGE_SLOT = bytes32(
            uint256(keccak256('eip1967.proxy.implementation')) - 1
        );

        console.log('targetEnv:', targetEnv);

        hubProxyAddr = json.readAddress(string(abi.encodePacked('.', targetEnv, '.LensHubProxy')));
        console.log('hubProxyAddr:', hubProxyAddr);

        hub = LensHub(hubProxyAddr);

        console.log('Hub:', address(hub));

        address followNFTAddr = hub.getFollowNFTImpl();
        address collectNFTAddr = hub.getCollectNFTImpl();

        address hubImplAddr = address(
            uint160(uint256(vm.load(hubProxyAddr, PROXY_IMPLEMENTATION_STORAGE_SLOT)))
        );
        console.log('Found hubImplAddr:', hubImplAddr);
        hubImpl = LensHub(hubImplAddr);
        followNFT = FollowNFT(followNFTAddr);
        collectNFT = CollectNFT(collectNFTAddr);
        hubAsProxy = TransparentUpgradeableProxy(payable(address(hub)));
        freeCollectModule = FreeCollectModule(
            json.readAddress(string(abi.encodePacked('.', targetEnv, '.FreeCollectModule')))
        );

        moduleGlobals = ModuleGlobals(
            json.readAddress(string(abi.encodePacked('.', targetEnv, '.ModuleGlobals')))
        );

        currency = new Currency();
        nft = new NFT();

        firstProfileId = uint256(vm.load(hubProxyAddr, bytes32(uint256(22)))) + 1;
        console.log('firstProfileId:', firstProfileId);

        deployer = address(1);

        governance = hub.getGovernance();
        treasury = moduleGlobals.getTreasury();

        TREASURY_FEE_BPS = moduleGlobals.getTreasuryFee();
    }

    function deployBaseContracts() internal {
        firstProfileId = 1;
        deployer = address(1);
        governance = address(2);
        treasury = address(3);

        TREASURY_FEE_BPS = 50;

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
    }

    constructor() {
        forkEnv = vm.envString('TESTING_FORK');

        if (bytes(forkEnv).length > 0) {
            fork = true;
            console.log('\n\n Testing using %s fork', forkEnv);
            json = loadJson();

            network = getNetwork(json, forkEnv);
            vm.createSelectFork(network);

            forkBlockNumber = block.number;
            console.log('Fork Block number:', forkBlockNumber);

            checkNetworkParams(json, forkEnv);

            loadBaseAddresses(json, forkEnv);
        } else {
            deployBaseContracts();
        }
        ///////////////////////////////////////// Start governance actions.
        vm.startPrank(governance);

        if (hub.getState() != DataTypes.ProtocolState.Unpaused)
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
