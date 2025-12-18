// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title IDGToken - IDLE Dungeon Token
 * @dev ERC20 Token for IDLE Dungeon game on BSC (BNB Smart Chain)
 * 
 * Security Features:
 * - Fixed supply (no minting after deployment)
 * - Role-based access control
 * - Pausable in emergency
 * - Anti-whale transfer limits
 * - Blacklist for malicious addresses
 * - ReentrancyGuard for all critical functions
 * 
 * Roles:
 * - DEFAULT_ADMIN_ROLE: Full control, can grant/revoke roles
 * - PAUSER_ROLE: Can pause/unpause transfers
 * - OPERATOR_ROLE: Can manage blacklist
 */
contract IDGToken is ERC20, ERC20Burnable, AccessControl, Pausable, ReentrancyGuard {
    
    // ============================================
    // ROLES
    // ============================================
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    // ============================================
    // STATE VARIABLES
    // ============================================
    
    // Anti-whale: Maximum transfer amount per transaction (0 = unlimited)
    uint256 public maxTransferAmount;
    
    // Addresses exempt from transfer limits (e.g., Treasury, DEX)
    mapping(address => bool) public isExemptFromLimit;
    
    // Blacklisted addresses (cannot send or receive)
    mapping(address => bool) public isBlacklisted;
    
    // ============================================
    // EVENTS
    // ============================================
    event MaxTransferAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event ExemptFromLimitUpdated(address indexed account, bool exempt);
    event BlacklistUpdated(address indexed account, bool blacklisted);
    
    // ============================================
    // CONSTRUCTOR
    // ============================================
    
    /**
     * @dev Deploys IDG Token with fixed supply
     * @param initialSupply Total supply to mint (with 18 decimals)
     * @param treasury Address to receive initial supply
     * 
     * Initial supply = 10,000,000,000 * 10^18 = 10 billion IDG
     */
    constructor(
        uint256 initialSupply,
        address treasury
    ) ERC20("IDLE Dungeon", "IDG") {
        require(treasury != address(0), "IDG: treasury cannot be zero address");
        require(initialSupply > 0, "IDG: initial supply must be greater than 0");
        
        // Grant roles to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        
        // Mint entire supply to treasury
        _mint(treasury, initialSupply);
        
        // Set initial max transfer to 1% of supply (anti-whale)
        maxTransferAmount = initialSupply / 100;
        
        // Exempt treasury from limits
        isExemptFromLimit[treasury] = true;
        isExemptFromLimit[msg.sender] = true;
    }
    
    // ============================================
    // ADMIN FUNCTIONS
    // ============================================
    
    /**
     * @dev Update maximum transfer amount
     * @param newAmount New max amount (0 = unlimited)
     */
    function setMaxTransferAmount(uint256 newAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldAmount = maxTransferAmount;
        maxTransferAmount = newAmount;
        emit MaxTransferAmountUpdated(oldAmount, newAmount);
    }
    
    /**
     * @dev Set address exempt from transfer limits
     * @param account Address to update
     * @param exempt True to exempt, false to apply limits
     */
    function setExemptFromLimit(address account, bool exempt) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isExemptFromLimit[account] = exempt;
        emit ExemptFromLimitUpdated(account, exempt);
    }
    
    /**
     * @dev Add/remove address from blacklist
     * @param account Address to update
     * @param blacklisted True to blacklist, false to remove
     */
    function setBlacklist(address account, bool blacklisted) external onlyRole(OPERATOR_ROLE) {
        require(account != address(0), "IDG: cannot blacklist zero address");
        isBlacklisted[account] = blacklisted;
        emit BlacklistUpdated(account, blacklisted);
    }
    
    /**
     * @dev Pause all token transfers (emergency)
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }
    
    /**
     * @dev Unpause token transfers
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
    
    // ============================================
    // OVERRIDE FUNCTIONS
    // ============================================
    
    /**
     * @dev Hook called before any transfer
     * Implements: pause check, blacklist check, transfer limit check
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);
        
        // Check pause state
        require(!paused(), "IDG: token transfer while paused");
        
        // Check blacklist (skip for mint/burn)
        if (from != address(0)) {
            require(!isBlacklisted[from], "IDG: sender is blacklisted");
        }
        if (to != address(0)) {
            require(!isBlacklisted[to], "IDG: recipient is blacklisted");
        }
        
        // Check transfer limit (skip for mint/burn and exempt addresses)
        if (from != address(0) && to != address(0)) {
            if (maxTransferAmount > 0) {
                if (!isExemptFromLimit[from] && !isExemptFromLimit[to]) {
                    require(amount <= maxTransferAmount, "IDG: transfer amount exceeds limit");
                }
            }
        }
    }
    
    // ============================================
    // VIEW FUNCTIONS
    // ============================================
    
    /**
     * @dev Check if transfer would succeed
     * @param from Sender address
     * @param to Recipient address  
     * @param amount Amount to transfer
     * @return success True if transfer would succeed
     * @return reason Error message if would fail
     */
    function canTransfer(
        address from,
        address to,
        uint256 amount
    ) external view returns (bool success, string memory reason) {
        if (paused()) {
            return (false, "Token transfers are paused");
        }
        if (isBlacklisted[from]) {
            return (false, "Sender is blacklisted");
        }
        if (isBlacklisted[to]) {
            return (false, "Recipient is blacklisted");
        }
        if (maxTransferAmount > 0 && !isExemptFromLimit[from] && !isExemptFromLimit[to]) {
            if (amount > maxTransferAmount) {
                return (false, "Transfer amount exceeds limit");
            }
        }
        if (balanceOf(from) < amount) {
            return (false, "Insufficient balance");
        }
        return (true, "");
    }
    
    /**
     * @dev Required override for AccessControl
     */
    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        override(AccessControl) 
        returns (bool) 
    {
        return super.supportsInterface(interfaceId);
    }
}
