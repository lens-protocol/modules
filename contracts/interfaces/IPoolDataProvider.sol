// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IPoolDataProvider {
    /**
     * @notice Returns the configuration data of the reserve.
     * @dev Not returning borrow and supply caps for compatibility, nor pause flag.
     * @param asset The address of the underlying asset of the reserve.
     * @return decimals The number of decimals of the reserve.
     * @return ltv The ltv of the reserve.
     * @return liquidationThreshold The liquidationThreshold of the reserve.
     * @return liquidationBonus The liquidationBonus of the reserve.
     * @return reserveFactor The reserveFactor of the reserve.
     * @return usageAsCollateralEnabled True if the usage as collateral is enabled, false otherwise.
     * @return borrowingEnabled True if borrowing is enabled, false otherwise.
     * @return stableBorrowRateEnabled True if stable rate borrowing is enabled, false otherwise.
     * @return isActive True if it is active, false otherwise.
     * @return isFrozen True if it is frozen, false otherwise.
     **/
    function getReserveConfigurationData(address asset)
        external
        view
        returns (
            uint256 decimals,
            uint256 ltv,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            uint256 reserveFactor,
            bool usageAsCollateralEnabled,
            bool borrowingEnabled,
            bool stableBorrowRateEnabled,
            bool isActive,
            bool isFrozen
        );
}
