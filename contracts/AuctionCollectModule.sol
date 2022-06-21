// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.10;

import {DataTypes} from '@aave/lens-protocol/contracts/libraries/DataTypes.sol';
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
 */
struct AuctionData {
    uint256 availableSinceTimestamp;
    uint256 startTimestamp;
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
}

/**
 * @title AuctionCollectModule
 * @author Lens Protocol
 *
 * @notice This module works by creating an English auction for the underlying publication. After the auction ends, only
 * the auction winner is allowed to collect the publication.
 */
contract AuctionCollectModule is FeeModuleBase, ModuleBase, ICollectModule {
    using SafeERC20 for IERC20;

    error ActiveAuction();
    error UnavailableAuction();
    error NoFeeToProcess();
    error InsufficientBidAmount();
    error InvalidBidder();

    event AuctionCreated(
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
    );
    event BidPlaced(
        uint256 profileId,
        uint256 pubId,
        uint256 referrerProfileId,
        uint256 amount,
        uint256 followNftTokenId,
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

    // keccak256('BidWithSig(uint256 profileId,uint256 pubId,uint256 amount,uint256 followNftTokenId,uint256 nonce,uint256 deadline)');
    bytes32 internal constant BID_WITH_SIG_TYPEHASH =
        0x0379a8fff1df18e1c9ca9ee00af30bc25bd91f6f353825b7781e0b1ca9e89d5d;

    mapping(address => uint256) public nonces;

    mapping(uint256 => mapping(uint256 => AuctionData)) internal _auctionDataByPubByProfile;

    /**
     * @dev Maps a given bidder's address to its referrer profile ID. Referrer matching publication's profile ID means
     * no referral, referrer being zero means that bidder has not bidded yet on this auction.
     * The referrer is set through, and only through, the first bidder's bid on each auction.
     */
    mapping(uint256 => mapping(uint256 => mapping(address => uint256)))
        internal _referrerProfileIdByPubByProfile;

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
        AuctionData memory auction = _auctionDataByPubByProfile[profileId][pubId];
        if (auction.startTimestamp <= block.timestamp && block.timestamp <= auction.endTimestamp) {
            revert ActiveAuction();
        }
        if (
            collector != auction.winner ||
            referrerProfileId != _referrerProfileIdByPubByProfile[profileId][pubId][collector]
        ) {
            revert Errors.ModuleDataMismatch();
        }
        if (auction.collected) {
            revert Errors.CollectNotAllowed();
        }
        if (auction.onlyFollowers) {
            _validateFollow(
                profileId,
                collector,
                abi.decode(data, (uint256)),
                auction.startTimestamp
            );
        } else if (data.length > 0) {
            // Prevents `LensHub` from emiting `Collected` event with wrong `data` parameter.
            revert Errors.ModuleDataMismatch();
        }
        _auctionDataByPubByProfile[profileId][pubId].collected = true;
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
        AuctionData memory auction = _auctionDataByPubByProfile[profileId][pubId];
        if (auction.startTimestamp <= block.timestamp && block.timestamp <= auction.endTimestamp) {
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
     * @param followNftTokenId The token ID of the Follow NFT to use if the auction is configured as followers-only.
     */
    function bid(
        uint256 profileId,
        uint256 pubId,
        uint256 amount,
        uint256 followNftTokenId
    ) external {
        (uint256 profileIdPointed, uint256 pubIdPointed) = _getRootPublication(profileId, pubId);
        _bid(profileIdPointed, pubIdPointed, profileId, amount, followNftTokenId, msg.sender);
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
     * @param bidder The address of the bidder, which should be
     */
    function bidWithSig(
        uint256 profileId,
        uint256 pubId,
        uint256 amount,
        uint256 followNftTokenId,
        address bidder,
        DataTypes.EIP712Signature calldata sig
    ) external {
        _validateBidSignature(
            profileId,
            pubId,
            amount,
            followNftTokenId,
            bidder,
            sig,
            BID_WITH_SIG_TYPEHASH
        );
        (uint256 profileIdPointed, uint256 pubIdPointed) = _getRootPublication(profileId, pubId);
        _bid(profileIdPointed, pubIdPointed, profileId, amount, followNftTokenId, bidder);
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
        return _referrerProfileIdByPubByProfile[profileId][pubId][bidder];
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

    function _processCollectFee(uint256 profileId, uint256 pubId) internal {
        AuctionData memory auction = _auctionDataByPubByProfile[profileId][pubId];
        _auctionDataByPubByProfile[profileId][pubId].feeProcessed = true;
        uint256 referrerProfileId = _referrerProfileIdByPubByProfile[profileId][pubId][
            auction.winner
        ];
        if (referrerProfileId == profileId) {
            _processCollectFeeWithoutReferral(auction);
        } else {
            _processCollectFeeWithReferral(auction, referrerProfileId);
        }
        emit FeeProcessed(profileId, pubId, block.timestamp);
    }

    function _processCollectFeeWithoutReferral(AuctionData memory auction) internal {
        (address treasury, uint16 treasuryFee) = _treasuryData();
        uint256 treasuryAmount = (auction.winningBid * treasuryFee) / BPS_MAX;
        uint256 adjustedAmount = auction.winningBid - treasuryAmount;
        IERC20(auction.currency).safeTransfer(auction.recipient, adjustedAmount);
        if (treasuryAmount > 0) {
            IERC20(auction.currency).safeTransfer(treasury, treasuryAmount);
        }
    }

    function _processCollectFeeWithReferral(AuctionData memory auction, uint256 referrerProfileId)
        internal
    {
        address treasury;
        uint256 treasuryAmount;
        // Avoids stack too deep.
        {
            uint16 treasuryFee;
            (treasury, treasuryFee) = _treasuryData();
            treasuryAmount = (auction.winningBid * treasuryFee) / BPS_MAX;
        }
        uint256 adjustedAmount = auction.winningBid - treasuryAmount;
        if (auction.referralFee > 0) {
            // The reason we levy the referral fee on the adjusted amount is so that referral fees
            // don't bypass the treasury fee, in essence referrals pay their fair share to the treasury.
            uint256 referralAmount = (adjustedAmount * auction.referralFee) / BPS_MAX;
            adjustedAmount = adjustedAmount - referralAmount;
            address referralRecipient = IERC721(HUB).ownerOf(referrerProfileId);
            IERC20(auction.currency).safeTransfer(referralRecipient, referralAmount);
        }
        address recipient = auction.recipient;
        IERC20(auction.currency).safeTransfer(recipient, adjustedAmount);
        if (treasuryAmount > 0) {
            IERC20(auction.currency).safeTransfer(treasury, treasuryAmount);
        }
    }

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
        uint256 referrerProfileIdSet = _setReferrerProfileId(
            profileId,
            pubId,
            referrerProfileId,
            bidder
        );
        _setNewAuctionStorageStateAfterBid(profileId, pubId, amount, bidder, auction);
        if (auction.winner != address(0)) {
            IERC20(auction.currency).safeTransferFrom(
                address(this),
                auction.winner,
                auction.winningBid
            );
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
            auction.endTimestamp,
            block.timestamp
        );
    }

    function _validateBid(
        uint256 profileId,
        uint256 amount,
        uint256 followNftTokenId,
        address bidder,
        AuctionData memory auction
    ) internal view {
        if (
            auction.duration == 0 ||
            auction.availableSinceTimestamp > block.timestamp ||
            (auction.startTimestamp > 0 && block.timestamp > auction.endTimestamp)
        ) {
            revert UnavailableAuction();
        }
        if (bidder == address(0)) {
            revert InvalidBidder();
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

    function _setNewAuctionStorageStateAfterBid(
        uint256 profileId,
        uint256 pubId,
        uint256 newWinningBid,
        address newWinner,
        AuctionData memory prevAuctionState
    ) internal {
        AuctionData storage nextAuctionState = _auctionDataByPubByProfile[profileId][pubId];
        nextAuctionState.winner = newWinner;
        nextAuctionState.winningBid = newWinningBid;
        if (prevAuctionState.winner == address(0)) {
            nextAuctionState.endTimestamp = block.timestamp + prevAuctionState.duration;
            nextAuctionState.startTimestamp = block.timestamp;
        } else {
            if (
                prevAuctionState.endTimestamp - block.timestamp < prevAuctionState.minTimeAfterBid
            ) {
                nextAuctionState.endTimestamp = block.timestamp + prevAuctionState.minTimeAfterBid;
            }
        }
    }

    function _setReferrerProfileId(
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

    function _validateBidSignature(
        uint256 profileId,
        uint256 pubId,
        uint256 amount,
        uint256 followNftTokenId,
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

    // TODO: Functions below could be in a lib or base contract

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
