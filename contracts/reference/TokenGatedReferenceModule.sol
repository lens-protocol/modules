// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IReferenceModule} from '@aave/lens-protocol/contracts/interfaces/IReferenceModule.sol';
import {ModuleBase} from '@aave/lens-protocol/contracts/core/modules/ModuleBase.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';

interface IToken {
    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title TokenGatedReferenceModule
 * @author Lens Protocol
 *
 * @notice // TODO
 */
contract TokenGatedReferenceModule is ModuleBase, IReferenceModule {
    constructor(address hub) ModuleBase(hub) {}

    error NotEnoughBalance();

    mapping(uint256 => mapping(uint256 => address)) internal _tokenAddressByPublicationByProfile;

    /**
     * @dev There is nothing needed at initialization.
     */
    function initializeReferenceModule(
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) external override returns (bytes memory) {
        // TODO: Maybe add a min threshold
        _tokenAddressByPublicationByProfile[profileId][pubId] = abi.decode(data, (address));
        return data;
    }

    /**
     * @notice Validates that the commenting profile's owner is a follower.
     *
     * NOTE: We don't need to care what the pointed publication is in this context.
     */
    function processComment(
        uint256 profileId,
        uint256 profileIdPointed,
        uint256 pubIdPointed,
        bytes calldata data
    ) external view override {
        _validateTokenBalance(profileId, profileIdPointed, pubIdPointed);
    }

    /**
     * @notice Validates that the commenting profile's owner is a follower.
     *
     * NOTE: We don't need to care what the pointed publication is in this context.
     */
    function processMirror(
        uint256 profileId,
        uint256 profileIdPointed,
        uint256 pubIdPointed,
        bytes calldata data
    ) external view override {
        _validateTokenBalance(profileId, profileIdPointed, pubIdPointed);
    }

    function _validateTokenBalance(
        uint256 profileId,
        uint256 profileIdPointed,
        uint256 pubIdPointed
    ) internal view {
        if (
            IToken(_tokenAddressByPublicationByProfile[profileIdPointed][pubIdPointed]).balanceOf(
                IERC721(HUB).ownerOf(profileId)
            ) == 0
        ) {
            revert NotEnoughBalance();
        }
    }
}
