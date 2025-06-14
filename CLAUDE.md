# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

PayNest is an Aragon OSx plugin ecosystem for payment infrastructure. The project transforms standalone payment contracts into modular Aragon plugins supporting streaming and scheduled payments with username-based addressing.

### PayNest Components

- **AddressRegistry**: Global username → address mapping (standalone contract)
- **PaymentsPlugin**: Aragon plugin handling streams (LlamaPay) and scheduled payments
- **PaymentsPluginSetup**: Plugin installation/permission management for DAOs
- **PayNestDAOFactory**: Creates DAOs with Admin + PayNest plugins in one transaction

### PayNestDAOFactory Constructor

**IMPORTANT**: The factory now requires 5 parameters:

```solidity
constructor(
    AddressRegistry _addressRegistry,    // Username registry
    DAOFactory _daoFactory,             // Aragon's DAO factory
    PluginRepo _adminPluginRepo,        // Admin plugin repository
    PluginRepo _paymentsPluginRepo,     // Payments plugin repository  
    address _llamaPayFactory            // LlamaPay factory address (NEW)
)
```

This ensures the factory knows which LlamaPay factory to use when creating payment streams.

### Aragon Integration

- PayNest contracts serve as the reference implementation for Aragon OSx plugins
- `PaymentsPlugin.sol` demonstrates proper `PluginUUPSUpgradeable` inheritance patterns
- `PaymentsPluginSetup.sol` shows correct plugin installation and permission management
- `MANAGER_PERMISSION_ID` controls who can call plugin functions
- `EXECUTE_PERMISSION_ID` allows plugins to execute actions on the DAO
- Admin plugin provides single-owner control with upgrade path to complex governance

## Essential Commands

### Build and Test

```bash
# Build contracts
forge build

# Run unit tests (local only)
make test

# Run fork tests (requires RPC_URL)
make test-fork

# Generate test coverage report
make test-coverage
```

### Test Management with Bulloak

```bash
# Sync YAML test definitions to Solidity
make sync-tests

# Check if test files are out of sync
make check-tests

# Generate markdown test documentation
make markdown-tests
```

### Deployment

```bash
# Simulate deployment
make predeploy

# Deploy to network (runs tests first)
make deploy

# Resume failed deployment
make resume
```

### Contract Verification

```bash
# Verify on Etherscan-compatible explorers
make verify-etherscan

# Verify on BlockScout
make verify-blockscout

# Verify on Sourcify
make verify-sourcify
```

### Git Hooks

A pre-commit hook is configured to automatically format Solidity files with `forge fmt` before commits. This prevents CI formatting failures by ensuring all committed code follows consistent formatting standards.

The hook:
- Runs `forge fmt` on staged `.sol` files
- Adds formatted changes back to the commit automatically
- Verifies formatting with `forge fmt --check` before allowing the commit
- Only processes commits that include Solidity files

## Development Workflow

### PayNest Development

- PayNest contracts are now the reference implementation for Aragon OSx plugins
- `PaymentsPlugin.sol` → Reference for UUPS upgradeable plugin architecture
- `PaymentsPluginSetup.sol` → Reference for plugin setup and permission management
- `PayNestDAOFactory.sol` → Reference for single-transaction DAO creation with plugins
- Follow existing Aragon permission patterns with `auth()` modifiers
- Test using `PaymentsBuilder` and `PaymentsForkBuilder` patterns

## Project Structure

### Specifications (Planning Phase)

- `docs/address-registry-spec.md` - Username mapping system
- `docs/payments-plugin-spec.md` - Streaming + scheduled payments
- `docs/dao-factory-spec.md` - Single-transaction DAO creation
- `docs/llamapay-integration-spec.md` - LlamaPay streaming integration
- `docs/testing-strategy.md` - Comprehensive testing approach

### Implementation Contracts (Deployed on Base Mainnet)

- `src/AddressRegistry.sol` - Standalone username registry ✅ **Deployed & Verified**
- `src/PaymentsPlugin.sol` - Main plugin (UUPS upgradeable) ✅ **Deployed & Verified**
- `src/setup/PaymentsPluginSetup.sol` - Plugin setup ✅ **Deployed & Verified**
- `src/factory/PayNestDAOFactory.sol` - DAO creation factory ✅ **Deployed & Verified**

### Dependencies

- Aragon OSx: Core DAO and plugin framework (`lib/osx/`)
- OpenZeppelin: Upgradeable contracts (`lib/openzeppelin-contracts-upgradeable/`)
- LlamaPay: Streaming protocol integration
- Bulloak: YAML → Solidity test conversion

## Coding Style Guide

### Error Handling

- **ALWAYS use custom errors instead of require statements**
- Custom errors are more gas efficient and provide better error messages
- Example:

  ```solidity
  // ❌ NEVER use this
  require(amount > 0, "Amount must be positive");

  // ✅ ALWAYS use this
  if (amount == 0) revert AmountMustBePositive();
  ```

### Documentation

- **Provide verbose comments** for all functions and complex logic
- Use NatSpec comments for all public/external functions
- Explain the "why" not just the "what"
- Document all assumptions and edge cases

### Code Style

- Use explicit error names that describe the issue
- Group custom errors at the top of the contract
- Maintain consistency across all contracts
- Follow the existing PayNest contract patterns

## Key Implementation Notes

### Contract Development

- Use PayNest contracts as reference implementations for new plugins
- Follow Aragon permission system patterns as demonstrated in `PaymentsPlugin.sol`
- Use specifications in `docs/` folder for requirements and invariants
- Implement contracts to match specification behavior, not implementation details

### Testing Approach

- **Unit Testing**: Fast feedback loop with mocks for development
- **Fork Testing**: Real contract integration for production confidence
- **Builder Patterns**: Use `PaymentsForkBuilder` for fork tests, `PaymentsBuilder` for unit tests
- **Bulloak Scaffolding**: YAML-driven test structure for consistency
- **Real Contract Testing**: All 33 fork tests run against live Base mainnet
- **Stream Migration**: User-driven migration system for wallet recovery scenarios
- **Test Coverage**: 213 total tests (130+ unit + 33 fork + 39 invariant) all passing
- **Invariant Testing**: 33M+ function calls across comprehensive property-based tests

## Git Workflow

### Commit Messages

- Use conventional commits format: `type(scope): description`
- Types: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`
- Examples:
  - `feat(plugin): add stream creation functionality`
  - `docs(specs): update payments plugin specification`
  - `test(registry): add username validation tests`
  - `fix(factory): handle DAO creation failures properly`

## Fork Testing Implementation Lessons

### Key Discoveries and Solutions

#### **PaymentsForkBuilder Design**

- **Pattern**: Uses real DAOFactory and PluginRepoFactory for production-like testing
- **DAO Creation**: `daoFactory.createDao(daoSettings, installSettings)` with plugin installation
- **Plugin Repo**: Creates plugin repo with `pluginRepoFactory.createPluginRepoWithFirstVersion()`
- **Environment**: Requires correct Base mainnet Aragon addresses in `.env` file
- **Success**: All fork tests passing with official Aragon infrastructure

#### **Real Contract Behavior Adaptations**

- **USDC Approval**: Real USDC doesn't use `type(uint256).max`, check for sufficient approval instead
- **LlamaPay Stream Lifecycle**: Cancelled streams revert with "stream doesn't exist" on `withdrawable()` calls
- **Event Emission Timing**: `vm.expectEmit()` must be placed immediately before the action, not after
- **Network Latency**: Fork tests take 5+ seconds vs milliseconds for mocked tests

#### **Bulloak Integration Patterns**

- **YAML Location**: Keep YAML files in `test/` directory alongside Solidity tests
- **Tree Generation**: Use `deno run ./script/make-test-tree.ts` for YAML → tree conversion
- **Test Scaffolding**: `make sync-tests` generates Solidity from tree files
- **Format**: Use `given/when/then` structure matching existing project patterns

#### **Permission System Testing**

- **Unauthorized Caller**: Use `address(this)` (test contract) for permission failures, not predefined actors
- **Error Matching**: Ensure actual error addresses match expected addresses in `DaoUnauthorized` events
- **Context Matters**: Fork tests run in different context than unit tests for permission checking

#### **Real Contract Addresses (Base Mainnet)**

```solidity
address constant LLAMAPAY_FACTORY_BASE = 0x09c39B8311e4B7c678cBDAD76556877ecD3aEa07;
address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
address constant USDC_WHALE = 0x0B0A5886664376F59C351ba3f598C8A8B4D0A6f3;
```

### Testing Commands Reference

```bash
# Fast unit tests (mocked) - 130+ tests
forge test --match-path "./test/*.sol"

# Production fork tests (real contracts) - 33 tests
forge test --match-contract "*Fork*"

# Invariant tests (property-based) - 39 tests
forge test --match-contract "*Invariant*"

# All tests (mixed) - 213 tests
forge test

# Always use verbose output for debugging
forge test -vvv
```

## Testing Tips

- Always run tests with at least -vvv so you can see the stack trace
- Fork tests prove production readiness but unit tests provide fast development feedback
- Use `PaymentsForkBuilder` pattern for any new fork test implementations
- Real LlamaPay behavior may differ from mocks - test both scenarios
