# sSuperUSD Oracle System

A robust oracle system for sSuperUSD price feeds with fallback mechanisms and EMA calculations.

## Overview

The sSuperUSD Oracle System consists of three main components:
- `sSuperUSDOracle`: Primary oracle that reads price data directly from the Accountant contract
- `sSuperUSDFallbackOracle`: Backup oracle system
- `sSuperUSDMorphoOracle`: Advanced oracle implementation with EMA calculations and fallback mechanism

## Contract Details

### sSuperUSDOracle

The primary oracle contract that provides price data for sSuperUSD.

**Key Features:**
- Direct integration with Accountant contract
- Price conversion from 6 decimals to 8 decimals
- Immutable Accountant address
- Owner-controlled contract with ownership transfer capability
- Real-time price updates from Accountant

### sSuperUSDFallbackOracle

The secondary oracle contract that provides price data for sSuperUSD.

**Key Features:**
- Reads the TWAP from a Uniswap V3 pool
- Price conversion to 8 decimals
- Immutable pool address
- TWAP interval can be adjusted by contract owner
- Price updates over time and trades

### sSuperUSDMorphoOracle

An advanced oracle implementation with additional safety features.

**Key Features:**
- EMA (Exponential Moving Average) price calculations
- Dynamic price bounds for security
- Fallback mechanism for stale or out-of-range prices
- Timelock contract ownership for enhanced security
- Mutable oracle addresses for upgradability

**Price Bound Parameters:**
- Initial Lower Bound: 0.95
- Initial Upper Bound: 1.005
- Bounds are dynamically updated with each price update:
  - New Upper Bound = EMA Price × 1.005
  - New Lower Bound = EMA Price × 0.95

## Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation.html)
- Solidity ^0.8.21

### Build and Test

```shell
# Build contracts
forge build

# Run tests
forge test

# Format code
forge fmt

# Generate gas snapshots
forge snapshot
```

### Local Development

Start a local Ethereum node:
```shell
anvil
```

### Deployment

#### Deploy sSuperUSDOracle

```shell
forge script script/DeploysSuperUSDOracle.s.sol:DeploySSuperUSDOracle \
  --rpc-url <your_rpc_url> \
  --private-key <your_private_key>
```

#### Deploy sSuperUSDMorphoOracle

```shell
forge script script/DeploysSuperUSDMorphoOracle.s.sol:DeploySSuperUSDOracle \
  --rpc-url <your_rpc_url> \
  --private-key <your_private_key>
```

**Important:** Set your `PRIVATE_KEY` environment variable before running deployment scripts.

### Utilities

```shell
# Use Cast for contract interactions
cast <subcommand>

# Access help documentation
forge --help
anvil --help
cast --help
```

## Security Considerations

1. **Price Staleness Protection**
   - sSuperUSDMorphoOracle implements staleness checks
   - Fallback mechanism activates when primary oracle data is stale

2. **Price Bounds**
   - Dynamic price bounds prevent extreme price movements
   - Automatic fallback to secondary oracle when price is out of bounds

3. **Access Control**
   - sSuperUSDMorphoOracle is controlled by a timelock contract
   - Owner functions are protected with access control modifiers

## License

MIT License