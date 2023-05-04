export const MAX_UINT256 = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
export const WETH_ADDRESS = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';
export const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
export const ONE_DAY = 86400;
export const POOL_ADDRESSES_PROVIDER_ADDRESS = '0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb';
export const POOL_ADDRESS = '0x794a61358D6845594F94dc1DB02A252b5b4814aD';

// Fetched from $npx hardhat node, account # 7
export const FAKE_PRIVATEKEY = '0xa2e0097c961c67ec197b6865d7ecea6caffc68ebeb00e6050368c8f67fc9c588';

export const HARDHAT_CHAINID = 31337;

export enum PubType {
  Post,
  Comment,
  Mirror,
  Nonexistent,
}

export const CAMPAIGN_MERKLE_LEAF = {
  interest: 'ART_ENTERTAINMENT__MUSIC',
  root: '0xb6caf994e3edd909e5d47ec6351245ae6bdcc75058df6f053a5b62ecbc719895',
  profileId: '0x01',
  proof: [
    '0x3c4386eaf082514302ddab653a5b8f9b9ac704ca897ad1c0515407ca6d1f9c4b',
    '0x70640be0cb8df2f12d96150a9ab7e36bee600058353267866b69c49aa244daa6',
    '0x828a6ef31f191765ea2154af6f57c97468dc1d53731aa34c246184c6737ddb1b',
    '0x278fc646965283308bc0a1a871815a47997498943062882795040dd43ed92dd4',
    '0xf9e4fb5f099251e7224b65ffc8cdcc0246b2e642d0c22072f97e44edab7f792b',
    '0xc850b6b84de2247da1cb8b0d6216a0a30e2ac21dbb3be39cc97fce8b1298faa8',
    '0x14e2b380475b14e347ab01bb5e6a06bf7a1588120c2eaaf27a67aa8dc6dd3da9'
  ],
  index: 15
};
