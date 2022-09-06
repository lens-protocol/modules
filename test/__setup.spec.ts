import { AbiCoder } from '@ethersproject/abi';
import { parseEther } from '@ethersproject/units';
import '@nomiclabs/hardhat-ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect, use } from 'chai';
import { solidity } from 'ethereum-waffle';
import { BytesLike, Wallet } from 'ethers';
import { ethers } from 'hardhat';
import {
  CollectNFT__factory,
  Events,
  Events__factory,
  FollowNFT__factory,
  InteractionLogic__factory,
  LensHub,
  LensHub__factory,
  ProfileTokenURILogic__factory,
  PublishingLogic__factory,
  FollowNFT,
  CollectNFT,
  ModuleGlobals__factory,
  TransparentUpgradeableProxy__factory,
  Currency__factory,
  Currency,
  ACurrency,
  ACurrency__factory,
  ModuleGlobals,
  AuctionCollectModule,
  AuctionCollectModule__factory,
  FreeCollectModule__factory,
  FreeCollectModule,
  MockLendingPool,
  MockLendingPool__factory,
  AaveLimitedFeeCollectModule,
  AaveLimitedFeeCollectModule__factory,
} from '../typechain';
import { LensHubLibraryAddresses } from '../typechain/factories/LensHub__factory';
import {
  computeContractAddress,
  ProtocolState,
  revertToSnapshot,
  takeSnapshot,
} from './helpers/utils';

use(solidity);

export const CURRENCY_MINT_AMOUNT = parseEther('100');
export const BPS_MAX = 10000;
export const TREASURY_FEE_BPS = 50;
export const REFERRAL_FEE_BPS = 250;
export const MAX_PROFILE_IMAGE_URI_LENGTH = 6000;
export const LENS_HUB_NFT_NAME = 'Lens Protocol Profiles';
export const LENS_HUB_NFT_SYMBOL = 'LPP';
export const MOCK_PROFILE_HANDLE = 'satoshi.lens';
export const FIRST_PROFILE_ID = 1;
export const FIRST_PUB_ID = 1;
export const FIRST_FOLLOW_NFT_ID = 1;
export const MOCK_URI = 'https://ipfs.io/ipfs/QmY9dUwYu67puaWBMxRKW98LPbXCznPwHUbhX5NeWnCJbX';
export const OTHER_MOCK_URI = 'https://ipfs.io/ipfs/QmTFLSXdEQ6qsSzaXaCSNtiv6wA56qq87ytXJ182dXDQJS';
export const MOCK_PROFILE_URI =
  'https://ipfs.io/ipfs/Qme7ss3ARVgxv6rXqVPiikMJ8u2NLgmgszg13pYrDKEoiu';
export const MOCK_FOLLOW_NFT_URI =
  'https://ipfs.io/ipfs/QmU8Lv1fk31xYdghzFrLm6CiFcwVg7hdgV6BBWesu6EqLj';

export let chainId: number;
export let accounts: SignerWithAddress[];
export let deployer: SignerWithAddress;
export let governance: SignerWithAddress;
export let proxyAdmin: SignerWithAddress;
export let treasury: SignerWithAddress;
export let user: SignerWithAddress;
export let userTwo: SignerWithAddress;
export let anotherUser: SignerWithAddress;
export let thirdUser: SignerWithAddress;
export let publisher: SignerWithAddress;
export let feeRecipient: SignerWithAddress;
export let collector: SignerWithAddress;

export let userAddress: string;
export let userTwoAddress: string;
export let treasuryAddress: string;

export let lensHubImpl: LensHub;
export let lensHub: LensHub;
export let currency: Currency;
export let aCurrency: ACurrency;
export let currencyTwo: Currency;
export let lendingPool: MockLendingPool;
export let abiCoder: AbiCoder;
export let mockModuleData: BytesLike;
export let hubLibs: LensHubLibraryAddresses;
export let eventsLib: Events;
export let moduleGlobals: ModuleGlobals;
export let followNFTImpl: FollowNFT;
export let collectNFTImpl: CollectNFT;
export let freeCollectModule: FreeCollectModule;

export let auctionCollectModule: AuctionCollectModule;
export let aaveLimitedFeeCollectModule: AaveLimitedFeeCollectModule;

export function makeSuiteCleanRoom(name: string, tests: () => void) {
  describe(name, () => {
    beforeEach(async function () {
      await takeSnapshot();
    });
    tests();
    afterEach(async function () {
      await revertToSnapshot();
    });
  });
}

before(async function () {
  chainId = (await ethers.provider.getNetwork()).chainId;
  abiCoder = ethers.utils.defaultAbiCoder;
  accounts = await ethers.getSigners();
  deployer = accounts[0];
  governance = accounts[1];
  proxyAdmin = accounts[2];
  treasury = accounts[3];
  user = accounts[4];
  anotherUser = accounts[5];
  thirdUser = accounts[6];
  publisher = accounts[7];
  feeRecipient = accounts[8];
  userTwo = accounts[9];

  userAddress = await user.getAddress();
  userTwoAddress = await userTwo.getAddress();
  treasuryAddress = await treasury.getAddress();

  // Deployment
  moduleGlobals = await new ModuleGlobals__factory(deployer).deploy(
    governance.address,
    treasury.address,
    TREASURY_FEE_BPS
  );
  const publishingLogic = await new PublishingLogic__factory(deployer).deploy();
  const interactionLogic = await new InteractionLogic__factory(deployer).deploy();
  const profileTokenURILogic = await new ProfileTokenURILogic__factory(deployer).deploy();
  hubLibs = {
    '@aave/lens-protocol/contracts/libraries/PublishingLogic.sol:PublishingLogic':
      publishingLogic.address,
    '@aave/lens-protocol/contracts/libraries/InteractionLogic.sol:InteractionLogic':
      interactionLogic.address,
    '@aave/lens-protocol/contracts/libraries/ProfileTokenURILogic.sol:ProfileTokenURILogic':
      profileTokenURILogic.address,
  };

  // Here, we pre-compute the nonces and addresses used to deploy the contracts.
  const nonce = await deployer.getTransactionCount();
  // nonce + 0 is follow NFT impl
  // nonce + 1 is collect NFT impl
  // nonce + 2 is impl
  // nonce + 3 is hub proxy

  const hubProxyAddress = computeContractAddress(deployer.address, nonce + 3); // '0x' + keccak256(RLP.encode([deployerAddress, hubProxyNonce])).substr(26);

  followNFTImpl = await new FollowNFT__factory(deployer).deploy(hubProxyAddress);
  collectNFTImpl = await new CollectNFT__factory(deployer).deploy(hubProxyAddress);

  lensHubImpl = await new LensHub__factory(hubLibs, deployer).deploy(
    followNFTImpl.address,
    collectNFTImpl.address
  );

  const data = lensHubImpl.interface.encodeFunctionData('initialize', [
    LENS_HUB_NFT_NAME,
    LENS_HUB_NFT_SYMBOL,
    governance.address,
  ]);
  const proxy = await new TransparentUpgradeableProxy__factory(deployer).deploy(
    lensHubImpl.address,
    proxyAdmin.address,
    data
  );

  // Connect the hub proxy to the LensHub factory and the user for ease of use.
  lensHub = LensHub__factory.connect(proxy.address, deployer);

  // Currency
  currency = await new Currency__factory(deployer).deploy();
  currencyTwo = await new Currency__factory(deployer).deploy();
  aCurrency = await new ACurrency__factory(deployer).deploy();

  // LendingPool
  lendingPool = await new MockLendingPool__factory(deployer).deploy(
    currency.address,
    aCurrency.address
  );

  // Currency whitelisting
  await expect(
    moduleGlobals.connect(governance).whitelistCurrency(currency.address, true)
  ).to.not.be.reverted;

  // Modules used for testing purposes
  freeCollectModule = await new FreeCollectModule__factory(deployer).deploy(lensHub.address);
  await expect(
    lensHub.connect(governance).whitelistCollectModule(freeCollectModule.address, true)
  ).to.not.be.reverted;

  // Collect modules
  auctionCollectModule = await new AuctionCollectModule__factory(deployer).deploy(
    lensHub.address,
    moduleGlobals.address
  );
  aaveLimitedFeeCollectModule = await new AaveLimitedFeeCollectModule__factory(deployer).deploy(
    lensHub.address,
    moduleGlobals.address,
    lendingPool.address
  );

  await expect(
    lensHub.connect(governance).whitelistCollectModule(auctionCollectModule.address, true)
  ).to.not.be.reverted;

  await expect(
    lensHub.connect(governance).whitelistCollectModule(aaveLimitedFeeCollectModule.address, true)
  ).to.not.be.reverted;

  // Unpausing protocol
  await expect(lensHub.connect(governance).setState(ProtocolState.Unpaused)).to.not.be.reverted;

  // Profile creator whitelisting
  await expect(
    lensHub.connect(governance).whitelistProfileCreator(deployer.address, true)
  ).to.not.be.reverted;

  // Event library deployment is only needed for testing and is not reproduced in the live environment
  eventsLib = await new Events__factory(deployer).deploy();
});
