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

// different root from above
export const CAMPAIGN_MERKLE_LEAF_TWO = {
  interest: 'CRYPTO__DEFI',
  root: '0x7a358b67a379eaabc13d1f3329ac75da3059787c331bb070897c5bd3859f7744',
  profileId: '0x02',
  proof: [
    '0xa6442d8ab90212669d3375ee7dd4af73ffcafee469427ff8277f1602b27cc784',
    '0x9b4fdc112c0841f1fb38de898028d6b32e5145cea6a9f377bb220ea45270f378',
    '0xffedb9dcbf76b3ac831b2a634879b8dda1f8a30c61c4a55e07c9ab59f7e6199c',
    '0x01d8c1519c0dc62acc6fc7d3e7771c70cc61a189340593dc2697268819a82884',
    '0xe7b555c5e5454fcf627852662ea55b2b0fd3573c14027e874a52279ba961b75b',
    '0x23f78edc4ab037f8e136f0e413ea38ac3da9466fad334205542d0e063e000c69',
    '0xa106e5a265191ca8f082c8aeb72f0e54f7533aab843f546e18af5b1f92ea54a5'
  ],
  index: 82
};

// same root as above
export const CAMPAIGN_MERKLE_LEAF_THREE = {
  interest: 'CRYPTO__DEFI',
  root: '0x7a358b67a379eaabc13d1f3329ac75da3059787c331bb070897c5bd3859f7744',
  profileId: '0x03',
  proof: [
    '0x9484b314cc336e3a780c22c5da3ec01f64e916f68a4e24d647eb045f5f3633b0',
    '0xface71a988488daeccc5492274e47e67b29f6bcb095ecddb2294f679fef97bf6',
    '0x446658c65cc8c8c6d832cbb9ada55b178343a34a3d7d0131ae8124c82edd8f25',
    '0x8547ab67cd3779155bfbef0559f26becd3b6fee896d9e173a8c04d64fbdb9208',
    '0xf2bc69d25271dfd7603ddbb0207b944ab44e0a1b3dae6295ae5ac1c1401a9807',
    '0x23f78edc4ab037f8e136f0e413ea38ac3da9466fad334205542d0e063e000c69',
    '0xa106e5a265191ca8f082c8aeb72f0e54f7533aab843f546e18af5b1f92ea54a5'
  ],
  index: 63
};
