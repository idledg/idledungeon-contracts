# IDLE Dungeon Game (IDG) - Smart Contracts

A **Web3 Idle RPG Game** with tokenized economy built on **BNB Smart Chain (BSC)**. Players earn IDG tokens by completing dungeons and can purchase mystery boxes to get NFT characters and items.

## Technology Stack

- **Blockchain**: BNB Smart Chain (BSC) Mainnet
- **Smart Contracts**: Solidity ^0.8.19
- **Token Standard**: ERC20 (IDG Token), ERC721 (Character & Item NFTs)
- **Development**: Hardhat, OpenZeppelin v4.9.3
- **Security**: AccessControl, ReentrancyGuard, Pausable

## Supported Networks

| Network | Chain ID | Status |
|---------|----------|--------|
| BNB Smart Chain Mainnet | 56 | ✅ Deployed |
| BNB Smart Chain Testnet | 97 | Available |

## Contract Addresses (BSC Mainnet)

| Contract | Address | Verified |
|----------|---------|----------|
| **IDG Token** | `0xB28fE770a2Ffb9942Cfc0516aDf7d2F9Cd43ade1` | ✅ |
| **CharacterNFT** | `0x52E792a6cd5Ec6f607ebf64bae836e1fc30415Aa` | ✅ |
| **ItemNFT** | `0x333ff91F0055dE1861661Eee2AE2DBb244d914dC` | ✅ |
| **GameShop** | `0x92474ef2572186fD45494B66c30d44f7cBbfbA45` | ✅ |
| **GameRewards** | `0xf94c90EF8994d5a33977f973E483a43699848Db9` | ✅ |

## Features

- 🪙 **IDG Token**: Utility token with burn mechanism for deflationary tokenomics
- 🦸 **Character NFTs**: ERC721 heroes with randomized stats and elements
- ⚔️ **Item NFTs**: ERC721 equipment with stat bonuses
- 🛒 **GameShop**: Purchase mystery boxes using IDG tokens (burn model)
- 🏆 **GameRewards**: Claim dungeon rewards on-chain with signature verification
- 🔐 **Security**: Role-based access control, anti-replay signatures, pausable contracts

## Contracts Overview

### IDGToken.sol
- ERC20 token with 10 billion total supply
- Burn functionality for deflationary model
- Minter role for controlled minting

### CharacterNFT.sol
- ERC721 NFT for game characters
- Metadata includes class (S/A/B/C/D), element, and stats
- Operator can mint for players

### ItemNFT.sol
- ERC721 NFT for game items/equipment
- Supports weapon, armor, accessory, card slot types
- Rarity system matching character classes

### GameShop.sol
- Purchase mystery boxes with IDG tokens
- Signature-based authorization (anti-cheat)
- Tokens are burned on purchase (deflationary)

### GameRewards.sol
- Claim dungeon rewards as IDG tokens
- Signature verification with expiry and nonce
- Prevents double claiming with nonce tracking

## Quick Start

### Prerequisites
- Node.js v18+
- npm or yarn

### Installation
```bash
npm install
```

### Configuration
Copy `.env.example` to `.env` and fill in your values:
```bash
cp .env.example .env
```

Required environment variables:
- `OWNER_PRIVATE_KEY` - Deployer wallet private key
- `TREASURY_ADDRESS` - Treasury wallet for rewards
- `OPERATOR_ADDRESS` - Operator wallet for signing
- `BSCSCAN_API_KEY` - For contract verification

### Compile
```bash
npx hardhat compile
```

### Deploy
```bash
npx hardhat run scripts/deploy-idg-token.js --network bscMainnet
```

### Verify on BSCScan
```bash
npx hardhat verify --network bscMainnet <CONTRACT_ADDRESS> <CONSTRUCTOR_ARGS>
```

## Security

### ✅ Security Status (Updated Dec 18, 2025)

| Feature | Status | Transaction |
|---------|--------|-------------|
| **Ownership Renounced** | ✅ Done | All admin roles have been renounced |
| **Anti-Whale Disabled** | ✅ Done | maxTransferAmount set to 0 (unlimited) |
| **No Mint Function** | ✅ Safe | Fixed supply, cannot mint new tokens |
| **Transfer Tax** | ✅ 0% | No buy/sell tax |

### ⚠️ Features in Code (But Unusable)

These features exist in the contract code but **cannot be used** because all roles have been renounced:

- **Blacklist**: Cannot add/remove addresses (no OPERATOR_ROLE holder)
- **Pause**: Cannot pause transfers (no PAUSER_ROLE holder)
- **Anti-Whale Settings**: Cannot modify limits (no DEFAULT_ADMIN_ROLE holder)

### Renouncement Transactions

| Role | Transaction Hash |
|------|------------------|
| DEFAULT_ADMIN_ROLE | `0x93e625bead25e5d161120af230c05880c834ceb6ee7f4d4db722e51eb2998e59` |
| PAUSER_ROLE | `0xd2c723d0433a969380d25f541a7426e3050373a8bf1f59ab2cd7ef719c59f9d5` |
| OPERATOR_ROLE | `0x6210c8a90ef55e47271316e3678c2061174202e7be40e74d7261806aed2391c7` |

### Contract Security Features

- All contracts use OpenZeppelin's battle-tested libraries
- Signature verification with expiry to prevent replay attacks
- ReentrancyGuard on all state-changing functions

## License

MIT License

## Links

- **Website**: [https://idledg.com](https://idledg.com)
- **BSCScan (IDG Token)**: [View on BSCScan](https://bscscan.com/token/0xB28fE770a2Ffb9942Cfc0516aDf7d2F9Cd43ade1)
- **X**: [@idledungeon](https://x.com/idledungeon)

---

Built with ❤️ on BNB Smart Chain
