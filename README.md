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

## Coverage

1. `npm run coverage` for Hardhat coverage report
2. `forge coverage` for Foundry coverage report

# Modules

## Collect modules

- [**Aave Fee Collect Module**](./contracts/collect/AaveFeeCollectModule.sol): Extend the LimitedFeeCollectModule to deposit all received fees into the Aave Polygon Market (if applicable for the asset) and send the resulting aTokens to the beneficiary.
- [**Auction Collect Module**](./contracts/collect/AuctionCollectModule.sol): This module works by creating an English auction for the underlying publication. After the auction ends, only the auction winner is allowed to collect the publication.
- [**Updatable Ownable Fee Collect Module**](./contracts/collect/UpdatableOwnableFeeCollectModule.sol): A fee collect module that, for each publication that uses it, mints an ERC-721 ownership-NFT to its author. Whoever owns the ownership-NFT has the rights to update the parameters required to do a successful collect operation over its underlying publication.

## Follow modules

## Reference modules

- [**Degrees Of Separation Reference Module**](./contracts/reference/DegreesOfSeparationReferenceModule.sol): This reference module allows to set a degree of separation `n`, and then allows to comment/mirror only to profiles that are at most at `n` degrees of separation from the author of the root publication. 
- [**Token Gated Reference Module**](./contracts/reference/TokenGatedReferenceModule.sol): A reference module that validates that the user who tries to reference has a required minimum balance of ERC20/ERC721 token.
