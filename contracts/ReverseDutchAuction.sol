// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./abstract/Auction.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract ReverseDutchAuction is Auction{

    uint256 public auctionCounter=0;
    mapping (uint256 => AuctionData) public auctions;

    struct AuctionData{
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
        uint256 deadline
    );

    modifier validAuctionId(uint256 auctionId) {
        require(auctionId>=0 && auctionId < auctionCounter,"Invalid auctionId");
        _;
    }

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
        uint256 duration
    ) external{
        require(bytes(name).length>0,"Name must be present");
        require(reservedPrice>=0,"Reserved price cannot be negative");
        require(startingPrice>=0,"Starting price cannot be negative");
        require(startingPrice>=reservedPrice,"Starting price should be higher than reserved price");
        require(duration>0,"Duration must be greater than zero seconds");

        if(auctionType == AuctionType.NFT){
            require(IERC721(auctionedToken).ownerOf(auctionedTokenIdOrAmount)==msg.sender,"Caller must be the owner");
            IERC721(auctionedToken).safeTransferFrom(msg.sender,address(this),auctionedTokenIdOrAmount);
        }else{
            require(IERC20(auctionedToken).balanceOf(msg.sender)>=auctionedTokenIdOrAmount,"Insufficient balance");
            IERC20(auctionedToken).transferFrom(msg.sender,address(this),auctionedTokenIdOrAmount);
        }

        uint256 deadline=block.timestamp+duration;

        auctions[auctionCounter] = AuctionData({
            id: auctionCounter,
            name:name,
            description:description,
            imgUrl:imgUrl,
            auctioneer: msg.sender,
            auctionType: auctionType,
            auctionedToken: auctionedToken,
            auctionedTokenIdOrAmount: auctionedTokenIdOrAmount,
            biddingToken: biddingToken,
            startingPrice: startingPrice,
            availableFunds: 0,
            reservedPrice: reservedPrice,
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
            deadline
        );
    }

    function getCurrentPrice(uint256 auctionId) public view validAuctionId(auctionId) returns (uint256) {
        AuctionData storage auction=auctions[auctionId];
        require(block.timestamp<auction.deadline,"Auction has ended");
        require(!auction.isClaimed,"Auction has ended");
        return auction.startingPrice - ((auction.startingPrice-auction.reservedPrice)*(auction.deadline-block.timestamp))/(auction.duration);
    }

    function withdrawItem(uint256 auctionId,uint256 bidAmount) external validAuctionId(auctionId) {
        AuctionData storage auction = auctions[auctionId];
        require(block.timestamp<auction.deadline,"Auction has ended");
        require(!auction.isClaimed,"Auction has been settled");

        uint256 currentPrice=getCurrentPrice(auctionId);
        require(bidAmount>=currentPrice,"Bid amount is less than current price");
        
        IERC20(auction.biddingToken).transferFrom(msg.sender,address(this),currentPrice);
        if(auction.auctionType == AuctionType.NFT){
            require(IERC721(auction.auctionedToken).ownerOf(auction.auctionedTokenIdOrAmount)==msg.sender,"Caller must be the owner");
            IERC721(auction.auctionedToken).safeTransferFrom(msg.sender,address(this),auction.auctionedTokenIdOrAmount);
        }else{
            require(IERC20(auction.auctionedToken).balanceOf(msg.sender)>=auction.auctionedTokenIdOrAmount,"Insufficient balance");
            IERC20(auction.auctionedToken).transferFrom(msg.sender,address(this),auction.auctionedTokenIdOrAmount);
        }

        auction.winner=msg.sender;
        auction.availableFunds=bidAmount;
        auction.isClaimed=true;

        emit itemWithdrawn(auctionId,msg.sender,auction.auctionedToken,bidAmount);
    }

    function withdrawFunds(uint256 auctionId) external validAuctionId(auctionId){
        AuctionData storage auction = auctions[auctionId]; 
        require(msg.sender==auctions[auctionId].auctioneer,"Not auctioneer!");
        uint256 withdrawAmount=auction.availableFunds;
        require(withdrawAmount > 0,"No funds available");

        IERC20(auction.biddingToken).transfer(auction.auctioneer,withdrawAmount);
        auction.availableFunds=0;

        emit fundsWithdrawn(
            auctionId,
            withdrawAmount
        );
    }

}
