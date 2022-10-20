// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {BaseCollectModuleInitData, BaseProfilePublicationData, AbstractCollectModule} from '../collect/AbstractCollectModule.sol';

/**
 * @title BaseFeeCollectModule
 * @author Lens Protocol
 *
 * @notice This is a base Lens CollectModule implementation, allowing customization of time to collect,
 * number of collects and whether only followers can collect.
 *
 * You can build your own collect modules by inheriting from AbstractCollectModule and adding your
 * functionality along with getPublicationData function.
 */
contract BaseFeeCollectModule is AbstractCollectModule {
    constructor(address hub, address moduleGlobals) AbstractCollectModule(hub, moduleGlobals) {}

    /**
     * @notice This collect module levies a fee on collects and supports referrals. Thus, we need to decode data.
     *
     * @param data The arbitrary data parameter, decoded into:
     *      uint160 amount: The currency total amount to levy.
     *      uint96 collectLimit: The maximum amount of collects.
     *      address currency: The currency address, must be internally whitelisted.
     *      uint16 referralFee: The referral fee to set.
     *      bool followerOnly: Whether only followers should be able to collect.
     *      uint72 endTimestamp: The end timestamp after which collecting is impossible.
     *      RecipientData[] recipients: Array of RecipientData items to split collect fees across multiple recipients.
     *
     * @return An abi encoded bytes parameter, which is the same as the passed data parameter.
     */
    function initializePublicationCollectModule(
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) external virtual onlyHub returns (bytes memory) {
        BaseCollectModuleInitData memory baseInitData = abi.decode(
            data,
            (BaseCollectModuleInitData)
        );
        _validateBaseInitData(baseInitData);
        _storeBasePublicationCollectParameters(profileId, pubId, baseInitData);
        return data;
    }

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
        return getBasePublicationData(profileId, pubId);
    }
}
