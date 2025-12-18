// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title ItemNFT - IDLE Dungeon Item NFTs
 * @dev ERC-721 contract for minting game items as NFTs
 * 
 * Same workflow as CharacterNFT:
 * 1. User gets item from box/dungeon → off-chain (in database)
 * 2. User can convert off-chain item to on-chain NFT
 * 3. When NFT is transferred → ownership changes in both on-chain and off-chain
 */
contract ItemNFT is ERC721, ERC721URIStorage, ERC721Enumerable, AccessControl, Pausable, ReentrancyGuard {
    
    // ============================================
    // ROLES
    // ============================================
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    // ============================================
    // STATE VARIABLES
    // ============================================
    
    string private _baseTokenURI;
    
    mapping(uint256 => bool) public isMinted;
    
    // Item data stored on-chain
    struct ItemData {
        string itemType;     // weapon, armor, accessory, consumable
        string rarity;       // S, A, B, C, D, Common
        string slotType;     // head, body, weapon, etc.
        uint256 mintedAt;
    }
    
    mapping(uint256 => ItemData) public itemData;
    
    // ============================================
    // EVENTS
    // ============================================
    event ItemMinted(
        uint256 indexed tokenId,
        address indexed owner,
        string itemType,
        string rarity,
        uint256 timestamp
    );
    
    event ItemTransferred(
        uint256 indexed tokenId,
        address indexed from,
        address indexed to,
        uint256 timestamp
    );
    
    // ============================================
    // CONSTRUCTOR
    // ============================================
    
    constructor(string memory baseURI) ERC721("IDLE Dungeon Item", "IDGITEM") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _baseTokenURI = baseURI;
    }
    
    // ============================================
    // MINTING
    // ============================================
    
    function mintItem(
        address to,
        uint256 tokenId,
        string calldata itemType,
        string calldata rarity,
        string calldata slotType,
        string calldata tokenURI_
    ) external onlyRole(MINTER_ROLE) nonReentrant whenNotPaused {
        require(!isMinted[tokenId], "ItemNFT: Token already minted");
        require(to != address(0), "ItemNFT: Invalid recipient");
        
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenURI_);
        
        itemData[tokenId] = ItemData({
            itemType: itemType,
            rarity: rarity,
            slotType: slotType,
            mintedAt: block.timestamp
        });
        
        isMinted[tokenId] = true;
        
        emit ItemMinted(tokenId, to, itemType, rarity, block.timestamp);
    }
    
    // ============================================
    // TRANSFER OVERRIDE
    // ============================================
    
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal virtual override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
        
        if (from != address(0) && to != address(0)) {
            emit ItemTransferred(tokenId, from, to, block.timestamp);
        }
    }
    
    // ============================================
    // VIEW FUNCTIONS
    // ============================================
    
    function getItem(uint256 tokenId) external view returns (
        string memory itemType,
        string memory rarity,
        string memory slotType,
        uint256 mintedAt,
        address owner
    ) {
        require(_exists(tokenId), "ItemNFT: Token does not exist");
        
        ItemData storage data = itemData[tokenId];
        return (data.itemType, data.rarity, data.slotType, data.mintedAt, ownerOf(tokenId));
    }
    
    function tokensOfOwner(address owner) external view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(owner);
        uint256[] memory tokens = new uint256[](tokenCount);
        
        for (uint256 i = 0; i < tokenCount; i++) {
            tokens[i] = tokenOfOwnerByIndex(owner, i);
        }
        
        return tokens;
    }
    
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }
    
    // ============================================
    // ADMIN FUNCTIONS
    // ============================================
    
    function setBaseURI(string calldata newBaseURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseTokenURI = newBaseURI;
    }
    
    function pause() external onlyRole(OPERATOR_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(OPERATOR_ROLE) {
        _unpause();
    }
    
    function addMinter(address minter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(MINTER_ROLE, minter);
    }
    
    function removeMinter(address minter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(MINTER_ROLE, minter);
    }
    
    // ============================================
    // REQUIRED OVERRIDES
    // ============================================
    
    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }
    
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }
    
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable, ERC721URIStorage, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
