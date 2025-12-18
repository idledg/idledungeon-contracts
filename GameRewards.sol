// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title GameRewards - IDG Token Distribution for IDLE Dungeon
 * @dev Handles reward distribution from Treasury to players
 * 
 * Security Features:
 * - Signature verification (prevents unauthorized claims)
 * - Nonce tracking (prevents replay attacks)
 * - Daily limits per user (prevents drain attacks)
 * - Cooldown between claims (prevents flash loan attacks)
 * - ReentrancyGuard on all claim functions
 * 
 * Flow:
 * 1. User completes dungeon, server generates signed reward
 * 2. User calls claimReward with signature
 * 3. Contract verifies signature and limits
 * 4. Contract transfers IDG from Treasury to user
 */
contract GameRewards is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // ============================================
    // ROLES
    // ============================================
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");
    
    // ============================================
    // STATE VARIABLES
    // ============================================
    
    // IDG Token contract
    IERC20 public immutable idgToken;
    
    // Treasury address that holds rewards
    address public treasury;
    
    // Signer address for verifying reward claims
    address public rewardSigner;
    
    // Nonce tracking per user (prevents replay attacks)
    mapping(address => uint256) public userNonces;
    
    // Track claimed run IDs (prevents double claims)
    mapping(uint256 => bool) public claimedRunIds;
    
    // Daily reward tracking
    mapping(address => uint256) public dailyRewardsClaimed;
    mapping(address => uint256) public lastClaimDay;
    
    // Limits
    uint256 public maxDailyRewardPerUser;  // Max IDG per user per day
    uint256 public maxSingleReward;         // Max IDG per single claim
    uint256 public claimCooldown;           // Seconds between claims (0 = no cooldown)
    mapping(address => uint256) public lastClaimTime;
    
    // Signature expiration (seconds)
    uint256 public signatureExpiration = 1 hours;
    
    // ============================================
    // EVENTS
    // ============================================
    event RewardClaimed(
        address indexed user,
        uint256 amount,
        uint256 runId,
        uint256 nonce,
        uint256 timestamp
    );
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event SignerUpdated(address indexed oldSigner, address indexed newSigner);
    event LimitsUpdated(uint256 maxDaily, uint256 maxSingle, uint256 cooldown);
    event EmergencyWithdraw(address indexed token, address indexed to, uint256 amount);
    
    // ============================================
    // CONSTRUCTOR
    // ============================================
    
    /**
     * @param _idgToken Address of IDG Token contract
     * @param _treasury Address holding rewards (Treasury wallet)
     * @param _rewardSigner Address that signs reward claims (Operator wallet)
     */
    constructor(
        address _idgToken,
        address _treasury,
        address _rewardSigner
    ) {
        require(_idgToken != address(0), "GameRewards: invalid token");
        require(_treasury != address(0), "GameRewards: invalid treasury");
        require(_rewardSigner != address(0), "GameRewards: invalid signer");
        
        idgToken = IERC20(_idgToken);
        treasury = _treasury;
        rewardSigner = _rewardSigner;
        
        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(SIGNER_ROLE, _rewardSigner);
        
        // Set initial limits (can be adjusted later)
        maxDailyRewardPerUser = 1_000_000 * 1e18;  // 1 million IDG per day
        maxSingleReward = 100_000 * 1e18;          // 100k IDG per claim
        claimCooldown = 0;                          // No cooldown initially
    }
    
    // ============================================
    // CLAIM FUNCTIONS
    // ============================================
    
    /**
     * @dev Claim dungeon rewards with server signature
     * @param amount Amount of IDG to claim (in wei, 18 decimals)
     * @param runId Unique dungeon run ID (to prevent double claims)
     * @param nonce User's nonce (must match current nonce)
     * @param expireTime Signature expiration timestamp
     * @param signature Server's signature authorizing this claim
     */
    function claimDungeonReward(
        uint256 amount,
        uint256 runId,
        uint256 nonce,
        uint256 expireTime,
        bytes calldata signature
    ) external nonReentrant whenNotPaused {
        address user = msg.sender;
        
        // Validate inputs
        require(amount > 0, "GameRewards: amount must be > 0");
        require(amount <= maxSingleReward, "GameRewards: exceeds single claim limit");
        require(!claimedRunIds[runId], "GameRewards: run already claimed");
        require(nonce == userNonces[user], "GameRewards: invalid nonce");
        require(block.timestamp <= expireTime, "GameRewards: signature expired");
        require(expireTime <= block.timestamp + signatureExpiration, "GameRewards: expire time too far");
        
        // Check cooldown
        if (claimCooldown > 0) {
            require(
                block.timestamp >= lastClaimTime[user] + claimCooldown,
                "GameRewards: claim cooldown active"
            );
        }
        
        // Check daily limit
        _checkAndUpdateDailyLimit(user, amount);
        
        // Verify signature
        bytes32 messageHash = keccak256(abi.encodePacked(
            user,
            amount,
            runId,
            nonce,
            expireTime,
            block.chainid,
            address(this)
        ));
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(messageHash);
        address recoveredSigner = ECDSA.recover(ethSignedHash, signature);
        require(recoveredSigner == rewardSigner, "GameRewards: invalid signature");
        
        // Update state BEFORE transfer (CEI pattern)
        claimedRunIds[runId] = true;
        userNonces[user] = nonce + 1;
        lastClaimTime[user] = block.timestamp;
        
        // Transfer tokens from treasury to user
        idgToken.safeTransferFrom(treasury, user, amount);
        
        emit RewardClaimed(user, amount, runId, nonce, block.timestamp);
    }
    
    /**
     * @dev Check and update daily reward limit
     */
    function _checkAndUpdateDailyLimit(address user, uint256 amount) internal {
        uint256 today = block.timestamp / 1 days;
        
        // Reset daily counter if new day
        if (lastClaimDay[user] != today) {
            lastClaimDay[user] = today;
            dailyRewardsClaimed[user] = 0;
        }
        
        require(
            dailyRewardsClaimed[user] + amount <= maxDailyRewardPerUser,
            "GameRewards: exceeds daily limit"
        );
        
        dailyRewardsClaimed[user] += amount;
    }
    
    // ============================================
    // VIEW FUNCTIONS
    // ============================================
    
    /**
     * @dev Get user's current nonce
     */
    function getNonce(address user) external view returns (uint256) {
        return userNonces[user];
    }
    
    /**
     * @dev Check if a run ID has been claimed
     */
    function isRunClaimed(uint256 runId) external view returns (bool) {
        return claimedRunIds[runId];
    }
    
    /**
     * @dev Get user's remaining daily reward allowance
     */
    function getRemainingDailyReward(address user) external view returns (uint256) {
        uint256 today = block.timestamp / 1 days;
        if (lastClaimDay[user] != today) {
            return maxDailyRewardPerUser;
        }
        if (dailyRewardsClaimed[user] >= maxDailyRewardPerUser) {
            return 0;
        }
        return maxDailyRewardPerUser - dailyRewardsClaimed[user];
    }
    
    /**
     * @dev Check if user can claim right now (cooldown check)
     */
    function canClaimNow(address user) external view returns (bool) {
        if (claimCooldown == 0) return true;
        return block.timestamp >= lastClaimTime[user] + claimCooldown;
    }
    
    /**
     * @dev Generate message hash for signing (helper for backend)
     */
    function getMessageHash(
        address user,
        uint256 amount,
        uint256 runId,
        uint256 nonce,
        uint256 expireTime
    ) external view returns (bytes32) {
        return keccak256(abi.encodePacked(
            user,
            amount,
            runId,
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
     * @dev Update treasury address
     */
    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newTreasury != address(0), "GameRewards: invalid treasury");
        address oldTreasury = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }
    
    /**
     * @dev Update reward signer address
     */
    function setRewardSigner(address newSigner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newSigner != address(0), "GameRewards: invalid signer");
        address oldSigner = rewardSigner;
        rewardSigner = newSigner;
        
        // Revoke old signer role and grant new
        _revokeRole(SIGNER_ROLE, oldSigner);
        _grantRole(SIGNER_ROLE, newSigner);
        
        emit SignerUpdated(oldSigner, newSigner);
    }
    
    /**
     * @dev Update claim limits
     */
    function setLimits(
        uint256 _maxDaily,
        uint256 _maxSingle,
        uint256 _cooldown
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxDailyRewardPerUser = _maxDaily;
        maxSingleReward = _maxSingle;
        claimCooldown = _cooldown;
        emit LimitsUpdated(_maxDaily, _maxSingle, _cooldown);
    }
    
    /**
     * @dev Update signature expiration time
     */
    function setSignatureExpiration(uint256 _expiration) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_expiration >= 5 minutes, "GameRewards: expiration too short");
        require(_expiration <= 24 hours, "GameRewards: expiration too long");
        signatureExpiration = _expiration;
    }
    
    /**
     * @dev Pause all claims (emergency)
     */
    function pause() external onlyRole(OPERATOR_ROLE) {
        _pause();
    }
    
    /**
     * @dev Unpause claims
     */
    function unpause() external onlyRole(OPERATOR_ROLE) {
        _unpause();
    }
    
    /**
     * @dev Emergency withdraw tokens (only admin, only if contract holds tokens)
     * This should never be needed as tokens flow directly from Treasury
     */
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "GameRewards: invalid recipient");
        IERC20(token).safeTransfer(to, amount);
        emit EmergencyWithdraw(token, to, amount);
    }
}
