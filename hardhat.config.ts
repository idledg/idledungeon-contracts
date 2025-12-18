import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";

dotenv.config();

// Private keys for deployment - NEVER commit these to git!
const OWNER_PRIVATE_KEY = process.env.OWNER_PRIVATE_KEY || "";
const TREASURY_ADDRESS = process.env.TREASURY_ADDRESS || "";
const OPERATOR_ADDRESS = process.env.OPERATOR_ADDRESS || "";

const config: HardhatUserConfig = {
    solidity: {
        version: "0.8.20",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200
            },
            viaIR: true
        }
    },
    networks: {
        // BSC Mainnet
        bsc: {
            url: "https://bsc-dataseed.binance.org",
            chainId: 56,
            accounts: OWNER_PRIVATE_KEY ? [OWNER_PRIVATE_KEY] : [],
            gasPrice: 3000000000, // 3 gwei
        },
        // BSC Testnet (for testing)
        bscTestnet: {
            url: "https://data-seed-prebsc-1-s1.binance.org:8545",
            chainId: 97,
            accounts: OWNER_PRIVATE_KEY ? [OWNER_PRIVATE_KEY] : [],
            gasPrice: 10000000000, // 10 gwei
        },
        // Local Hardhat network for testing
        hardhat: {
            chainId: 31337,
        }
    },
    etherscan: {
        apiKey: {
            bsc: process.env.BSCSCAN_API_KEY || "",
            bscTestnet: process.env.BSCSCAN_API_KEY || ""
        },
        customChains: [
            {
                network: "bsc",
                chainId: 56,
                urls: {
                    apiURL: "https://api.bscscan.com/api",
                    browserURL: "https://bscscan.com"
                }
            },
            {
                network: "bscTestnet",
                chainId: 97,
                urls: {
                    apiURL: "https://api-testnet.bscscan.com/api",
                    browserURL: "https://testnet.bscscan.com"
                }
            }
        ]
    },
    paths: {
        sources: "./",
        tests: "./test",
        cache: "./cache",
        artifacts: "./artifacts"
    }
};

export default config;
