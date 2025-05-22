// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title Virtual Real Estate Project
 * @dev A decentralized platform for buying and selling virtual land parcels as NFTs
 */
contract Project is ERC721, ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;
    
    Counters.Counter private _tokenIdCounter;
    
    // Land parcel structure
    struct LandParcel {
        uint256 tokenId;
        int256 x;
        int256 y;
        uint256 size;
        uint256 price;
        bool forSale;
        string name;
        address currentOwner;
        uint256 createdAt;
    }
    
    // Mappings
    mapping(uint256 => LandParcel) public landParcels;
    mapping(bytes32 => uint256) public coordinateToTokenId;
    mapping(uint256 => bool) public listings;
    
    // Constants
    uint256 public constant MAX_SUPPLY = 10000;
    uint256 public constant MIN_PRICE = 0.001 ether;
    uint256 public marketplaceFee = 250; // 2.5%
    
    // Events
    event LandMinted(uint256 indexed tokenId, address indexed owner, int256 x, int256 y, uint256 size);
    event LandListed(uint256 indexed tokenId, address indexed seller, uint256 price);
    event LandSold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price);
    event LandDelisted(uint256 indexed tokenId, address indexed owner);
    
    constructor() ERC721("Virtual Real Estate", "VRE") {}
    
    /**
     * @dev Check if a token exists by verifying it has an owner
     * @param tokenId Token ID to check
     * @return bool True if token exists, false otherwise
     */
    function tokenExists(uint256 tokenId) public view returns (bool) {
        try this.ownerOf(tokenId) returns (address) {
            return true;
        } catch {
            return false;
        }
    }
    
    /**
     * @dev Core Function 1: Mint new virtual land parcels
     * @param to Address to mint the land to
     * @param x X coordinate of the land
     * @param y Y coordinate of the land
     * @param size Size of the land parcel
     * @param name Name of the land parcel
     */
    function mintLand(
        address to,
        int256 x,
        int256 y,
        uint256 size,
        string memory name
    ) public onlyOwner {
        require(_tokenIdCounter.current() < MAX_SUPPLY, "Max supply reached");
        require(size > 0, "Size must be greater than 0");
        require(bytes(name).length > 0, "Name cannot be empty");
        require(to != address(0), "Cannot mint to zero address");
        
        bytes32 coordinateHash = keccak256(abi.encodePacked(x, y));
        require(coordinateToTokenId[coordinateHash] == 0, "Land already exists at coordinates");
        
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        
        _safeMint(to, tokenId);
        
        landParcels[tokenId] = LandParcel({
            tokenId: tokenId,
            x: x,
            y: y,
            size: size,
            price: 0,
            forSale: false,
            name: name,
            currentOwner: to,
            createdAt: block.timestamp
        });
        
        coordinateToTokenId[coordinateHash] = tokenId;
        
        emit LandMinted(tokenId, to, x, y, size);
    }
    
    /**
     * @dev Core Function 2: List land for sale
     * @param tokenId Token ID of the land parcel
     * @param price Sale price in wei
     */
    function listLandForSale(uint256 tokenId, uint256 price) public {
        require(tokenExists(tokenId), "Land does not exist");
        require(ownerOf(tokenId) == msg.sender, "Not the owner");
        require(price >= MIN_PRICE, "Price too low");
        require(!landParcels[tokenId].forSale, "Already listed");
        
        landParcels[tokenId].forSale = true;
        landParcels[tokenId].price = price;
        listings[tokenId] = true;
        
        emit LandListed(tokenId, msg.sender, price);
    }
    
    /**
     * @dev Core Function 3: Buy listed land
     * @param tokenId Token ID of the land parcel to buy
     */
    function buyLand(uint256 tokenId) public payable nonReentrant {
        require(tokenExists(tokenId), "Land does not exist");
        require(landParcels[tokenId].forSale, "Land not for sale");
        require(msg.value >= landParcels[tokenId].price, "Insufficient payment");
        require(msg.sender != ownerOf(tokenId), "Cannot buy your own land");
        
        address seller = ownerOf(tokenId);
        uint256 salePrice = landParcels[tokenId].price;
        
        // Calculate fees
        uint256 fee = (salePrice * marketplaceFee) / 10000;
        uint256 sellerAmount = salePrice - fee;
        
        // Update land parcel state first
        landParcels[tokenId].forSale = false;
        landParcels[tokenId].price = 0;
        listings[tokenId] = false;
        
        // Transfer NFT
        _transfer(seller, msg.sender, tokenId);
        
        // Update current owner after successful transfer
        landParcels[tokenId].currentOwner = msg.sender;
        
        // Transfer payments using call for better gas handling
        (bool success, ) = payable(seller).call{value: sellerAmount}("");
        require(success, "Payment to seller failed");
        
        // Refund excess payment
        if (msg.value > salePrice) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: msg.value - salePrice}("");
            require(refundSuccess, "Refund failed");
        }
        
        emit LandSold(tokenId, seller, msg.sender, salePrice);
    }
    
    /**
     * @dev Delist land from sale
     * @param tokenId Token ID of the land parcel to delist
     */
    function delistLand(uint256 tokenId) public {
        require(tokenExists(tokenId), "Land does not exist");
        require(ownerOf(tokenId) == msg.sender, "Not the owner");
        require(landParcels[tokenId].forSale, "Land not listed for sale");
        
        landParcels[tokenId].forSale = false;
        landParcels[tokenId].price = 0;
        listings[tokenId] = false;
        
        emit LandDelisted(tokenId, msg.sender);
    }
    
    // View functions
    function getLandInfo(uint256 tokenId) public view returns (LandParcel memory) {
        require(tokenExists(tokenId), "Land does not exist");
        return landParcels[tokenId];
    }
    
    function isCoordinateAvailable(int256 x, int256 y) public view returns (bool) {
        bytes32 coordinateHash = keccak256(abi.encodePacked(x, y));
        return coordinateToTokenId[coordinateHash] == 0;
    }
    
    function getLandAtCoordinates(int256 x, int256 y) public view returns (uint256) {
        bytes32 coordinateHash = keccak256(abi.encodePacked(x, y));
        return coordinateToTokenId[coordinateHash];
    }
    
    function totalSupply() public view returns (uint256) {
        return _tokenIdCounter.current();
    }
    
    function getAllListedLands() public view returns (uint256[] memory) {
        uint256 totalTokens = _tokenIdCounter.current();
        uint256[] memory listedLands = new uint256[](totalTokens);
        uint256 listedCount = 0;
        
        for (uint256 i = 0; i < totalTokens; i++) {
            if (listings[i] && landParcels[i].forSale && tokenExists(i)) {
                listedLands[listedCount] = i;
                listedCount++;
            }
        }
        
        // Create result array with exact size
        uint256[] memory result = new uint256[](listedCount);
        for (uint256 i = 0; i < listedCount; i++) {
            result[i] = listedLands[i];
        }
        
        return result;
    }
    
    function getOwnerLands(address owner) public view returns (uint256[] memory) {
        uint256 totalTokens = _tokenIdCounter.current();
        uint256[] memory ownerLands = new uint256[](totalTokens);
        uint256 ownerCount = 0;
        
        for (uint256 i = 0; i < totalTokens; i++) {
            if (tokenExists(i) && ownerOf(i) == owner) {
                ownerLands[ownerCount] = i;
                ownerCount++;
            }
        }
        
        // Create result array with exact size
        uint256[] memory result = new uint256[](ownerCount);
        for (uint256 i = 0; i < ownerCount; i++) {
            result[i] = ownerLands[i];
        }
        
        return result;
    }
    
    // Admin functions
    function setMarketplaceFee(uint256 newFee) public onlyOwner {
        require(newFee <= 1000, "Fee too high"); // Max 10%
        marketplaceFee = newFee;
    }
    
    function withdrawFees() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdrawal failed");
    }
    
    function emergencyWithdraw() public onlyOwner {
        // Emergency function to withdraw all funds
        (bool success, ) = payable(owner()).call{value: address(this).balance}("");
        require(success, "Emergency withdrawal failed");
    }
    
    // Receive function to accept ETH
    receive() external payable {}
    
    // Fallback function
    fallback() external payable {}
}
