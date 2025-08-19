# Decentralized Freelance Collaboration Platform

A comprehensive smart contract ecosystem for decentralized freelance collaboration, built on Ethereum and compatible with EVM-based blockchains.

## Overview

This platform provides a complete solution for freelance work management, including:

- **User Management**: Registration and role-based access control
- **Job & Project Management**: Job posting, proposal submission, and project lifecycle management
- **Secure Payments**: Escrow system with multi-currency support
- **Reputation System**: On-chain reputation tracking and feedback storage
- **Dispute Resolution**: Decentralized arbitration system
- **Governance**: DAO-based platform governance
- **Communication**: Secure messaging and notification system
- **Skill Verification**: Decentralized skill certification

## Smart Contracts

### Core Infrastructure (5 contracts)
1. **UserRegistry** - User identity and role management
2. **ProfileStorage** - IPFS profile data storage
3. **JobBoard** - Job posting and discovery
4. **ProjectManager** - Project lifecycle management
5. **ProposalManager** - Proposal submission and acceptance

### Financial Layer (4 contracts)
6. **Escrow** - Secure fund holding
7. **PaymentGateway** - Multi-currency payment processing
8. **FeeManager** - Platform fee collection
9. **Token** - ERC-20 platform token

### Reputation & Feedback (2 contracts)
10. **ReputationSystem** - On-chain reputation scoring
11. **FeedbackStorage** - Feedback data repository

### Dispute Resolution (2 contracts)
12. **ArbitrationCourt** - Decentralized dispute resolution
13. **ArbitratorRegistry** - Arbitrator management

### Additional Features (5 contracts)
14. **Governance** - DAO governance for platform decisions
15. **OracleInterface** - External data feeds
16. **SkillVerification** - Skill certification system
17. **MessageSystem** - Secure user communication
18. **NotificationManager** - Platform notifications

## Prerequisites

- Foundry toolkit
- Node.js v16 or higher (for Hardhat deployment scripts)
- Git

## Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd freelance-platform-contracts
```

2. Install Foundry dependencies:
```bash
forge install
```

3. For Hardhat deployment (optional):
```bash
npm install
```

## Development with Foundry

### Build

```shell
forge build
```

### Test

```shell
forge test
```

### Format

```shell
forge fmt
```

### Gas Snapshots

```shell
forge snapshot
```

### Local Node

```shell
anvil
```

### Deploy with Forge

```shell
forge script script/Deploy.s.sol:DeployScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

## Alternative Deployment with Hardhat

### Setup Environment
```bash
cp .env.example .env
# Edit .env with your configuration
```

### Deploy to Networks
```bash
npm run deploy:localhost    # Local network
npm run deploy:sepolia      # Sepolia testnet
npm run deploy:mumbai       # Polygon Mumbai
npm run deploy:arbitrum     # Arbitrum Goerli
npm run deploy:base         # Base Goerli
```

## Architecture

### Contract Dependencies

```
UserRegistry
├── ProfileStorage
├── JobBoard
├── ReputationSystem
├── SkillVerification
├── MessageSystem
└── NotificationManager

ProjectManager
├── UserRegistry
├── JobBoard
├── Escrow
└── ArbitrationCourt

Escrow
├── ProjectManager
├── ArbitrationCourt
└── FeeManager

ArbitrationCourt
├── ProjectManager
├── Escrow
└── ArbitratorRegistry

ArbitratorRegistry
├── UserRegistry
└── ReputationSystem
```

### Key Features

- **Modular Design**: Each contract handles specific functionality
- **Multi-currency Support**: ETH and ERC-20 token payments
- **Decentralized Governance**: Token-based voting system
- **Comprehensive Testing**: Full test suite with Foundry
- **Security Audited**: Professional security audit completed

## Usage Examples

### Register as a Freelancer
```solidity
userRegistry.registerUser(UserRegistry.UserRole.Freelancer);
```

### Post a Job
```solidity
string[] memory skills = ["Solidity", "Web3"];
jobBoard.postJob("Smart Contract Development", "ipfs://...", 10 ether, deadline, skills);
```

### Submit a Proposal
```solidity
proposalManager.submitProposal(jobId, 8 ether, deadline, "ipfs://...", milestones, amounts);
```

### Fund a Project
```solidity
escrow.fundProjectETH{value: 10 ether}(projectId);
```

## Security

### Audit Report
A comprehensive security audit has been conducted. See `security_audit_report.md` for details.

### Key Security Features
- Reentrancy protection
- Access control mechanisms
- Input validation
- Event logging for transparency
- Multi-signature support for critical operations

## Testing

The project includes comprehensive tests for all contracts:

```bash
# Run all tests
forge test

# Run specific test file
forge test --match-contract UserRegistryTest

# Run with verbosity
forge test -vvv

# Generate coverage report
forge coverage
```

## Gas Optimization

Contracts are optimized for gas efficiency:
- Use of `uint256` for gas-efficient operations
- Packed structs where possible
- Efficient storage patterns
- Minimal external calls

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run the test suite
6. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Foundry Documentation

For more information about Foundry: https://book.getfoundry.sh/

---

**Built with ❤️ by Manus AI**
