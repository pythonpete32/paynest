# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

PayNest is an Aragon OSx plugin ecosystem for payment infrastructure. The project transforms standalone payment contracts into modular Aragon plugins supporting streaming and scheduled payments with username-based addressing.

### PayNest Components

- **AddressRegistry**: Global username → address mapping (standalone contract)
- **PaymentsPlugin**: Aragon plugin handling streams (LlamaPay) and scheduled payments
- **PaymentsPluginSetup**: Plugin installation/permission management for DAOs
- **PayNestDAOFactory**: Creates DAOs with Admin + PayNest plugins in one transaction

### Aragon Integration

- Use existing boilerplate contracts as guides (`MyUpgradeablePlugin.sol`, `MyPluginSetup.sol`)
- Plugins inherit from `PluginUUPSUpgradeable` for upgradeable variants
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

## Development Workflow

### PayNest Development

- Use boilerplate contracts as guides - DON'T remove them
- `MyUpgradeablePlugin.sol` → Reference for PaymentsPlugin structure
- `MyPluginSetup.sol` → Reference for PaymentsPluginSetup structure
- Follow existing Aragon permission patterns with `auth()` modifiers
- Test using `SimpleBuilder` and `ForkBuilder` patterns

### Testing Strategy

- Tests use builder patterns (`SimpleBuilder`, `ForkBuilder`) for creating test DAOs
- Pre-defined test actors: `alice`, `bob`, `carol`, `david` from `TestBase`
- YAML-driven test definitions converted to Solidity with bulloak
- Unit tests: `make test` (fast, local)
- Fork tests: `make test-fork` (integration with live Aragon contracts)

## Project Structure

### Specifications (Planning Phase)

- `docs/address-registry-spec.md` - Username mapping system
- `docs/payments-plugin-spec.md` - Streaming + scheduled payments
- `docs/dao-factory-spec.md` - Single-transaction DAO creation
- `docs/llamapay-integration-spec.md` - LlamaPay streaming integration
- `docs/testing-strategy.md` - Comprehensive testing approach

### Implementation Contracts (To Build)

- `src/AddressRegistry.sol` - Standalone username registry
- `src/PaymentsPlugin.sol` - Main plugin (use `MyUpgradeablePlugin.sol` as guide)
- `src/setup/PaymentsPluginSetup.sol` - Plugin setup (use `MyPluginSetup.sol` as guide)
- `src/factory/PayNestDAOFactory.sol` - DAO creation factory

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
- Follow the existing boilerplate patterns in the codebase

## Key Implementation Notes

### Contract Development

- Keep boilerplate contracts (`MyUpgradeablePlugin.sol`, `MyPluginSetup.sol`) as references
- Follow Aragon permission system patterns exactly
- Use specifications in `docs/` folder for requirements and invariants
- Implement contracts to match specification behavior, not implementation details

### Testing Approach

- Follow testing strategy in `docs/testing-strategy.md`
- Use existing test builders as patterns
- Write invariant tests for critical security properties
- Test against real Aragon contracts using fork tests

## Git Workflow

### Commit Messages
- Use conventional commits format: `type(scope): description`
- Types: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`
- Examples:
  - `feat(plugin): add stream creation functionality`
  - `docs(specs): update payments plugin specification`
  - `test(registry): add username validation tests`
  - `fix(factory): handle DAO creation failures properly`
