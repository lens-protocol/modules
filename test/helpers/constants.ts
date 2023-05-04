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
  interest: 'ART_ENTERTAINMENT__ART',
  root: '0x6a49f3b42906e3057e364d5f79f3fa1b79384f5972d419c34409ab21c7c8fe0d',
  profileId: '0x01',
  proof: [
    '0x15dc9d7be7cd1a8d41bd4fabf19e46d4c293febf45e5463736ac05dd2814a0e1',
    '0xadfeddbf3926412434d19207d4cef920f84724e866531e6e4cd19aa174ba3992',
    '0x02d1ce0f901eb9add6090983d69c2187b9890d9ee89b4549d4c266008c79ccb2',
    '0x1aba26e23f1b3227f0e27ab678cb86502fc6e4040afec62bc2710237017f790f',
    '0x3bcdc5b0b0dd25120c87f9c145786a0393c210ef3f421253013e0fc510eded22',
    '0x84880d23e9b2fe469eb3d2a0876f8073082af6b64f10ef149724dd640a709f3e',
    '0x8d03617b07325c098f3ef1d2822de7ddb74597d9074bb445d4e7445958e295bd',
  ],
  index: 15,
};
