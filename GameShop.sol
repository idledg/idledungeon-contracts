// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @dev Interface for ERC20 tokens with burn functionality
 */
interface IERC20Burnable is IERC20 {
    function burnFrom(address account, uint256 amount) external;
    function burn(uint256 amount) external;
}

/**
 * @title GameShop - IDG Token Payment for Mystery Boxes
 * @dev Handles box purchases with IDG tokens - BURN MODEL
 * 
 * TOKENOMICS: Utility Token (Thailand SEC Compliant)
 * - Tokens are BURNED after purchase, not transferred to treasury
 * - This makes IDG a deflationary utility token
 * 
 * Flow:
 * 1. Admin sets box prices (e.g., Character Box = 1000 IDG)
 * 2. User approves IDG spending for this contract
 * 3. User calls purchaseBox with server signature
 * 4. Contract BURNS IDG from user (deflationary)
 * 5. Server verifies payment and mints NFT/item
 * 
 * Security Features:
 * - Signature verification (prevents unauthorized purchases)
 * - Nonce tracking (prevents replay attacks)
 * - Pausable in emergency
 * - ReentrancyGuard on all purchase functions
 */
contract GameShop is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // ============================================
    // STRUCTS
    // ============================================
    
    struct BoxType {
        uint256 priceIDG;    // Price in IDG (18 decimals)
        bool isActive;        // Whether this box is available
        string name;          // Box name for events
    }
    
    // ============================================
    // ROLES
    // ============================================
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    // ============================================
    // STATE VARIABLES
    // ============================================
    
    // IDG Token contract (with burn capability)
    IERC20Burnable public immutable idgToken;
    
    // Treasury address (for emergency withdrawal only, not for payments)
    address public treasury;
    
    // Server signer for verifying purchases
    address public purchaseSigner;
    
    // Box types by ID
    mapping(uint256 => BoxType) public boxTypes;
    
    // User purchase nonces (prevents replay)
    mapping(address => uint256) public userNonces;
    
    // Completed purchase IDs (prevents double processing)
    mapping(bytes32 => bool) public completedPurchases;
    
    // Signature expiration
    uint256 public signatureExpiration = 5 minutes;
    
    // ============================================
    // EVENTS
    // ============================================
    event BoxPurchased(
        address indexed buyer,
        uint256 indexed boxTypeId,
        uint256 price,
        bytes32 purchaseId,
        uint256 nonce,
        uint256 timestamp
    );
    event TokensBurned(
        address indexed buyer,
        uint256 amount,
        bytes32 purchaseId
    );
    event BoxTypeUpdated(uint256 indexed boxTypeId, uint256 price, bool isActive, string name);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event SignerUpdated(address indexed oldSigner, address indexed newSigner);
    
    // ============================================
    // CONSTRUCTOR
    // ============================================
    
    /**
     * @param _idgToken Address of IDG Token contract
     * @param _treasury Address to receive payments (Treasury wallet)
     * @param _purchaseSigner Address that signs purchase authorizations (Operator wallet)
     */
    constructor(
        address _idgToken,
        address _treasury,
        address _purchaseSigner
    ) {
        require(_idgToken != address(0), "GameShop: invalid token");
        require(_treasury != address(0), "GameShop: invalid treasury");
        require(_purchaseSigner != address(0), "GameShop: invalid signer");
        
        idgToken = IERC20Burnable(_idgToken);
        treasury = _treasury;
        purchaseSigner = _purchaseSigner;
        
        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        
        // Initialize default box types (prices in IDG with 18 decimals)
        // 1 Gold = 1 IDG, so 1000 Gold = 1000 IDG = 1000 * 10^18
        boxTypes[1] = BoxType({
            priceIDG: 1000 * 1e18,   // Character Box: 1000 IDG
            isActive: true,
            name: "Character Box"
        });
        
        boxTypes[2] = BoxType({
            priceIDG: 500 * 1e18,    // Item Box: 500 IDG
            isActive: true,
            name: "Item Box"
        });
        
        boxTypes[3] = BoxType({
            priceIDG: 1500 * 1e18,   // Mixed Box: 1500 IDG
            isActive: true,
            name: "Mixed Box"
        });
    }
    
    // ============================================
    // PURCHASE FUNCTIONS
    // ============================================
    
    /**
     * @dev Purchase a mystery box with IDG
     * @param boxTypeId Type of box to purchase (1, 2, or 3)
     * @param purchaseId Unique purchase ID from server
     * @param nonce User's nonce (must match current nonce)
     * @param expireTime Signature expiration timestamp
     * @param signature Server's signature authorizing this purchase
     * 
     * NOTE: User must approve IDG spending BEFORE calling this function!
     */
    function purchaseBox(
        uint256 boxTypeId,
        bytes32 purchaseId,
        uint256 nonce,
        uint256 expireTime,
        bytes calldata signature
    ) external nonReentrant whenNotPaused {
        address buyer = msg.sender;
        BoxType storage box = boxTypes[boxTypeId];
        
        // Validate box type
        require(box.isActive, "GameShop: box type not available");
        require(box.priceIDG > 0, "GameShop: invalid box price");
        
        // Validate purchase
        require(!completedPurchases[purchaseId], "GameShop: purchase already completed");
        require(nonce == userNonces[buyer], "GameShop: invalid nonce");
        require(block.timestamp <= expireTime, "GameShop: signature expired");
        require(expireTime <= block.timestamp + signatureExpiration, "GameShop: expire time too far");
        
        // Check user has sufficient balance and allowance
        require(
            idgToken.balanceOf(buyer) >= box.priceIDG,
            "GameShop: insufficient IDG balance"
        );
        require(
            idgToken.allowance(buyer, address(this)) >= box.priceIDG,
            "GameShop: insufficient IDG allowance"
        );
        
        // Verify signature
        bytes32 messageHash = keccak256(abi.encodePacked(
            buyer,
            boxTypeId,
            purchaseId,
            nonce,
            expireTime,
            block.chainid,
            address(this)
        ));
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(messageHash);
        address recoveredSigner = ECDSA.recover(ethSignedHash, signature);
        require(recoveredSigner == purchaseSigner, "GameShop: invalid signature");
        
        // Update state BEFORE transfer (CEI pattern)
        completedPurchases[purchaseId] = true;
        userNonces[buyer] = nonce + 1;
        
        // BURN IDG from buyer (deflationary tokenomics)
        // User must have approved this contract to spend their tokens
        idgToken.burnFrom(buyer, box.priceIDG);
        
        emit TokensBurned(buyer, box.priceIDG, purchaseId);
        emit BoxPurchased(buyer, boxTypeId, box.priceIDG, purchaseId, nonce, block.timestamp);
    }
    
    // ============================================
    // VIEW FUNCTIONS
    // ============================================
    
    /**
     * @dev Get box type details
     */
    function getBoxType(uint256 boxTypeId) external view returns (
        uint256 priceIDG,
        bool isActive,
        string memory name
    ) {
        BoxType storage box = boxTypes[boxTypeId];
        return (box.priceIDG, box.isActive, box.name);
    }
    
    /**
     * @dev Get user's current nonce
     */
    function getNonce(address user) external view returns (uint256) {
        return userNonces[user];
    }
    
    /**
     * @dev Check if purchase ID has been used
     */
    function isPurchaseCompleted(bytes32 purchaseId) external view returns (bool) {
        return completedPurchases[purchaseId];
    }
    
    /**
     * @dev Check if user can purchase (has balance and allowance)
     */
    function canPurchase(address buyer, uint256 boxTypeId) external view returns (
        bool canBuy,
        string memory reason
    ) {
        BoxType storage box = boxTypes[boxTypeId];
        
        if (!box.isActive) {
            return (false, "Box type not available");
        }
        if (idgToken.balanceOf(buyer) < box.priceIDG) {
            return (false, "Insufficient IDG balance");
        }
        if (idgToken.allowance(buyer, address(this)) < box.priceIDG) {
            return (false, "IDG not approved for spending");
        }
        return (true, "");
    }
    
    /**
     * @dev Generate message hash for signing (helper for backend)
     */
    function getMessageHash(
        address buyer,
        uint256 boxTypeId,
        bytes32 purchaseId,
        uint256 nonce,
        uint256 expireTime
    ) external view returns (bytes32) {
        return keccak256(abi.encodePacked(
            buyer,
            boxTypeId,
            purchaseId,
            nonce,
            expireTime,
            block.chainid,
            address(this)
        ));
    }
    
    // ============================================
    // ADMIN FUNCTIONS
    // ============================================
    
    /**
     * @dev Set box type price and status
     */
    function setBoxType(
        uint256 boxTypeId,
        uint256 priceIDG,
        bool isActive,
        string calldata name
    ) external onlyRole(OPERATOR_ROLE) {
        boxTypes[boxTypeId] = BoxType({
            priceIDG: priceIDG,
            isActive: isActive,
            name: name
        });
        emit BoxTypeUpdated(boxTypeId, priceIDG, isActive, name);
    }
    
    /**
     * @dev Update treasury address
     */
    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newTreasury != address(0), "GameShop: invalid treasury");
        address oldTreasury = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }
    
    /**
     * @dev Update purchase signer
     */
    function setPurchaseSigner(address newSigner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newSigner != address(0), "GameShop: invalid signer");
        address oldSigner = purchaseSigner;
        purchaseSigner = newSigner;
        emit SignerUpdated(oldSigner, newSigner);
    }
    
    /**
     * @dev Update signature expiration
     */
    function setSignatureExpiration(uint256 _expiration) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_expiration >= 1 minutes, "GameShop: expiration too short");
        require(_expiration <= 1 hours, "GameShop: expiration too long");
        signatureExpiration = _expiration;
    }
    
    /**
     * @dev Pause purchases (emergency)
     */
    function pause() external onlyRole(OPERATOR_ROLE) {
        _pause();
    }
    
    /**
     * @dev Unpause purchases
     */
    function unpause() external onlyRole(OPERATOR_ROLE) {
        _unpause();
    }
    
    /**
     * @dev Emergency withdraw (only if this contract holds tokens by mistake)
     */
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "GameShop: invalid recipient");
        IERC20(token).safeTransfer(to, amount);
    }
}
