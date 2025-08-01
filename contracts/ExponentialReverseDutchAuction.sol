// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './abstract/Auction.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/**
 * @title ExponentialReverseDutchAuction
 * @notice Auction contract for NFT and token auctions, where price decreases exponentially over time from starting price to reserve price.
 * The first bidder to meet the current price wins the auction.
 * price(t) = reservedPrice + (startingPrice - reservedPrice) * 2^(-timeElapsed*decayFactor)
 */
contract ExponentialReverseDutchAuction is Auction {
    mapping(uint256 => AuctionData) public auctions;

    uint256[61] private decayLookup = [1000000000000000000,500000000000000000,250000000000000000,125000000000000000,62500000000000000,31250000000000000,15625000000000000,7812500000000000,3906250000000000,1953125000000000,976562500000000,488281250000000,244140625000000,122070312500000,61035156250000,30517578125000,15258789062500,7629394531250,3814697265625,1907348632812,953674316406,476837158203,238418579102,119209289551,59604644775,29802322388,14901161194,7450580597,3725290298,1862645149,931322574,465661287,232830643,116415322,58207661,29103831,14551915,7275958,3637979,1818989,909495,454747,227373,113687,56843,28422,14211,7105,3553,1776,888,444,222,111,56,28,14,7,3,2,1
    ];
    // decayLookup table is formed by claculating 2^(-x) for x=0,1,2,...,61,scaled with 10^18 to ensure precision upto 18 decimal points

    struct AuctionData {
        uint256 id;
        string name;
        string description;
        string imgUrl;
        address auctioneer;
        AuctionType auctionType;
        address auctionedToken;
        uint256 auctionedTokenIdOrAmount;
        address biddingToken;
        uint256 startingPrice;
        uint256 availableFunds;
        uint256 reservedPrice;
        uint256 decayFactor;
        address winner;
        uint256 deadline;
        uint256 duration;
        bool isClaimed;
    }
    event AuctionCreated(
        uint256 indexed Id,
        string name,
        string description,
        string imgUrl,
        address auctioneer,
        AuctionType auctionType,
        address auctionedToken,
        uint256 auctionedTokenIdOrAmount,
        address biddingToken,
        uint256 startingPrice,
        uint256 reservedPrice,
        uint256 decayFactor,
        uint256 deadline
    );

    function createAuction(
        string memory name,
        string memory description,
        string memory imgUrl,
        AuctionType auctionType,
        address auctionedToken,
        uint256 auctionedTokenIdOrAmount,
        address biddingToken,
        uint256 startingPrice,
        uint256 reservedPrice,
        uint256 decayFactor,
        uint256 duration
    ) external validAuctionParams(name,auctionedToken,biddingToken) {
        require(startingPrice >= reservedPrice, 'Starting price should be higher than reserved price');
        require(duration > 0, 'Duration must be greater than zero seconds');
        //decay Factor is scaled with 10^5 to ensure precision upto three decimal points
        receiveFunds(auctionType == AuctionType.NFT, auctionedToken, msg.sender, auctionedTokenIdOrAmount); 
        uint256 deadline = block.timestamp + duration;
        auctions[auctionCounter] = AuctionData({
            id: auctionCounter,
            name: name,
            description: description,
            imgUrl: imgUrl,
            auctioneer: msg.sender,
            auctionType: auctionType,
            auctionedToken: auctionedToken,
            auctionedTokenIdOrAmount: auctionedTokenIdOrAmount,
            biddingToken: biddingToken,
            startingPrice: startingPrice,
            availableFunds: 0,
            reservedPrice: reservedPrice,
            decayFactor: decayFactor,
            winner: msg.sender,
            deadline: deadline,
            duration: duration,
            isClaimed: false
        });
        emit AuctionCreated(
            auctionCounter++,
            name,
            description,
            imgUrl,
            msg.sender,
            auctionType,
            auctionedToken,
            auctionedTokenIdOrAmount,
            biddingToken,
            startingPrice,
            reservedPrice,
            decayFactor,
            deadline
        );
    }

    function getDecayValue(uint256 x) internal view returns (uint256) {
        if (x >= 61 * 1e5) {
            return 0;
        } else {
            uint256 scaledPower = x / 1e5;
            uint256 remainder = x % 1e5;
            if (remainder == 0) return decayLookup[scaledPower];
            uint256 higherValue = decayLookup[scaledPower];
            uint256 lowerValue = scaledPower < 60 ? decayLookup[scaledPower + 1] : 0;
            return higherValue - ((higherValue - lowerValue) * remainder) / 1e5; //Linear interpolation
        }
    }

    function getCurrentPrice(uint256 auctionId) public view validAuctionId(auctionId) returns (uint256) {
        AuctionData storage auction = auctions[auctionId];
        if(block.timestamp >= auction.deadline) return 0;
        require(!auction.isClaimed, 'Auction has ended');
        uint256 timeElapsed = block.timestamp - (auction.deadline - auction.duration);
        uint256 x = timeElapsed * auction.decayFactor;
        uint256 decayValue = getDecayValue(x);
        return auction.reservedPrice + ((auction.startingPrice - auction.reservedPrice) * decayValue) / 1e18;
    }

    //placeBid function is not required in this auction type as the price is determined by the auctioneer and the auctioneer can withdraw the item on placing the bid only
    function withdrawItem(uint256 auctionId) external validAuctionId(auctionId) {
        AuctionData storage auction = auctions[auctionId];
        require(block.timestamp < auction.deadline || auction.winner==auction.auctioneer, 'Auction has ended');
        require(!auction.isClaimed, 'Auction has been settled');
        uint256 currentPrice = getCurrentPrice(auctionId);
        auction.winner = msg.sender;
        auction.availableFunds = currentPrice;
        auction.isClaimed = true;
        if(auction.auctioneer != auction.winner) receiveFunds(false, auction.biddingToken, msg.sender, currentPrice);
        sendFunds(auction.auctionType == AuctionType.NFT, auction.auctionedToken, msg.sender, auction.auctionedTokenIdOrAmount);
        emit itemWithdrawn(auctionId, msg.sender, auction.auctionedToken, auction.auctionedTokenIdOrAmount);
    }

    function withdrawFunds(uint256 auctionId) external validAuctionId(auctionId) {
        AuctionData storage auction = auctions[auctionId];
        require(msg.sender == auctions[auctionId].auctioneer, 'Not auctioneer!');
        uint256 withdrawAmount = auction.availableFunds;
        require(withdrawAmount > 0, 'No funds available');
        require(block.timestamp >= auction.deadline || auction.isClaimed, 'Auction is still ongoing');
        auction.availableFunds = 0;
        sendFunds(false, auction.biddingToken, msg.sender, withdrawAmount);
        emit fundsWithdrawn(auctionId, withdrawAmount);
    }
}
