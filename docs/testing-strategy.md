# PayNest Testing Strategy

## Overview

This document outlines the comprehensive testing strategy for the PayNest ecosystem, covering unit tests, integration tests, fork tests, invariant testing, and real DAO testing. The strategy leverages the existing Aragon OSx testing infrastructure while adding specific testing patterns for our payments functionality.

## Testing Architecture

### Test Types

1. **Unit Tests** - Fast, isolated component testing
2. **Integration Tests** - Cross-component interaction testing  
3. **Fork Tests** - Testing against live Aragon contracts
4. **Invariant Tests** - Property-based testing of contract invariants
5. **Gas Benchmarking** - Performance and optimization testing
6. **Real DAO Tests** - End-to-end testing with deployed DAOs

### Test Environment Structure

```
test/
├── unit/                           # Unit tests (fast, local)
│   ├── AddressRegistry.t.sol      # Registry unit tests
│   ├── PaymentsPlugin.t.sol       # Plugin unit tests
│   └── PaymentsPluginSetup.t.sol  # Setup unit tests
├── integration/                    # Integration tests
│   ├── PaymentsWorkflow.t.sol     # End-to-end workflows
│   └── CrossContract.t.sol        # Cross-component tests
├── fork-tests/                     # Fork tests (live networks)
│   ├── PaymentsPluginFork.t.sol   # Real Aragon integration
│   └── LlamaPayIntegration.t.sol   # Real LlamaPay testing
├── invariant/                      # Invariant tests
│   ├── AddressRegistryInvariant.t.sol
│   ├── PaymentsPluginInvariant.t.sol
│   └── handlers/                   # Invariant test handlers
├── builders/                       # Test utility builders
│   ├── PaymentsBuilder.sol        # Unit test builder
│   ├── PaymentsForkBuilder.sol    # Fork test builder
│   └── RegistryBuilder.sol        # Registry test builder
├── lib/                           # Test base contracts
│   ├── PaymentsTestBase.sol       # Common test utilities
│   └── InvariantTestBase.sol      # Invariant test base
├── mocks/                         # Mock contracts
│   ├── MockLlamaPay.sol           # LlamaPay mock
│   └── MockRegistry.sol           # Registry mock
└── yaml/                          # Bulloak YAML definitions
    ├── AddressRegistry.t.yaml     # Registry test specs
    └── PaymentsPlugin.t.yaml      # Plugin test specs
```

## Testing Strategies by Component

### 1. AddressRegistry Testing

#### Unit Tests (`test/unit/AddressRegistry.t.sol`)
```solidity
contract AddressRegistryTest is PaymentsTestBase {
    AddressRegistry registry;
    
    function setUp() public {
        registry = new AddressRegistry();
    }
    
    // Username claiming tests
    function test_claimUsername_Success() public;
    function test_claimUsername_RevertIfEmpty() public;
    function test_claimUsername_RevertIfTaken() public;
    function test_claimUsername_RevertIfInvalidFormat() public;
    
    // Address updating tests  
    function test_updateAddress_Success() public;
    function test_updateAddress_RevertIfNotOwner() public;
    function test_updateAddress_RevertIfTargetHasUsername() public;
    
    // Resolution tests
    function test_getUserAddress_ValidUsername() public;
    function test_getUserAddress_InvalidUsername() public;
}
```

#### Invariant Tests (`test/invariant/AddressRegistryInvariant.t.sol`)
```solidity
contract AddressRegistryInvariantTest is InvariantTestBase {
    AddressRegistry registry;
    RegistryHandler handler;
    
    function setUp() public {
        registry = new AddressRegistry();
        handler = new RegistryHandler(registry);
        targetContract(address(handler));
    }
    
    // Critical invariants from our specs
    function invariant_bidirectionalConsistency() public {
        // If usernameToAddress[X] = A, then addressToUsername[A] = X
    }
    
    function invariant_uniqueness() public {
        // Each address has at most one username
    }
    
    function invariant_dataIntegrity() public {
        // No empty usernames or zero addresses
    }
}
```

### 2. PaymentsPlugin Testing

#### Unit Tests (`test/unit/PaymentsPlugin.t.sol`)
```solidity
contract PaymentsPluginTest is PaymentsTestBase {
    using PaymentsBuilder for PaymentsBuilder;
    
    DAO dao;
    PaymentsPlugin plugin;
    MockRegistry registry;
    MockLlamaPay llamaPay;
    
    function setUp() public {
        (dao, plugin, registry, llamaPay) = new PaymentsBuilder()
            .withMockRegistry()
            .withMockLlamaPay()
            .build();
    }
    
    // Stream management tests
    function test_createStream_Success() public;
    function test_createStream_RevertIfUsernameNotFound() public;
    function test_createStream_RevertIfNotManager() public;
    function test_createStream_WithLlamaPayIntegration() public;
    
    // Schedule management tests
    function test_createSchedule_Weekly() public;
    function test_createSchedule_Monthly() public;
    function test_createSchedule_OneTime() public;
    function test_requestSchedulePayout_EagerPayout() public;
    
    // Permission tests
    function test_onlyManagerCanCreatePayments() public;
    function test_anyoneCanRequestPayouts() public;
}
```

#### Integration Tests (`test/integration/PaymentsWorkflow.t.sol`)
```solidity
contract PaymentsWorkflowTest is PaymentsTestBase {
    // Test complete workflows with real components
    function test_fullStreamWorkflow() public {
        // 1. Deploy registry and claim username
        // 2. Install payments plugin on DAO
        // 3. Create stream with LlamaPay
        // 4. Request payouts
        // 5. Cancel stream
    }
    
    function test_fullScheduleWorkflow() public {
        // 1. Deploy registry and claim username
        // 2. Install payments plugin on DAO
        // 3. Create recurring schedule
        // 4. Request multiple payouts with eager logic
        // 5. Cancel schedule
    }
    
    function test_usernameAddressChange() public {
        // Test stream continues when username owner changes address
    }
}
```

### 3. Fork Testing (Real Network Integration)

#### Fork Test Base (`test/lib/PaymentsForkTestBase.sol`)
```solidity
contract PaymentsForkTestBase is ForkTestBase {
    // Real Aragon contracts from .env
    // Real LlamaPay contracts
    // Real deployed AddressRegistry
    
    function setUp() public virtual override {
        super.setUp();
        
        // Verify all required contracts are available
        if (address(llamaPayFactory) == address(0)) {
            revert("Please set LLAMAPAY_FACTORY_ADDRESS in .env");
        }
        if (address(addressRegistry) == address(0)) {
            revert("Please set ADDRESS_REGISTRY_ADDRESS in .env");
        }
    }
}
```

#### Fork Builder (`test/builders/PaymentsForkBuilder.sol`)
```solidity
contract PaymentsForkBuilder is PaymentsForkTestBase {
    // Build real DAO with payments plugin installed
    // Use real AddressRegistry
    // Use real LlamaPay factory
    
    function build() public returns (
        DAO dao,
        PaymentsPlugin plugin,
        PluginRepo repo,
        PaymentsPluginSetup setup
    ) {
        // Similar to existing ForkBuilder but for payments plugin
        // Creates real DAO with real plugin installation
    }
}
```

#### Fork Tests (`test/fork-tests/PaymentsPluginFork.t.sol`)
```solidity
contract PaymentsPluginForkTest is PaymentsForkTestBase {
    function test_realDAOIntegration() public {
        // Test against live Aragon contracts
        // Test with real LlamaPay contracts
        // Test with real tokens (USDC, WETH, etc.)
    }
    
    function test_realTokenStreaming() public {
        // Test streaming real tokens
        // Test decimal handling across different tokens
        // Test gas costs with real contracts
    }
}
```

### 4. Invariant Testing Strategy

#### Invariant Test Base (`test/lib/InvariantTestBase.sol`)
```solidity
abstract contract InvariantTestBase is Test {
    // Common invariant testing utilities
    // Helper functions for invariant validation
    // Fuzz testing configuration
}
```

#### Payment Plugin Invariant Tests (`test/invariant/PaymentsPluginInvariant.t.sol`)
```solidity
contract PaymentsPluginInvariantTest is InvariantTestBase {
    PaymentsPlugin plugin;
    PaymentsHandler handler;
    
    function setUp() public {
        // Setup plugin with handler
        handler = new PaymentsHandler(plugin, dao, registry);
        targetContract(address(handler));
    }
    
    // Fund security invariants
    function invariant_pluginNeverHoldsFunds() public {
        assertEq(address(plugin).balance, 0);
        // Check ERC20 balances are zero
    }
    
    // Stream state invariants
    function invariant_activeStreamsHaveValidEndDates() public {
        // All active streams must have endDate > block.timestamp
    }
    
    // Permission invariants
    function invariant_onlyManagerCanModifyPayments() public {
        // Verify permission integrity
    }
    
    // Username resolution invariants
    function invariant_allPaymentsHaveValidUsernames() public {
        // All usernames in payments must exist in registry
    }
}
```

#### Invariant Handlers (`test/invariant/handlers/PaymentsHandler.sol`)
```solidity
contract PaymentsHandler is Test {
    PaymentsPlugin plugin;
    DAO dao;
    AddressRegistry registry;
    
    // Fuzz actions that maintain system invariants
    function createStream(
        string memory username,
        uint256 amount,
        address token,
        uint40 endTime
    ) public {
        // Bounded inputs to maintain invariants
        amount = bound(amount, 1, 1e30);
        endTime = uint40(bound(endTime, block.timestamp + 1, block.timestamp + 365 days));
        
        // Ensure username exists
        if (registry.getUserAddress(username) == address(0)) {
            return; // Skip invalid usernames
        }
        
        vm.prank(manager);
        plugin.createStream(username, amount, token, endTime);
    }
    
    // More fuzz actions...
}
```

## Bulloak Integration

### YAML Test Definitions

#### Address Registry Tests (`test/yaml/AddressRegistry.t.yaml`)
```yaml
AddressRegistryTest:
  when claiming a username:
    when username is valid:
      it should store the mapping
      it should emit UsernameClaimed event
      it should prevent duplicate claims
    when username is invalid:
      it should revert with UsernameEmpty
      it should revert with UsernameTooLong
      it should revert with InvalidCharacterInUsername
  
  when updating address:
    when caller owns username:
      it should update the mapping
      it should emit UserAddressUpdated event
    when caller doesn't own username:
      it should revert with NotUsernameOwner
```

### Bulloak Workflow

```bash
# Convert YAML to Solidity test scaffolds
make sync-tests

# Check if tests are in sync with YAML
make check-tests

# Generate markdown documentation
make markdown-tests
```

## Testing Commands

### Makefile Integration

```makefile
# Unit tests (fast, local)
.PHONY: test-unit
test-unit:
	forge test --no-match-path "./test/fork-tests/*" --no-match-path "./test/invariant/*"

# Integration tests
.PHONY: test-integration  
test-integration:
	forge test --match-path "./test/integration/*"

# Fork tests (requires RPC_URL and contract addresses)
.PHONY: test-fork
test-fork:
	forge test --match-path "./test/fork-tests/*"

# Invariant tests
.PHONY: test-invariant
test-invariant:
	forge test --match-path "./test/invariant/*"

# Gas benchmarking
.PHONY: test-gas
test-gas:
	forge test --gas-report

# All tests
.PHONY: test-all
test-all: test-unit test-integration test-invariant test-fork
```

## Environment Configuration

### Required Environment Variables (.env)

```bash
# Network Configuration
RPC_URL="https://base-sepolia.g.alchemy.com/v2/..."
CHAIN_ID="84532"

# Aragon Contracts (from official deployments)
DAO_FACTORY_ADDRESS="0x..."
PLUGIN_REPO_FACTORY_ADDRESS="0x..."

# PayNest Contracts (deployed separately)
ADDRESS_REGISTRY_ADDRESS="0x..."
LLAMAPAY_FACTORY_ADDRESS="0x..."

# Test Configuration
PAYMENTS_PLUGIN_MANAGER="0x..."  # Test manager address
TEST_TOKENS="0x...,0x..."        # Test token addresses
```

## Testing Workflows

### Development Workflow

1. **Write YAML specs** → `test/yaml/`
2. **Generate Solidity scaffolds** → `make sync-tests`
3. **Implement test logic** → Fill in test bodies
4. **Run unit tests** → `make test-unit`
5. **Run integration tests** → `make test-integration`
6. **Run invariant tests** → `make test-invariant`
7. **Deploy to testnet** → Real DAO testing
8. **Run fork tests** → `make test-fork`

### CI/CD Workflow

```yaml
# GitHub Actions workflow
test:
  strategy:
    matrix:
      test-type: [unit, integration, invariant]
  steps:
    - name: Run ${{ matrix.test-type }} tests
      run: make test-${{ matrix.test-type }}
    
coverage:
  steps:
    - name: Generate coverage
      run: make test-coverage
    - name: Upload to Codecov
      uses: codecov/codecov-action@v3
```

## Real DAO Testing Strategy

### Testnet Deployment Testing

1. **Deploy AddressRegistry** → Standalone contract
2. **Deploy PaymentsPluginSetup** → Via deployment script
3. **Create test DAO** → Using `DeployDaoWithPlugins.s.sol`
4. **Install payments plugin** → Via DAO factory
5. **Test complete workflows** → Real token transfers

### Test DAO Configuration

```solidity
// test/integration/RealDAOTest.t.sol
contract RealDAOTest is Test {
    function test_deployAndUseRealDAO() public {
        // 1. Run deployment script
        // 2. Verify DAO is created with plugin
        // 3. Test real payments with test tokens
        // 4. Verify all invariants hold
    }
}
```

## Performance & Gas Testing

### Gas Benchmarking

```solidity
contract PaymentsGasTest is PaymentsTestBase {
    function test_gas_createStream() public {
        uint256 gasBefore = gasleft();
        plugin.createStream("alice", 1000e18, token, block.timestamp + 30 days);
        uint256 gasUsed = gasBefore - gasleft();
        
        // Assert gas usage is within expected bounds
        assertLt(gasUsed, 500_000); // Max 500k gas
    }
    
    function test_gas_requestPayout() public {
        // Benchmark payout gas costs
    }
}
```

## Security Testing

### Attack Vector Testing

```solidity
contract PaymentsSecurityTest is PaymentsTestBase {
    function test_cannotDrainDAO() public {
        // Attempt various attacks on DAO treasury
    }
    
    function test_cannotManipulateUsernames() public {
        // Test username manipulation attacks
    }
    
    function test_cannotBypassPermissions() public {
        // Test permission bypass attempts
    }
}
```

## Testing Best Practices

### Code Coverage Requirements

- **Unit Tests**: 100% line coverage target
- **Integration Tests**: All critical workflows covered
- **Invariant Tests**: All specified invariants tested
- **Fork Tests**: Real contract integration verified

### Test Organization Principles

1. **Isolation**: Each test is independent and deterministic
2. **Clarity**: Test names clearly describe what is being tested
3. **Completeness**: All edge cases and error conditions covered
4. **Performance**: Fast unit tests, slower integration tests
5. **Reliability**: Tests pass consistently across environments

### Invariant Testing Guidelines

1. **Define invariants clearly** in specifications
2. **Test invariants continuously** during fuzz testing
3. **Use meaningful fuzz inputs** that maintain system validity
4. **Document invariant violations** when they occur
5. **Fix code, not tests** when invariants fail

## Summary

The PayNest testing strategy provides:

- ✅ **Comprehensive coverage** across all test types
- ✅ **Real DAO integration** via fork testing
- ✅ **Invariant verification** for security properties
- ✅ **Performance monitoring** via gas benchmarking
- ✅ **Automated workflows** with Bulloak integration
- ✅ **CI/CD ready** test organization
- ✅ **Security focused** attack vector testing

This strategy ensures robust, secure, and well-tested contracts ready for production deployment in the Aragon ecosystem.