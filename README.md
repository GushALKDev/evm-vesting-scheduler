# 🔐 Vesting Scheduler

> A production-ready, gas-optimized ERC20 token vesting smart contract showcasing Solidity best practices and DeFi development patterns.

[![Solidity](https://img.shields.io/badge/Solidity-0.8.24-363636?logo=solidity)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C?logo=foundry)](https://book.getfoundry.sh/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

---

## 🎯 Overview

This project implements a **linear token vesting contract** with configurable cliff periods, commonly used in DeFi protocols for team allocations, investor distributions, and ecosystem incentives.

### Key Highlights

| Aspect | Implementation |
|--------|----------------|
| **Architecture** | Minimalist single-contract design with CEI pattern |
| **Gas Efficiency** | Struct packing reduces storage from 5 to 3 slots (~40% savings) |
| **Security** | Custom errors, immutable variables, access control |
| **Testing** | Unit tests, edge cases, and fuzz testing with 100% coverage |
| **Code Quality** | NatSpec documentation, clean code principles |

---

## 🧠 Technical Decisions

### Storage Optimization

Variables are packed by size to minimize storage slots:

```solidity
struct VestingSchedule {
    // Slot 1 (Packed): 1+8+8+8 = 25 bytes ✅
    bool initialized;        
    uint64 startTime;        
    uint64 cliffDuration;    
    uint64 vestingDuration;  
    // Slot 2
    uint256 totalAmount;     
    // Slot 3
    uint256 amountClaimed;   
}
```

> **Result**: 3 storage slots instead of 5, saving ~4,200 gas per schedule creation.

### Security Patterns

- **CEI Pattern**: Checks-Effects-Interactions prevents reentrancy
- **Custom Errors**: Gas-efficient vs string reverts (~200 gas savings per revert)
- **Immutable Variables**: `TOKEN` and `ADMIN` are set once, reducing SLOAD costs

### Gas Benchmarks

| Function | Gas Cost |
|----------|----------|
| `createSchedule` | ~75,000 |
| `release` (first claim) | ~45,000 |
| `release` (subsequent) | ~35,000 |

---

## 📋 How It Works

```
|<-------- Cliff -------->|<-------- Linear Vesting -------->|
|         ❌ 0%           |    📈 Proportional Release       |
Start                   Cliff End                      Full Vest (100%)
```

1. **Admin creates schedule** → Tokens locked in contract
2. **Cliff period passes** → First tokens become claimable
3. **Linear vesting** → Tokens vest proportionally over time
4. **Beneficiary claims** → Accumulated tokens released on demand

---

## 🚀 Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Setup

```bash
git clone https://github.com/GushALKDev/evm-vesting-scheduler.git
cd evm-vesting-scheduler
forge install
```

### Build & Test

```bash
# Compile contracts
forge build

# Run test suite
forge test

# Run with gas report
forge test --gas-report

# Run fuzz tests with more runs
forge test --match-test "testFuzz" --fuzz-runs 10000
```

### Deploy

```bash
# Set environment
export TOKEN_ADDRESS=<erc20_token_address>

# Deploy to network
forge script script/VestingScheduler.s.sol:VestingSchedulerScript \
    --rpc-url <rpc_url> \
    --broadcast \
    --private-key $PRIVATE_KEY
```

---

## 📖 Contract Interface

### createSchedule

Creates a vesting schedule for a beneficiary.

```solidity
function createSchedule(
    address _beneficiary,      
    uint256 _totalAmount,      
    uint64 _startTime,         
    uint64 _cliffDuration,     
    uint64 _vestingDuration    
) external onlyAdmin
```

### release

Beneficiary claims all vested tokens.

```solidity
function release() external
```

### getSchedule

Admin views schedule details.

```solidity
function getSchedule(address _beneficiary) external view onlyAdmin returns (VestingSchedule memory)
```

---

## 🧪 Test Coverage

| Category | Tests | Description |
|----------|-------|-------------|
| **Unit Tests** | 15+ | Core functionality validation |
| **Edge Cases** | 8+ | Zero cliff, cliff = duration, boundary conditions |
| **Access Control** | 4+ | onlyAdmin restrictions |
| **Fuzz Tests** | 3+ | Randomized mathematical accuracy verification |

```bash
# Run specific categories
forge test --match-test "test_CreateSchedule"
forge test --match-test "test_Release"
forge test --match-test "testFuzz"
```

---

## 🏗️ Project Structure

```
├── src/
│   └── VestingScheduler.sol    # Main contract (266 lines)
├── script/
│   └── VestingScheduler.s.sol  # Deployment script
├── test/
│   ├── VestingScheduler.t.sol  # Comprehensive test suite
│   └── mocks/
│       └── MockERC20.sol       # Test helper
└── foundry.toml
```

---

## 🔒 Security Checklist

- [x] Reentrancy protection via CEI pattern
- [x] Integer overflow protection (Solidity 0.8+)
- [x] Access control on admin functions
- [x] Input validation on all public functions
- [x] No external calls before state changes
- [x] Immutable for constant addresses

---

## 📄 License

MIT License

---

## 👤 Author

**GushALKDev** — Solidity Developer

[![GitHub](https://img.shields.io/badge/GitHub-GushALKDev-181717?logo=github)](https://github.com/GushALKDev)

---

<p align="center">
  <i>Built with Foundry 🔨</i>
</p>
