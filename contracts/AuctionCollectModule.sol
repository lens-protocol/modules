// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.10;

import {DataTypes} from '@aave/lens-protocol/contracts/libraries/DataTypes.sol';
import {Errors} from '@aave/lens-protocol/contracts/libraries/Errors.sol';
import {FeeModuleBase} from '@aave/lens-protocol/contracts/core/modules/FeeModuleBase.sol';
import {FollowValidationModuleBase} from '@aave/lens-protocol/contracts/core/modules/FollowValidationModuleBase.sol';
import {ICollectModule} from '@aave/lens-protocol/contracts/interfaces/ICollectModule.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {ILensHub} from '@aave/lens-protocol/contracts/interfaces/ILensHub.sol';
import {IModuleGlobals} from '@aave/lens-protocol/contracts/interfaces/IModuleGlobals.sol';
import {ModuleBase} from '@aave/lens-protocol/contracts/core/modules/ModuleBase.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/**
 * @notice A struct containing the necessary data to execute collect auctions.
 *
 * @param availableSinceTimestamp The UNIX timestamp after bids can start to be placed.
 * @param duration The seconds that the auction will last after the first bid has been placed.
 * @param minTimeAfterBid The minimum time, in seconds, that must always remain between last bid's timestamp
 *        and `endTimestamp`. This restriction could make `endTimestamp` to be re-computed and updated.
 * @param endTimestamp The end of auction UNIX timestamp after which bidding is impossible. Computed inside contract.
 * @param reservePrice The minimum bid price accepted.
 * @param minBidIncrement The minimum amount by which a new bid must overcome the last bid.
 * @param winningBid The winning bid amount.
 * @param referralFee The percentage of the fee that will be transferred to the referrer in case of having one.
 *        Measured in basis points, each basis point represents 0.01%.
 * @param currency The currency in which the bids are denominated.
 * @param recipient The recipient of the auction's winner bid amount.
 * @param winner The current auction winner.
 * @param onlyFollowers Indicates whether followers are the only allowed to bid, and collect, or not.
 * @param collected Indicates whether the publication has been collected or not.
 * @param feeProcessed Indicates whether the auction fee was already processed or not.
 * @param referrerProfileIdOf Maps a given bidder's address to its referrer profile ID. Referrer matching publication's
 *        profile ID means no referral, referrer being zero means that bidder has not bidded yet on this auction.
 *        The referrer is set through, and only through, the first bidder's bid on each auction.
 */
struct AuctionData {
    uint256 availableSinceTimestamp;
    uint256 duration;
    uint256 minTimeAfterBid;
    uint256 endTimestamp;
    uint256 reservePrice;
    uint256 minBidIncrement;
    uint256 winningBid;
    uint16 referralFee;
    address currency;
    address recipient;
    address winner;
    bool onlyFollowers;
    bool collected;
    bool feeProcessed;
    mapping(address => uint256) referrerProfileIdOf;
}

/**
 * @title AuctionCollectModule
 * @author Lens Protocol
 *
 * @notice This module works by creating an auction for the underlying publication. After the auction ends, only the
 * auction winner is allowed to collect the publication.
 *
 */
contract AuctionCollectModule is ICollectModule, FeeModuleBase, FollowValidationModuleBase {
    using SafeERC20 for IERC20;

    error ActiveAuction();
    error UnavailableAuction();
    error NoFeeToProcess();
    error InsufficientBidAmount();
    error InvalidBidder();
    error LimitPriceExceeded();

    event BidPlaced(
        uint256 profileId,
        uint256 pubId,
        uint256 referrerProfileId,
        uint256 amount,
        address bidder,
        uint256 endTimestamp,
        uint256 timestamp
    );
    event FeeProcessed(uint256 profileId, uint256 pubId, uint256 timestamp);

    // keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)');
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    // keccak256('1');
    bytes32 internal constant EIP712_VERSION_HASH =
        0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6;

    // keccak256('AuctionCollectModule');
    bytes32 internal constant EIP712_NAME_HASH =
        0xba22081bc5c1d1ec869a162d29727734a7f22077aed8b8d52bc9a23e7c5ed6ef;

    // keccak256('BidWithSig(uint256 profileId,uint256 pubId,uint256 amount,uint256 nonce,uint256 deadline)');
    bytes32 internal constant BID_WITH_SIG_TYPEHASH =
        0x6787ef5fb2ac5e44122548b1bcf4c59afc7bb9c5765aaecc8466ab9f7b5fb63c;

    // keccak256(
    // 'BidWithIncrementWithSig(uint256 profileId,uint256 pubId,uint256 increment,uint256 bidPriceLimit,uint256 nonce,uint256 deadline)'
    // );
    bytes32 internal constant BID_WITH_INCREMENT_WITH_SIG_TYPEHASH =
        0xfb50d4e083d204e8884077ef514e2845378f8eb854553d6095159e4b6c84a5c2;

    mapping(address => uint256) public nonces;

    // TODO: Uncomment this and make changes to use memory struct instead of storage when possible
    // mapping(uint256 => mapping(uint256 => mapping(address => uint256)))
    //     public referrerProfileIdByBidderByPublicationByProfile;

    mapping(uint256 => mapping(uint256 => AuctionData)) internal _dataByPublicationByProfile;

    constructor(address hub, address moduleGlobals) ModuleBase(hub) FeeModuleBase(moduleGlobals) {}

    /**
     * @dev See `AuctionData` struct's natspec in order to understand `data` decoded values.
     *
     * @inheritdoc ICollectModule
     */
    function initializePublicationCollectModule(
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) external override onlyHub returns (bytes memory) {
        (
            uint256 availableSinceTimestamp,
            uint256 duration,
            uint256 minTimeAfterBid,
            uint256 reservePrice,
            uint256 minBidIncrement,
            uint16 referralFee,
            address currency,
            address recipient,
            bool onlyFollowers
        ) = abi.decode(
                data,
                (uint256, uint256, uint256, uint256, uint256, uint16, address, address, bool)
            );
        if (
            duration == 0 ||
            duration < minTimeAfterBid ||
            !IModuleGlobals(MODULE_GLOBALS).isCurrencyWhitelisted(currency) ||
            referralFee > BPS_MAX
        ) {
            revert Errors.InitParamsInvalid();
        }
        _initAuction(
            profileId,
            pubId,
            availableSinceTimestamp,
            duration,
            minTimeAfterBid,
            reservePrice,
            minBidIncrement,
            referralFee,
            currency,
            recipient,
            onlyFollowers
        );
        return data;
    }

    /**
     * @dev Auction initialization logic moved to this function to avoid stack too deep error.
     */
    function _initAuction(
        uint256 profileId,
        uint256 pubId,
        uint256 availableSinceTimestamp,
        uint256 duration,
        uint256 minTimeAfterBid,
        uint256 reservePrice,
        uint256 minBidIncrement,
        uint16 referralFee,
        address currency,
        address recipient,
        bool onlyFollowers
    ) internal {
        AuctionData storage auction = _dataByPublicationByProfile[profileId][pubId];
        auction.availableSinceTimestamp = availableSinceTimestamp;
        auction.duration = duration;
        auction.minTimeAfterBid = minTimeAfterBid;
        auction.reservePrice = reservePrice;
        auction.minBidIncrement = minBidIncrement;
        auction.referralFee = referralFee;
        auction.currency = currency;
        auction.recipient = recipient;
        auction.onlyFollowers = onlyFollowers;
    }

    /**
     * @notice Processes a collect action for the given publication, this can only be called by the hub.
     *
     * @dev Process the collect by ensuring:
     *  1. Underlying publication's auction has finished.
     *  2. Parameters passed matches expected values (collector is the winner, correct referral info & no custom data).
     *  3. Publication has not been collected yet.
     * This function will also process collect fees if they have not been already processed through `processCollectFee`.
     *
     * @inheritdoc ICollectModule
     */
    function processCollect(
        uint256 referrerProfileId,
        address collector,
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) external override onlyHub {
        AuctionData storage auction = _dataByPublicationByProfile[profileId][pubId];
        if (block.timestamp <= auction.endTimestamp) {
            revert ActiveAuction();
        }
        if (
            collector != auction.winner ||
            referrerProfileId != auction.referrerProfileIdOf[collector] ||
            data.length != 0
        ) {
            // Prevents `LensHub` from emiting `Collected` event with wrong parameters.
            revert Errors.ModuleDataMismatch();
        }
        if (auction.collected) {
            // Checking that the `collector` is not `address(0)` was already done by `LensHub`.
            revert Errors.CollectNotAllowed();
        }
        if (auction.onlyFollowers) {
            // TODO: If onlyFollowers enabled, we ask for it for each bid, maybe we can avoid it here unless we want to
            //       enforce the collector to keep following at collection time. Seems unnecesary, as the collector can
            //       unfollow right after collecting anyways. Maybe worth removing the validation to make it cheaper.
            _checkFollowValidity(profileId, collector);
        }
        auction.collected = true;
        if (!auction.feeProcessed) {
            _processCollectFee(profileId, pubId);
        }
    }

    /**
     * @notice Processes the collect fees using the auction winning bid funds and taking into account referrer and
     * treasury fees if necessary.
     *
     * @dev This function allows anyone to process the collect fees, not needing to wait for `processCollect` to be
     * called, as long as the auction has finished, has a winner and the publication has not been collected yet.
     * Why is this function necessary? Suppose someone wins the auction, but for some reason never calls the LensHub's
     * `collect`. That would make `processCollect` of this module never been called and, consequently, collect wouldn't
     * be processed, locking the fees in this contract forever.
     *
     * @param profileId The token ID of the profile associated with the underlying publication.
     * @param pubId The publication ID associated with the underlying publication.
     */
    function processCollectFee(uint256 profileId, uint256 pubId) external {
        AuctionData storage auction = _dataByPublicationByProfile[profileId][pubId];
        if (block.timestamp <= auction.endTimestamp) {
            revert ActiveAuction();
        }
        if (auction.feeProcessed) {
            revert NoFeeToProcess();
        }
        _processCollectFee(profileId, pubId);
    }

    /**
     * @notice Places a bid by the given amount on the given publication's auction. If the publication is a mirror,
     * the pointed publication auction will be used, setting the mirror's profileId as referrer if it's the first bid
     * in the auction.
     * Transaction will fail if the bid offered is below auction's current best price.
     *
     * @dev It will pull the tokens from the bidder to ensure the collect fees can be processed if the bidder ends up
     * being the winner after auction ended. If a better bid is placed in the future by a different bidder, funds will
     * be automatically transferred to the previous winner.
     *
     * @param profileId The token ID of the profile associated with the publication, could be a mirror.
     * @param pubId The publication ID associated with the publication, could be a mirror.
     * @param amount The bid amount to offer.
     */
    function bid(
        uint256 profileId,
        uint256 pubId,
        uint256 amount
    ) external {
        (uint256 profileIdPointed, uint256 pubIdPointed) = _getRootPublication(profileId, pubId);
        _bid(profileIdPointed, pubIdPointed, profileId, amount, msg.sender);
    }

    /**
     * @notice Using EIP-712 signatures, places a bid by the given amount on the given publication's auction.
     * If the publication is a mirror, the pointed publication auction will be used, setting the mirror's profileId
     * as referrer if it's the first bid in the auction.
     * Transaction will fail if the bid offered is below auction's current best price.
     *
     * @dev It will pull the tokens from the bidder to ensure the collect fees can be processed if the bidder ends up
     * being the winner after auction ended. If a better bid is placed in the future by a different bidder, funds will
     * be automatically transferred to the previous winner.
     *
     * @param profileId The token ID of the profile associated with the publication, could be a mirror.
     * @param pubId The publication ID associated with the publication, could be a mirror.
     * @param amount The bid amount to offer.
     */
    function bidWithSig(
        uint256 profileId,
        uint256 pubId,
        uint256 amount,
        address bidder,
        DataTypes.EIP712Signature calldata sig
    ) external {
        _validateBidSignature(profileId, pubId, amount, bidder, sig, BID_WITH_SIG_TYPEHASH);
        (uint256 profileIdPointed, uint256 pubIdPointed) = _getRootPublication(profileId, pubId);
        _bid(profileIdPointed, pubIdPointed, profileId, amount, bidder);
    }

    /**
     * @notice Places a bid of the auction's current best price plus the given increment, ensuring the bidder will
     * become the auction's winner after the transaction succeed.
     * Also, has a `bidPriceLimit` value to ensure the final bidded amount does not exceed it.
     * If the publication is a mirror, the pointed publication auction will be used, setting the mirror's profileId as
     * referrer if it's the first bid in the auction.
     *
     * @dev It will pull the tokens from the bidder to ensure the collect fees can be processed if the bidder ends up
     * being the winner after auction ended. If a better bid is placed in the future by a different bidder, funds will
     * be automatically transferred to the previous winner.
     *
     * @param profileId The token ID of the profile associated with the publication, could be a mirror.
     * @param pubId The publication ID associated with the publication, could be a mirror.
     * @param increment The amount to be incremented over the auction's current best price when offering the bid.
     * @param bidPriceLimit The maximum price willing to pay for the bid, the transaction will fail if it is exceeded.
     *        Use zero if you do not want to set a price limit.
     */
    function bidWithIncrement(
        uint256 profileId,
        uint256 pubId,
        uint256 increment,
        uint256 bidPriceLimit
    ) external {
        (uint256 profileIdPointed, uint256 pubIdPointed) = _getRootPublication(profileId, pubId);
        _bid(
            profileIdPointed,
            pubIdPointed,
            profileId,
            _getBidAmountWithIncrement(profileIdPointed, pubIdPointed, increment, bidPriceLimit),
            msg.sender
        );
    }

    /**
     * @notice Using EIP-712 signatures, places a bid of the auction's current best price plus the given increment,
     * ensuring the bidder will become the auction's winner after the transaction succeed.
     * Also, has a `bidPriceLimit` value to ensure the final bidded amount does not exceed it.
     * If the publication is a mirror, the pointed publication auction will be used, setting the mirror's profileId as
     * referrer if it's the first bid in the auction.
     *
     * @dev It will pull the tokens from the bidder to ensure the collect fees can be processed if the bidder ends up
     * being the winner after auction ended. If a better bid is placed in the future by a different bidder, funds will
     * be automatically transferred to the previous winner.
     *
     * @param profileId The token ID of the profile associated with the publication, could be a mirror.
     * @param pubId The publication ID associated with the publication, could be a mirror.
     * @param increment The amount to be incremented over the auction's current best price when offering the bid.
     * @param bidPriceLimit The maximum price willing to pay for the bid, the transaction will fail if it is exceeded.
     * @param bidder The bidder address, who must be the signer of the EIP-712 signature.
     * @param sig The EIP-712 signature data.
     */
    function bidWithIncrementWithSig(
        uint256 profileId,
        uint256 pubId,
        uint256 increment,
        uint256 bidPriceLimit,
        address bidder,
        DataTypes.EIP712Signature calldata sig
    ) external {
        _validateBidWithIncrementSignature(
            profileId,
            pubId,
            increment,
            bidPriceLimit,
            bidder,
            sig,
            BID_WITH_INCREMENT_WITH_SIG_TYPEHASH
        );
        (uint256 profileIdPointed, uint256 pubIdPointed) = _getRootPublication(profileId, pubId);
        _bid(
            profileIdPointed,
            pubIdPointed,
            profileId,
            _getBidAmountWithIncrement(profileIdPointed, pubIdPointed, increment, bidPriceLimit),
            bidder
        );
    }

    /**
     * @dev Abstracts the logic to get and validate bid amount when placing a bid through increment-based functions.
     */
    function _getBidAmountWithIncrement(
        uint256 profileId,
        uint256 pubId,
        uint256 increment,
        uint256 bidPriceLimit
    ) internal view returns (uint256) {
        // TODO: Remove nested mapping to use memory variables instead of storage.
        //       Using the public referrerProfileIdByBidderByPublicationByProfile.
        AuctionData storage auction = _dataByPublicationByProfile[profileId][pubId];
        uint256 amount = (
            auction.winner == address(0) ? auction.reservePrice : auction.winningBid
        ) + increment;
        if (bidPriceLimit != 0 && amount > bidPriceLimit) {
            revert LimitPriceExceeded();
        }
        return amount;
    }

    /**
     * @notice Returns the referrer profile in the given publication's auction.
     *
     * @param profileId The token ID of the profile associated with the underlying publication.
     * @param pubId The publication ID associated with the underlying publication.
     * @param bidder The address which the referrer profile should be returned.
     *
     * @return The ID of the referrer profile. If returned value matches publication's profile ID means no referral,
     * referrer being zero means no referral but because that bidder has not bidded yet on the given auction or the
     * auction does not exist.
     */
    function getReferrerProfileIdOf(
        uint256 profileId,
        uint256 pubId,
        address bidder
    ) external view returns (uint256) {
        return _dataByPublicationByProfile[profileId][pubId].referrerProfileIdOf[bidder];
    }

    function _processCollectFee(uint256 profileId, uint256 pubId) internal {
        AuctionData storage auction = _dataByPublicationByProfile[profileId][pubId];
        auction.feeProcessed = true;
        if (auction.referrerProfileIdOf[auction.winner] == profileId) {
            _processCollectFeeWithoutReferral(auction);
        } else {
            _processCollectFeeWithReferral(auction);
        }
        emit FeeProcessed(profileId, pubId, block.timestamp);
    }

    function _processCollectFeeWithoutReferral(AuctionData storage auction) internal {
        uint256 amount = auction.winningBid;
        address currency = auction.currency;
        (address treasury, uint16 treasuryFee) = _treasuryData();
        uint256 treasuryAmount = (amount * treasuryFee) / BPS_MAX;
        uint256 adjustedAmount = amount - treasuryAmount;
        IERC20(currency).safeTransfer(auction.recipient, adjustedAmount);
        IERC20(currency).safeTransfer(treasury, treasuryAmount);
    }

    function _processCollectFeeWithReferral(AuctionData storage auction) internal {
        address collector = auction.winner;
        uint256 amount = auction.winningBid;
        address currency = auction.currency;
        uint256 referralFee = auction.referralFee;
        address treasury;
        uint256 treasuryAmount;
        // Avoids stack too deep.
        {
            uint16 treasuryFee;
            (treasury, treasuryFee) = _treasuryData();
            treasuryAmount = (amount * treasuryFee) / BPS_MAX;
        }
        uint256 adjustedAmount = amount - treasuryAmount;
        if (referralFee != 0) {
            // The reason we levy the referral fee on the adjusted amount is so that referral fees
            // don't bypass the treasury fee, in essence referrals pay their fair share to the treasury.
            uint256 referralAmount = (adjustedAmount * referralFee) / BPS_MAX;
            adjustedAmount = adjustedAmount - referralAmount;
            address referralRecipient = IERC721(HUB).ownerOf(
                auction.referrerProfileIdOf[collector]
            );
            IERC20(currency).safeTransfer(referralRecipient, referralAmount);
        }
        address recipient = auction.recipient;
        IERC20(currency).safeTransfer(recipient, adjustedAmount);
        IERC20(currency).safeTransfer(treasury, treasuryAmount);
    }

    function _bid(
        uint256 profileId,
        uint256 pubId,
        uint256 referrerProfileId,
        uint256 amount,
        address bidder
    ) internal {
        AuctionData storage auction = _dataByPublicationByProfile[profileId][pubId];
        if (
            auction.availableSinceTimestamp > block.timestamp ||
            block.timestamp > auction.endTimestamp
        ) {
            revert UnavailableAuction();
        }
        if (bidder == address(0)) {
            // TODO: Check if we want to unallow recipient/profile-owner to bid, I think does not make sense as they
            //       could always use an alt account to do so if they want to. So better to avoid unnecessary checks.
            revert InvalidBidder();
        }
        _validateBidAmount(auction, amount);
        if (auction.onlyFollowers) {
            // TODO: Evaluate if worth to do this validation on each bid or only for first bid of each bidder.
            //       Basically, we can move it inside the referrerProfileIdOf if.
            _checkFollowValidity(profileId, bidder);
        }
        if (auction.referrerProfileIdOf[bidder] == 0) {
            auction.referrerProfileIdOf[bidder] = referrerProfileId;
        }
        address lastWinner = auction.winner;
        uint256 lastWinningBid = auction.winningBid;
        auction.winner = bidder;
        auction.winningBid = amount;
        if (lastWinner == address(0)) {
            auction.endTimestamp = block.timestamp + auction.duration;
        } else {
            if (auction.endTimestamp - block.timestamp < auction.minTimeAfterBid) {
                auction.endTimestamp = block.timestamp + auction.minTimeAfterBid;
            }
            IERC20(auction.currency).safeTransferFrom(address(this), lastWinner, lastWinningBid);
        }
        IERC20(auction.currency).safeTransferFrom(bidder, address(this), amount);
        emit BidPlaced(
            profileId,
            pubId,
            auction.referrerProfileIdOf[bidder],
            amount,
            bidder,
            auction.endTimestamp,
            block.timestamp
        );
    }

    function _validateBidAmount(AuctionData storage auction, uint256 amount) internal view {
        bool hasWinner = auction.winner != address(0);
        if (
            (!hasWinner && amount < auction.reservePrice) ||
            (hasWinner &&
                (amount <= auction.winningBid ||
                    (auction.minBidIncrement > 0 &&
                        amount - auction.winningBid < auction.minBidIncrement)))
        ) {
            revert InsufficientBidAmount();
        }
    }

    function _validateBidSignature(
        uint256 profileId,
        uint256 pubId,
        uint256 value,
        address bidder,
        DataTypes.EIP712Signature calldata sig,
        bytes32 typehash
    ) internal {
        _validateRecoveredAddress(
            _calculateDigest(
                abi.encode(typehash, profileId, pubId, value, nonces[bidder]++, sig.deadline)
            ),
            bidder,
            sig
        );
    }

    function _validateBidWithIncrementSignature(
        uint256 profileId,
        uint256 pubId,
        uint256 increment,
        uint256 bidPriceLimit,
        address bidder,
        DataTypes.EIP712Signature calldata sig,
        bytes32 typehash
    ) internal {
        _validateRecoveredAddress(
            _calculateDigest(
                abi.encode(
                    typehash,
                    profileId,
                    pubId,
                    increment,
                    bidPriceLimit,
                    nonces[bidder]++,
                    sig.deadline
                )
            ),
            bidder,
            sig
        );
    }

    //TODO: Functions below could be in a lib or something like that

    function _getRootPublication(uint256 profileId, uint256 pubId)
        internal
        view
        returns (uint256, uint256)
    {
        DataTypes.PublicationStruct memory publication = ILensHub(HUB).getPub(profileId, pubId);
        if (publication.collectModule != address(0)) {
            return (profileId, pubId);
        } else {
            if (publication.profileIdPointed == 0) {
                revert Errors.PublicationDoesNotExist();
            }
            return (publication.profileIdPointed, publication.pubIdPointed);
        }
    }

    function _validateRecoveredAddress(
        bytes32 digest,
        address expectedAddress,
        DataTypes.EIP712Signature calldata sig
    ) internal view {
        if (sig.deadline < block.timestamp) {
            revert Errors.SignatureExpired();
        }
        address recoveredAddress = ecrecover(digest, sig.v, sig.r, sig.s);
        if (recoveredAddress == address(0) || recoveredAddress != expectedAddress) {
            revert Errors.SignatureInvalid();
        }
    }

    function _calculateDigest(bytes memory message) internal view returns (bytes32) {
        bytes32 digest;
        unchecked {
            digest = keccak256(
                abi.encodePacked('\x19\x01', _calculateDomainSeparator(), keccak256(message))
            );
        }
        return digest;
    }

    function _calculateDomainSeparator() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    EIP712_DOMAIN_TYPEHASH,
                    EIP712_NAME_HASH,
                    EIP712_VERSION_HASH,
                    block.chainid,
                    address(this)
                )
            );
    }
}
