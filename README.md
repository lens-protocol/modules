# lens-modules

Repository for adding Lens Protocol collect, follow and reference modules.

**To have your module added to Lens Testnet or Mainnet please open a PR and follow the instructions here: #TODO**

## Installation

1. `npm install`
2. If you also want to use Foundry - follow the Foundry installation instructions [here](https://getfoundry.sh/).

## Testing

This repository contains both - Hardhat and Foundry tests. Foundry will be used for all future modules, and existing modules will be migrated to Foundry testing suite.

### Hardhat

1. `npm run test` will compile and run the Hardhat tests suite

### Foundry

1. `forge test` will compile and run the Foundry tests suite.

### Foundry tests against forks

1. Edit `TESTING_FORK` .env variable to be one of `mainnet/testnet/sandbox` and fill the rest of .env (`FOUNDRY` section)
2. If a module is already deployed and its address exists in `addresses.json` - tests will be run against that deployment. If there is no module in json - a new local instance of the module will be deployed. Remove the module key from `addresses.json` if you want to force testing a local module deployment.
3. Run `forge test` to fork the chosen network and test against existing LensHub contracts.

## Deployment

1. Make sure to fill in the `.env` using `.env.example` (the `Foundry` section). You can specify either a `MNEMONIC` or a single `PRIVATE_KEY` (make sure to include both variables, even if one of them is an empty string)
2. Run deployment script with a command like `bash script/deploy-module.sh testnet StepwiseCollectModule` from the project root folder (e.g. to deploy `StepwiseCollectModule` on `testnet`).
3. Follow the on-screen instructions to verify if everything is correct and confirm deployment & contract verification.
4. If only the verification is needed of an existing deployed contract - use the `--verify-only` flag followed by ABI-Encoded constructor args.

### Deployment of LZGated* Modules
All the hardhat tasks related to the deployment of `LZGatedFollowModule`, `LZGatedReferenceModule`, and `LZGatedCollectModule` can be found under [**tasks/lz-gated/**](./tasks/lz-gated)

First, we deploy the modules on the source chain (ex: `mumbai`) and we deploy our `LZGatedProxy` contract to all the remote chains we want to support (ex: `goerli`). Finally, we set the trusted remotes for each module. All the lz config can be found under [**tasks/lz-gated/config.ts**](./tasks/lz-gated/config.ts).

Contract addresses for new deployments will be written to `addresses.json`. For the contracts deployed to remote chains, a special property `lz` contains an object with those contract addresses.

1. deploy our modules on the same chain as the lens protocol, using the mock sandbox governance contract to whitelist.
```
npx hardhat deploy-modules --hub 0x7582177F9E536aB0b6c721e11f383C326F2Ad1D5 --mock-sandbox-governance 0x1677d9cc4861f1c85ac7009d5f06f49c928ca2ad --network mumbai
```
2. deploy our `LZGatedProxy` contract on all the remote chains we want to support
```
npx hardhat deploy-proxy --network goerli --sandbox true --hub 0x7582177F9E536aB0b6c721e11f383C326F2Ad1D5
```

3. set our trusted remotes
```
npx hardhat set-trusted-remotes --network mumbai --sandbox true
```

## Deployment addresses in `addresses.json`

The `addresses.json` file in root contains all existing deployed contracts on all of target environments (mainnet/testnet/sandbox) on corresponding chains.
After a successful module deployment the new address will be added to `addresses.json`, overwriting the existing one (the script will ask for confirmation if you want to redeploy an already existing deployment).

## Coverage

1. `npm run coverage` for Hardhat coverage report
2. `forge coverage` for Foundry coverage report

# Modules

## Collect modules

- [**Aave Fee Collect Module**](./contracts/collect/AaveFeeCollectModule.sol): Extend the LimitedFeeCollectModule to deposit all received fees into the Aave Polygon Market (if applicable for the asset) and send the resulting aTokens to the beneficiary.
- [**Auction Collect Module**](./contracts/collect/AuctionCollectModule.sol): This module works by creating an English auction for the underlying publication. After the auction ends, only the auction winner is allowed to collect the publication.
- [**Base Fee Collect Module**](./contracts/collect/base/BaseFeeCollectModule.sol): An abstract base fee collect module contract which can be used to construct flexible fee collect modules using inheritance.
- [**Multirecipient Fee Collect Module**](./contracts/collect/MultirecipientFeeCollectModule.sol): Fee Collect module that allows multiple recipients (up to 5) with different proportions of fees payout.
- [**Simple Fee Collect Module**](./contracts/collect/SimpleFeeCollectModule.sol): A simple fee collect module implementation, as an example of using base fee collect module abstract contract.
- [**Updatable Ownable Fee Collect Module**](./contracts/collect/UpdatableOwnableFeeCollectModule.sol): A fee collect module that, for each publication that uses it, mints an ERC-721 ownership-NFT to its author. Whoever owns the ownership-NFT has the rights to update the parameters required to do a successful collect operation over its underlying publication.
- [**LayerZero Gated Collect Module**](./contracts/collect/LZGatedCollectModule.sol): A Lens Collect Module that allows publication creators to gate who can collect their post with ERC20 or ERC721 balances held on other chains. To execute a collect on a post that has this module set, the collector must generate the signature for `LensHub#collectWithSig` and call `#relayCollectWithSig` on the `LZGatedProxy` contract deployed on the chain where the token balance check is done.

## Follow modules
- [**LayerZero Gated Follow Module**](./contracts/follow/LZGatedFollowModule.sol): A Lens Follow Module that allows profile holders to gate their following with ERC20 or ERC721 balances held on other chains. To execute a follow on a profile that has this module set, the follower must generate the signature for `LensHub#followWithSig` and call `#relayFollowWithSig` on the `LZGatedProxy` contract deployed on the chain where the token balance check is done.

## Reference modules

- [**Degrees Of Separation Reference Module**](./contracts/reference/DegreesOfSeparationReferenceModule.sol): This reference module allows to set a degree of separation `n`, and then allows to comment/mirror only to profiles that are at most at `n` degrees of separation from the author of the root publication.
- [**Token Gated Reference Module**](./contracts/reference/TokenGatedReferenceModule.sol): A reference module that validates that the user who tries to reference has a required minimum balance of ERC20/ERC721 token.
- [**LayerZero Gated Reference Module**](./contracts/reference/LZGatedReferenceModule.sol): A Lens Reference Module that allows publication creators to gate who can comment/mirror their post with ERC20 or ERC721 balances held on other chains. To execute a comment or mirror on a post that has this module set, the commentor/mirrorer must generate the signature for `LensHub#commentWithSig`/`LensHub#mirrorWithSig` and call `#relayCommentWithSig`/`#relayMirrorWithSig` on the `LZGatedProxy` contract deployed on the chain where the token balance check is done.
