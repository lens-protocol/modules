// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {ERC4626} from 'solmate/src/mixins/ERC4626.sol';
import {ERC20} from 'solmate/src/tokens/ERC20.sol';

contract MockVault is ERC4626 {
    constructor(ERC20 _asset) ERC4626(_asset, 'MockVault Shares', 'MVS') {}

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }
}
