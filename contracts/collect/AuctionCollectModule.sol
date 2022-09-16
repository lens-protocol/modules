// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.10;

import {DataTypes} from '@aave/lens-protocol/contracts/libraries/DataTypes.sol';
import {EIP712} from '@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol';
import {Errors} from '@aave/lens-protocol/contracts/libraries/Errors.sol';
import {FeeModuleBase} from '@aave/lens-protocol/contracts/core/modules/FeeModuleBase.sol';
import {ICollectModule} from '@aave/lens-protocol/contracts/interfaces/ICollectModule.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {IERC721Time} from '@aave/lens-protocol/contracts/core/base/IERC721Time.sol';
import {ILensHub} from '@aave/lens-protocol/contracts/interfaces/ILensHub.sol';
import {IModuleGlobals} from '@aave/lens-protocol/contracts/interfaces/IModuleGlobals.sol';
import {ModuleBase} from '@aave/lens-protocol/contracts/core/modules/ModuleBase.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/**
 * @notice A struct containing the necessary data to execute collect auctions.
 *
 * @param availableSinceTimestamp The UNIX timestamp after bids can start to be placed.
 * @param startTimestamp The UNIX timestamp of the first bid, i.e. when the auction started.
 * @param duration The seconds that the auction will last after the first bid has been placed.
 * @param minTimeAfterBid The minimum time, in seconds, that must always remain between last bid's timestamp
 * and `endTimestamp`. This restriction could make `endTimestamp` to be re-computed and updated.
 * @param endTimestamp The end of auction UNIX timestamp after which bidding is impossible. Computed inside contract.
 * @param reservePrice The minimum bid price accepted.
 * @param minBidIncrement The minimum amount by which a new bid must overcome the last bid.
 * @param winningBid The winning bid amount.
 * @param referralFee The percentage of the fee that will be transferred to the referrer in case of having one.
 * Measured in basis points, each basis point represents 0.01%.
 * @param currency The currency in which the bids are denominated.
 * @param recipient The recipient of the auction's winner bid amount.
 * @param winner The current auction winner.
 * @param onlyFollowers Indicates whether followers are the only allowed to bid, and collect, or not.
 * @param collected Indicates whether the publication has been collected or not.
 * @param feeProcessed Indicates whether the auction fee was already processed or not.
 */
struct AuctionData {
    uint64 availableSinceTimestamp;
    uint64 startTimestamp;
    uint32 duration;
    uint32 minTimeAfterBid;
    uint64 endTimestamp;
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
}

/**
 * @title AuctionCollectModule
 * @author Lens Protocol
 *
 * @notice This module works by creating an English auction for the underlying publication. After the auction ends, only
 * the auction winner is allowed to collect the publication.
 */
contract AuctionCollectModule is EIP712, FeeModuleBase, ModuleBase, ICollectModule {
    using SafeERC20 for IERC20;

    error OngoingAuction();
    error UnavailableAuction();
    error CollectAlreadyProcessed();
    error FeeAlreadyProcessed();
    error InsufficientBidAmount();

    event AuctionCreated(
        uint256 indexed profileId,
        uint256 indexed pubId,
        uint64 availableSinceTimestamp,
        uint32 duration,
        uint32 minTimeAfterBid,
        uint256 reservePrice,
        uint256 minBidIncrement,
        uint16 referralFee,
        address currency,
        address recipient,
        bool onlyFollowers
    );
    event BidPlaced(
        uint256 indexed profileId,
        uint256 indexed pubId,
        uint256 referrerProfileId,
        uint256 amount,
        uint256 followNftTokenId,
        address bidder,
        uint256 endTimestamp,
        uint256 timestamp
    );
    event FeeProcessed(uint256 indexed profileId, uint256 indexed pubId, uint256 timestamp);

    mapping(address => uint256) public nonces;

    mapping(uint256 => mapping(uint256 => AuctionData)) internal _auctionDataByPubByProfile;

    /**
     * @dev Maps a given bidder's address to its referrer profile ID. Referrer matching publication's profile ID means
     * no referral, referrer being zero means that bidder has not bidded yet on this auction.
     * The referrer is set through, and only through, the first bidder's bid on each auction.
     */
    mapping(uint256 => mapping(uint256 => mapping(address => uint256)))
        internal _referrerProfileIdByPubByProfile;

    constructor(address hub, address moduleGlobals)
        EIP712('AuctionCollectModule', '1')
        ModuleBase(hub)
        FeeModuleBase(moduleGlobals)
    {}

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
            uint64 availableSinceTimestamp,
            uint32 duration,
            uint32 minTimeAfterBid,
            uint256 reservePrice,
            uint256 minBidIncrement,
            uint16 referralFee,
            address currency,
            address recipient,
            bool onlyFollowers
        ) = abi.decode(
                data,
                (uint64, uint32, uint32, uint256, uint256, uint16, address, address, bool)
            );
        if (
            duration == 0 ||
            duration < minTimeAfterBid ||
            !_currencyWhitelisted(currency) ||
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
     * @notice If the given publication has an auction, this function returns all its information.
     *
     * @param profileId The token ID of the profile associated with the underlying publication.
     * @param pubId The publication ID associated with the underlying publication.
     *
     * @return The auction data for the given publication.
     */
    function getAuctionData(uint256 profileId, uint256 pubId)
        external
        view
        returns (AuctionData memory)
    {
        return _auctionDataByPubByProfile[profileId][pubId];
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
        if (
            block.timestamp < _auctionDataByPubByProfile[profileId][pubId].availableSinceTimestamp
        ) {
            revert UnavailableAuction();
        }
        if (
            _auctionDataByPubByProfile[profileId][pubId].startTimestamp == 0 ||
            block.timestamp <= _auctionDataByPubByProfile[profileId][pubId].endTimestamp
        ) {
            revert OngoingAuction();
        }
        if (
            collector != _auctionDataByPubByProfile[profileId][pubId].winner ||
            referrerProfileId != _referrerProfileIdByPubByProfile[profileId][pubId][collector]
        ) {
            revert Errors.ModuleDataMismatch();
        }
        if (_auctionDataByPubByProfile[profileId][pubId].collected) {
            revert CollectAlreadyProcessed();
        }
        if (_auctionDataByPubByProfile[profileId][pubId].onlyFollowers) {
            _validateFollow(
                profileId,
                collector,
                abi.decode(data, (uint256)),
                _auctionDataByPubByProfile[profileId][pubId].startTimestamp
            );
        } else if (data.length > 0) {
            // Prevents `LensHub` from emiting `Collected` event with wrong `data` parameter.
            revert Errors.ModuleDataMismatch();
        }
        _auctionDataByPubByProfile[profileId][pubId].collected = true;
        if (!_auctionDataByPubByProfile[profileId][pubId].feeProcessed) {
            _processCollectFee(profileId, pubId);
        }
    }

    /**
     * @notice Processes the collect fees using the auction winning bid funds and taking into account referrer and
     * treasury fees if necessary.
     *
     * @dev This function allows anyone to process the collect fees, not needing to wait for `processCollect` to be
     * called, as long as the auction has finished, has a winner and the publication has not been collected yet.
     *
     * @param profileId The token ID of the profile associated with the underlying publication.
     * @param pubId The publication ID associated with the underlying publication.
     */
    function processCollectFee(uint256 profileId, uint256 pubId) external {
        if (
            _auctionDataByPubByProfile[profileId][pubId].duration == 0 ||
            block.timestamp < _auctionDataByPubByProfile[profileId][pubId].availableSinceTimestamp
        ) {
            revert UnavailableAuction();
        }
        if (
            _auctionDataByPubByProfile[profileId][pubId].startTimestamp == 0 ||
            block.timestamp <= _auctionDataByPubByProfile[profileId][pubId].endTimestamp
        ) {
            revert OngoingAuction();
        }
        if (_auctionDataByPubByProfile[profileId][pubId].feeProcessed) {
            revert FeeAlreadyProcessed();
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
     * @param followNftTokenId The token ID of the Follow NFT to use if the auction is configured as followers-only.
     */
    function bid(
        uint256 profileId,
        uint256 pubId,
        uint256 amount,
        uint256 followNftTokenId
    ) external {
        (uint256 rootProfileId, uint256 rootPubId) = _getRootPublication(profileId, pubId);
        _bid(rootProfileId, rootPubId, profileId, amount, followNftTokenId, msg.sender);
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
     * @param followNftTokenId The token ID of the Follow NFT to use if the auction is configured as followers-only.
     * @param bidder The address of the bidder.
     * @param sig The EIP-712 signature for this operation.
     */
    function bidWithSig(
        uint256 profileId,
        uint256 pubId,
        uint256 amount,
        uint256 followNftTokenId,
        address bidder,
        DataTypes.EIP712Signature calldata sig
    ) external {
        _validateBidSignature(profileId, pubId, amount, followNftTokenId, bidder, sig);
        (uint256 rootProfileId, uint256 rootPubId) = _getRootPublication(profileId, pubId);
        _bid(rootProfileId, rootPubId, profileId, amount, followNftTokenId, bidder);
    }

    /**
     * @notice Returns the referrer profile in the given publication's auction.
     *
     * @param profileId The token ID of the profile associated with the underlying publication.
     * @param pubId The publication ID associated with the underlying publication.
     * @param bidder The address whose referrer profile should be returned.
     *
     * @return The ID of the referrer profile. Zero means no referral.
     */
    function getReferrerProfileIdOf(
        uint256 profileId,
        uint256 pubId,
        address bidder
    ) external view returns (uint256) {
        uint256 referrerProfileId = _referrerProfileIdByPubByProfile[profileId][pubId][bidder];
        return referrerProfileId == profileId ? 0 : referrerProfileId;
    }

    /**
     * @notice Initializes the auction struct for the given publication.
     *
     * @dev Auction initialization logic moved to this function to avoid stack too deep error.
     *
     * @param profileId The token ID of the profile associated with the underlying publication.
     * @param pubId The publication ID associated with the underlying publication.
     * @param availableSinceTimestamp The UNIX timestamp after bids can start to be placed.
     * @param duration The seconds that the auction will last after the first bid has been placed.
     * @param minTimeAfterBid The minimum time, in seconds, that must always remain between last bid's timestamp
     * and `endTimestamp`. This restriction could make `endTimestamp` to be re-computed and updated.
     * @param reservePrice The minimum bid price accepted.
     * @param minBidIncrement The minimum amount by which a new bid must overcome the last bid.
     * @param referralFee The percentage of the fee that will be transferred to the referrer in case of having one.
     * Measured in basis points, each basis point represents 0.01%.
     * @param currency The currency in which the bids are denominated.
     * @param recipient The recipient of the auction's winner bid amount.
     * @param onlyFollowers Indicates whether followers are the only allowed to bid, and collect, or not.
     */
    function _initAuction(
        uint256 profileId,
        uint256 pubId,
        uint64 availableSinceTimestamp,
        uint32 duration,
        uint32 minTimeAfterBid,
        uint256 reservePrice,
        uint256 minBidIncrement,
        uint16 referralFee,
        address currency,
        address recipient,
        bool onlyFollowers
    ) internal {
        AuctionData storage auction = _auctionDataByPubByProfile[profileId][pubId];
        auction.availableSinceTimestamp = availableSinceTimestamp;
        auction.duration = duration;
        auction.minTimeAfterBid = minTimeAfterBid;
        auction.reservePrice = reservePrice;
        auction.minBidIncrement = minBidIncrement;
        auction.referralFee = referralFee;
        auction.currency = currency;
        auction.recipient = recipient;
        auction.onlyFollowers = onlyFollowers;
        emit AuctionCreated(
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
    }

    /**
     * @notice Process the fees from the given publication's underlying auction.
     *
     * @dev It delegates the fee processing to `_processCollectFeeWithoutReferral` or `_processCollectFeeWithReferral`
     * depending if has referrer or not.
     *
     * @param profileId The token ID of the profile associated with the underlying publication.
     * @param pubId The publication ID associated with the underlying publication.
     */
    function _processCollectFee(uint256 profileId, uint256 pubId) internal {
        _auctionDataByPubByProfile[profileId][pubId].feeProcessed = true;
        uint256 referrerProfileId = _referrerProfileIdByPubByProfile[profileId][pubId][
            _auctionDataByPubByProfile[profileId][pubId].winner
        ];
        if (referrerProfileId == profileId) {
            _processCollectFeeWithoutReferral(
                _auctionDataByPubByProfile[profileId][pubId].winningBid,
                _auctionDataByPubByProfile[profileId][pubId].currency,
                _auctionDataByPubByProfile[profileId][pubId].recipient
            );
        } else {
            _processCollectFeeWithReferral(
                _auctionDataByPubByProfile[profileId][pubId].winningBid,
                _auctionDataByPubByProfile[profileId][pubId].referralFee,
                referrerProfileId,
                _auctionDataByPubByProfile[profileId][pubId].currency,
                _auctionDataByPubByProfile[profileId][pubId].recipient
            );
        }
        emit FeeProcessed(profileId, pubId, block.timestamp);
    }

    /**
     * @notice Process the fees sending the winner amount to the recipient.
     *
     * @param winnerBid The amount of the winner bid.
     * @param currency The currency in which the bids are denominated.
     * @param recipient The recipient of the auction's winner bid amount.
     */
    function _processCollectFeeWithoutReferral(
        uint256 winnerBid,
        address currency,
        address recipient
    ) internal {
        (address treasury, uint16 treasuryFee) = _treasuryData();
        uint256 treasuryAmount = (winnerBid * treasuryFee) / BPS_MAX;
        uint256 adjustedAmount = winnerBid - treasuryAmount;
        IERC20(currency).safeTransfer(recipient, adjustedAmount);
        if (treasuryAmount > 0) {
            IERC20(currency).safeTransfer(treasury, treasuryAmount);
        }
    }

    /**
     * @notice Process the fees sending the winner amount to the recipient and the corresponding referral fee to the
     * owner of the referrer profile.
     *
     * @param winnerBid The amount of the winner bid.
     * @param referralFee The percentage of the fee that will be transferred to the referrer in case of having one.
     * Measured in basis points, each basis point represents 0.01%.
     * @param referrerProfileId The token ID of the referrer's profile.
     * @param currency The currency in which the bids are denominated.
     * @param recipient The recipient of the auction's winner bid amount.
     */
    function _processCollectFeeWithReferral(
        uint256 winnerBid,
        uint16 referralFee,
        uint256 referrerProfileId,
        address currency,
        address recipient
    ) internal {
        (address treasury, uint16 treasuryFee) = _treasuryData();
        uint256 treasuryAmount = (winnerBid * treasuryFee) / BPS_MAX;
        uint256 adjustedAmount = winnerBid - treasuryAmount;
        if (referralFee > 0) {
            // The reason we levy the referral fee on the adjusted amount is so that referral fees
            // don't bypass the treasury fee, in essence referrals pay their fair share to the treasury.
            uint256 referralAmount = (adjustedAmount * referralFee) / BPS_MAX;
            adjustedAmount = adjustedAmount - referralAmount;
            IERC20(currency).safeTransfer(IERC721(HUB).ownerOf(referrerProfileId), referralAmount);
        }
        IERC20(currency).safeTransfer(recipient, adjustedAmount);
        if (treasuryAmount > 0) {
            IERC20(currency).safeTransfer(treasury, treasuryAmount);
        }
    }

    /**
     * @notice Executes the given bid for the given auction. Each new successful bid transfers back the funds of the
     * previous winner and pulls funds from the new winning bidder.
     *
     * @param profileId The token ID of the profile associated with the underlying publication.
     * @param pubId The publication ID associated with the underlying publication.
     * @param referrerProfileId The token ID of the referrer's profile.
     * @param amount The bid amount to offer.
     * @param followNftTokenId The token ID of the Follow NFT to use if the auction is configured as followers-only.
     * @param bidder The address of the bidder.
     */
    function _bid(
        uint256 profileId,
        uint256 pubId,
        uint256 referrerProfileId,
        uint256 amount,
        uint256 followNftTokenId,
        address bidder
    ) internal {
        AuctionData memory auction = _auctionDataByPubByProfile[profileId][pubId];
        _validateBid(profileId, amount, followNftTokenId, bidder, auction);
        uint256 referrerProfileIdSet = _setReferrerProfileIdIfNotAlreadySet(
            profileId,
            pubId,
            referrerProfileId,
            bidder
        );
        uint256 endTimestamp = _setNewAuctionStorageStateAfterBid(
            profileId,
            pubId,
            amount,
            bidder,
            auction
        );
        if (auction.winner != address(0)) {
            IERC20(auction.currency).safeTransfer(auction.winner, auction.winningBid);
        }
        IERC20(auction.currency).safeTransferFrom(bidder, address(this), amount);
        // `referrerProfileId` and `followNftTokenId` event params are tweaked to provide better semantics for indexers.
        emit BidPlaced(
            profileId,
            pubId,
            referrerProfileIdSet == profileId ? 0 : referrerProfileIdSet,
            amount,
            auction.onlyFollowers ? followNftTokenId : 0,
            bidder,
            endTimestamp,
            block.timestamp
        );
    }

    /**
     * @notice Valides if the given bid is valid for the given auction.
     *
     * @param profileId The token ID of the profile associated with the underlying publication.
     * @param amount The bid amount to offer.
     * @param followNftTokenId The token ID of the Follow NFT to use if the auction is configured as followers-only.
     * @param bidder The address of the bidder.
     * @param auction The data of the auction where the bid is being placed.
     */
    function _validateBid(
        uint256 profileId,
        uint256 amount,
        uint256 followNftTokenId,
        address bidder,
        AuctionData memory auction
    ) internal view {
        if (
            auction.duration == 0 ||
            block.timestamp < auction.availableSinceTimestamp ||
            (auction.startTimestamp > 0 && block.timestamp > auction.endTimestamp)
        ) {
            revert UnavailableAuction();
        }
        _validateBidAmount(auction, amount);
        if (auction.onlyFollowers) {
            _validateFollow(
                profileId,
                bidder,
                followNftTokenId,
                auction.startTimestamp == 0 ? block.timestamp : auction.startTimestamp
            );
        }
    }

    /**
     * @notice Updates the state of the auction data after a successful bid.
     *
     * @param profileId The token ID of the profile associated with the underlying publication.
     * @param pubId The publication ID associated with the underlying publication.
     * @param newWinningBid The amount of the new winning bid.
     * @param newWinner The new winning bidder.
     * @param prevAuctionState The state of the auction data before the bid, which will be overrided.
     *
     * @return A UNIX timestamp representing the `endTimestamp` of the new auction state.
     */
    function _setNewAuctionStorageStateAfterBid(
        uint256 profileId,
        uint256 pubId,
        uint256 newWinningBid,
        address newWinner,
        AuctionData memory prevAuctionState
    ) internal returns (uint256) {
        AuctionData storage nextAuctionState = _auctionDataByPubByProfile[profileId][pubId];
        nextAuctionState.winner = newWinner;
        nextAuctionState.winningBid = newWinningBid;
        uint256 endTimestamp = prevAuctionState.endTimestamp;
        if (prevAuctionState.winner == address(0)) {
            endTimestamp = block.timestamp + prevAuctionState.duration;
            nextAuctionState.endTimestamp = uint64(endTimestamp);
            nextAuctionState.startTimestamp = uint64(block.timestamp);
        } else if (endTimestamp - block.timestamp < prevAuctionState.minTimeAfterBid) {
            endTimestamp = block.timestamp + prevAuctionState.minTimeAfterBid;
            nextAuctionState.endTimestamp = uint64(endTimestamp);
        }
        return endTimestamp;
    }

    /**
     * @notice Sets the the given `referrerProfileId` if it is the first bid of the bidder, or returns the previously
     * set otherwise.
     *
     * @param profileId The token ID of the profile associated with the underlying publication.
     * @param pubId The publication ID associated with the underlying publication.
     * @param referrerProfileId The token ID of the referrer's profile.
     * @param bidder The address of the bidder whose referrer profile id is being set.
     *
     * @return The token ID of the referrer profile for the given bidder. Being equals to `profileId` means no referrer.
     */
    function _setReferrerProfileIdIfNotAlreadySet(
        uint256 profileId,
        uint256 pubId,
        uint256 referrerProfileId,
        address bidder
    ) internal returns (uint256) {
        uint256 referrerProfileIdSet = _referrerProfileIdByPubByProfile[profileId][pubId][bidder];
        if (referrerProfileIdSet == 0) {
            _referrerProfileIdByPubByProfile[profileId][pubId][bidder] = referrerProfileId;
            referrerProfileIdSet = referrerProfileId;
        }
        return referrerProfileIdSet;
    }

    /**
     * @notice Checks if the given bid amount is valid for the given auction.
     *
     * @param auction The auction where the bid amount validation should be performed.
     * @param amount The bid amount to validate.
     */
    function _validateBidAmount(AuctionData memory auction, uint256 amount) internal pure {
        bool auctionStartsWithCurrentBid = auction.winner == address(0);
        if (
            (auctionStartsWithCurrentBid && amount < auction.reservePrice) ||
            (!auctionStartsWithCurrentBid &&
                (amount <= auction.winningBid ||
                    (auction.minBidIncrement > 0 &&
                        amount - auction.winningBid < auction.minBidIncrement)))
        ) {
            revert InsufficientBidAmount();
        }
    }

    /**
     * @notice Checks the given Follow NFT is owned by the given follower, is part of the given followed profile's
     * follow NFT collection and was minted before the given deadline.
     *
     * @param profileId The token ID of the profile associated with the publication.
     * @param follower The address performing the follow operation.
     * @param followNftTokenId The token ID of the Follow NFT to use.
     * @param maxValidFollowTimestamp The maximum timestamp for which Follow NFTs should have been minted before to be
     * valid for this scenario.
     */
    function _validateFollow(
        uint256 profileId,
        address follower,
        uint256 followNftTokenId,
        uint256 maxValidFollowTimestamp
    ) internal view {
        address followNFT = ILensHub(HUB).getFollowNFT(profileId);
        if (
            followNFT == address(0) ||
            IERC721(followNFT).ownerOf(followNftTokenId) != follower ||
            IERC721Time(followNFT).mintTimestampOf(followNftTokenId) > maxValidFollowTimestamp
        ) {
            revert Errors.FollowInvalid();
        }
    }

    /**
     * @notice Returns the pointed publication if the passed one is a mirror, otherwise just returns the passed one.
     *
     * @param profileId The token ID of the profile associated with the publication, could be a mirror.
     * @param pubId The publication ID associated with the publication, could be a mirror.
     */
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

    /**
     * @notice Checks if the signature for the `bidWithSig` function is valid according EIP-712 standard.
     *
     * @param profileId The token ID of the profile associated with the publication, could be a mirror.
     * @param pubId The publication ID associated with the publication, could be a mirror.
     * @param amount The bid amount to offer.
     * @param followNftTokenId The token ID of the Follow NFT to use if the auction is configured as followers-only.
     * @param bidder The address of the bidder.
     * @param sig The EIP-712 signature to validate.
     */
    function _validateBidSignature(
        uint256 profileId,
        uint256 pubId,
        uint256 amount,
        uint256 followNftTokenId,
        address bidder,
        DataTypes.EIP712Signature calldata sig
    ) internal {
        unchecked {
            _validateRecoveredAddress(
                _calculateDigest(
                    abi.encode(
                        keccak256(
                            'BidWithSig(uint256 profileId,uint256 pubId,uint256 amount,uint256 followNftTokenId,uint256 nonce,uint256 deadline)'
                        ),
                        profileId,
                        pubId,
                        amount,
                        followNftTokenId,
                        nonces[bidder]++,
                        sig.deadline
                    )
                ),
                bidder,
                sig
            );
        }
    }

    /**
     * @notice Checks the recovered address is the expected signer for the given signature.
     *
     * @param digest The expected signed data.
     * @param expectedAddress The address of the expected signer.
     * @param sig The signature.
     */
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

    /**
     * @notice Calculates the digest for the given bytes according EIP-712 standard.
     *
     * @param message The message, as bytes, to calculate the digest from.
     */
    function _calculateDigest(bytes memory message) internal view returns (bytes32) {
        return keccak256(abi.encodePacked('\x19\x01', _domainSeparatorV4(), keccak256(message)));
    }
}
