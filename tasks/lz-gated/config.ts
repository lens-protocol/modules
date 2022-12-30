export const LZ_CONFIG = {
  "mumbai": {
    "chainId": 10109,
    "endpoint": "0xf69186dfBa60DdB133E91E9A4B5673624293d8F8",
    "remotes": ["goerli"]
  },
  "goerli": {
    "chainId": 10121,
    "endpoint": "0xbfD2135BFfbb0B5378b56643c2Df8a87552Bfa23",
    "remote": "mumbai"
  }
};

// all the constants below should change per setup

// https://hq.decent.xyz/5/Editions/0xBbD9a6186C084F7148FA9787E94828faF769c9A3
export const TOKEN_CONTRACT = '0xBbD9a6186C084F7148FA9787E94828faF769c9A3'; // the ERC721 for token gate
export const TOKEN_THRESHOLD = '1'; // one token required to follow
export const TOKEN_CHAIN_ID = LZ_CONFIG.goerli.chainId; // where our `TOKEN_CONTRACT` lives (goerli)

// https://docs.lens.xyz/docs/deployed-contract-addresses#sandbox-mumbai-testnet-addresses
export const SANDBOX_USER_PROFILE_ID = '322'; // thereisnosecondbest2.test
export const SANDBOX_GATED_COLLECT_PUB_ID = 5;
export const SANDBOX_GATED_REFERENCE_PUB_ID = 6;

export const SAMPLE_CONTENT_URI = 'ipfs://QmVjCtnpFKZwpQUNYkP7nR8dDA1Q3Tv3bWUFozRE4EnaGS/Teddies2067.png';
