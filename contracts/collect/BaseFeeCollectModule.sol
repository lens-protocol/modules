// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {BaseProfilePublicationData, AbstractCollectModule} from './AbstractCollectModule.sol';

/**
 * @title BaseFeeCollectModule
 * @author Lens Protocol
 *
 * @notice This is a base Lens CollectModule implementation, allowing customization of time to collect, number of collects
 * and whether only followers can collect.
 * You can build your own collect modules by inheriting from AbstractCollectModule like this and adding your functionality along with getPublicationData function.
 */
contract BaseFeeCollectModule is AbstractCollectModule {
    constructor(address hub, address moduleGlobals) AbstractCollectModule(hub, moduleGlobals) {}

    /**
     * @notice Returns the publication data for a given publication, or an empty struct if that publication was not
     * initialized with this module.
     *
     * @param profileId The token ID of the profile mapped to the publication to query.
     * @param pubId The publication ID of the publication to query.
     *
     * @return The BaseProfilePublicationData struct mapped to that publication.
     */
    function getPublicationData(uint256 profileId, uint256 pubId)
        external
        view
        virtual
        returns (BaseProfilePublicationData memory)
    {
        return _getPublicationData(profileId, pubId);
    }
}
