// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title CharacterNFT - IDLE Dungeon Character NFTs
 * @dev ERC-721 contract for minting game characters as NFTs
 * 
 * Workflow:
 * 1. User opens box → gets off-chain character (in database)
 * 2. User can convert off-chain character to on-chain NFT (this contract)
 * 3. NFT characters can still be used in-game (off-chain actions)
 * 4. When NFT is transferred → level resets, ownership changes in both on-chain and off-chain
 * 
 * Minting:
 * - Only MINTER_ROLE (game server) can mint
 * - Token ID matches the off-chain character token_id
 * - Metadata stored on IPFS or game server
 * 
 * Security:
 * - Pausable for emergencies
 * - Role-based access control
 * - ReentrancyGuard on all state-changing functions
 */
contract CharacterNFT is ERC721, ERC721URIStorage, ERC721Enumerable, AccessControl, Pausable, ReentrancyGuard {
    using Counters for Counters.Counter;
    
    // ============================================
    // ROLES
    // ============================================
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    // ============================================
    // STATE VARIABLES
    // ============================================
    
    // Base URI for metadata
    string private _baseTokenURI;
    
    // Mapping to track if a character ID has been minted
    mapping(uint256 => bool) public isMinted;
    
    // Character data stored on-chain (minimal for gas efficiency)
    struct CharacterData {
        string charClass;    // S, A, B, C, D, Common
        string element;      // earth, water, wind, fire, light, dark
        uint256 mintedAt;    // Timestamp when converted to NFT
    }
    
    mapping(uint256 => CharacterData) public characterData;
    
    // ============================================
    // EVENTS
    // ============================================
    event CharacterMinted(
        uint256 indexed tokenId,
        address indexed owner,
        string charClass,
        string element,
        uint256 timestamp
    );
    
    event CharacterTransferred(
        uint256 indexed tokenId,
        address indexed from,
        address indexed to,
        uint256 timestamp
    );
    
    event BaseURIUpdated(string newBaseURI);
    
    // ============================================
    // CONSTRUCTOR
    // ============================================
    
    constructor(string memory baseURI) ERC721("IDLE Dungeon Character", "IDGCHAR") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _baseTokenURI = baseURI;
    }
    
    // ============================================
    // MINTING (Only Game Server)
    // ============================================
    
    /**
     * @dev Mint a character NFT
     * @param to Owner address
     * @param tokenId Must match the off-chain character token_id
     * @param charClass Character class (S, A, B, C, D, Common)
     * @param element Character element (earth, water, wind, fire, light, dark)
     * @param tokenURI_ Metadata URI (IPFS or server URL)
     * 
     * Called by game server when user converts off-chain character to NFT
     */
    function mintCharacter(
        address to,
        uint256 tokenId,
        string calldata charClass,
        string calldata element,
        string calldata tokenURI_
    ) external onlyRole(MINTER_ROLE) nonReentrant whenNotPaused {
        require(!isMinted[tokenId], "CharacterNFT: Token already minted");
        require(to != address(0), "CharacterNFT: Invalid recipient");
        require(bytes(charClass).length > 0, "CharacterNFT: Invalid class");
        require(bytes(element).length > 0, "CharacterNFT: Invalid element");
        
        // Mint the NFT
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenURI_);
        
        // Store character data
        characterData[tokenId] = CharacterData({
            charClass: charClass,
            element: element,
            mintedAt: block.timestamp
        });
        
        isMinted[tokenId] = true;
        
        emit CharacterMinted(tokenId, to, charClass, element, block.timestamp);
    }
    
    /**
     * @dev Batch mint multiple characters (gas efficient)
     */
    function batchMintCharacters(
        address[] calldata to,
        uint256[] calldata tokenIds,
        string[] calldata charClasses,
        string[] calldata elements,
        string[] calldata tokenURIs
    ) external onlyRole(MINTER_ROLE) nonReentrant whenNotPaused {
        require(
            to.length == tokenIds.length && 
            tokenIds.length == charClasses.length &&
            charClasses.length == elements.length &&
            elements.length == tokenURIs.length,
            "CharacterNFT: Array length mismatch"
        );
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (!isMinted[tokenIds[i]] && to[i] != address(0)) {
                _safeMint(to[i], tokenIds[i]);
                _setTokenURI(tokenIds[i], tokenURIs[i]);
                
                characterData[tokenIds[i]] = CharacterData({
                    charClass: charClasses[i],
                    element: elements[i],
                    mintedAt: block.timestamp
                });
                
                isMinted[tokenIds[i]] = true;
                
                emit CharacterMinted(tokenIds[i], to[i], charClasses[i], elements[i], block.timestamp);
            }
        }
    }
    
    // ============================================
    // TRANSFER OVERRIDE (Emit event for backend sync)
    // ============================================
    
    /**
     * @dev Override _beforeTokenTransfer to emit event for backend synchronization
     * Backend will listen for CharacterTransferred event and reset level in database
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal virtual override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
        
        // Only emit for actual transfers (not mints or burns)
        if (from != address(0) && to != address(0)) {
            emit CharacterTransferred(tokenId, from, to, block.timestamp);
        }
    }
    
    // ============================================
    // VIEW FUNCTIONS
    // ============================================
    
    /**
     * @dev Get character data
     */
    function getCharacter(uint256 tokenId) external view returns (
        string memory charClass,
        string memory element,
        uint256 mintedAt,
        address owner
    ) {
        require(_exists(tokenId), "CharacterNFT: Token does not exist");
        
        CharacterData storage data = characterData[tokenId];
        return (
            data.charClass,
            data.element,
            data.mintedAt,
            ownerOf(tokenId)
        );
    }
    
    /**
     * @dev Get all token IDs owned by an address
     */
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
    
    /**
     * @dev Update base URI for metadata
     */
    function setBaseURI(string calldata newBaseURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }
    
    /**
     * @dev Pause all transfers and minting
     */
    function pause() external onlyRole(OPERATOR_ROLE) {
        _pause();
    }
    
    /**
     * @dev Unpause
     */
    function unpause() external onlyRole(OPERATOR_ROLE) {
        _unpause();
    }
    
    /**
     * @dev Grant minter role to game server
     */
    function addMinter(address minter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(MINTER_ROLE, minter);
    }
    
    /**
     * @dev Revoke minter role
     */
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
