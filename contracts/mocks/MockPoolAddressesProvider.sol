// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.10;

contract MockPoolAddressesProvider {
    address public pool;

    constructor(address _pool) {
        pool = _pool;
    }

    function getPool() public view returns (address) {
        return pool;
    }
}
