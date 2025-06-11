# PayNest System Invariants Specification

> **Purpose**: This document defines comprehensive invariants for property-based testing of the PayNest system. These properties should hold true regardless of the sequence of operations performed.

## Overview

This specification defines **77 critical invariants** across the PayNest ecosystem that must be validated through invariant testing. The invariants are organized by priority and component for systematic implementation.

## Critical Invariants (Priority 1)

These invariants are fundamental to system correctness and security:

### AddressRegistry Bidirectional Mapping (AR1-AR6)

**AR1: Username-to-Address Consistency**
```solidity
// If username maps to an address, that address must map back to the username
userAddresses[username].currentAddress != address(0) ⟺ 
    bytes(addressToUsername[userAddresses[username].currentAddress]).length != 0
```

**AR2: Address-to-Username Consistency**
```solidity
// If address has a username, that username must map back to the address
addressToUsername[user].length > 0 ⟺ 
    userAddresses[addressToUsername[user]].currentAddress == user
```

**AR3: Bijective Mapping**
```solidity
// One-to-one mapping: different usernames cannot map to same address
∀u1, u2: u1 ≠ u2 ⟹ 
    userAddresses[u1].currentAddress ≠ userAddresses[u2].currentAddress
```

**AR4: Zero Address Protection**
```solidity
// Zero address never has a username
addressToUsername[address(0)].length == 0
```

**AR5: Address History Integrity**
```solidity
// Active usernames must have valid timestamps
userAddresses[username].currentAddress != address(0) ⟹ 
    userAddresses[username].lastChangeTime > 0 ∧ 
    userAddresses[username].lastChangeTime <= block.timestamp
```

**AR6: No Self-Transitions**
```solidity
// Previous address differs from current (except initial claim)
userAddresses[username].currentAddress == userAddresses[username].previousAddress ⟹ 
    userAddresses[username].previousAddress == address(0)
```

### PaymentsPlugin Financial Integrity (PP1-PP8)

**PP1: Active Stream Validity**
```solidity
// Active streams have valid tokens and non-zero amounts
streams[username].active == true ⟹ 
    streams[username].token != address(0) ∧ 
    streams[username].amount > 0 ∧
    streams[username].endDate > block.timestamp
```

**PP2: Stream-Recipient Consistency**
```solidity
// Active streams have recipients, inactive streams don't
streams[username].active == true ⟺ streamRecipients[username] != address(0)
```

**PP3: Stream Amount Bounds**
```solidity
// Stream amounts fit in LlamaPay's uint216
streams[username].amount <= type(uint216).max
```

**PP4: Schedule Validity**
```solidity
// Active schedules have valid parameters
schedules[username].active == true ⟹ 
    schedules[username].token != address(0) ∧ 
    schedules[username].amount > 0 ∧
    schedules[username].firstPaymentDate > 0
```

**PP5: Temporal Consistency**
```solidity
// Payout timestamps are logical
streams[username].lastPayout <= block.timestamp ∧
schedules[username].firstPaymentDate <= schedules[username].nextPayout
```

**PP6: LlamaPay Contract Caching**
```solidity
// Cached LlamaPay contracts are valid
tokenToLlamaPay[token] != address(0) ⟹ 
    ILlamaPayFactory(llamaPayFactory).getLlamaPayContractByToken(token).deployed == true
```

**PP7: Username Dependency**
```solidity
// Active payments require valid usernames
(streams[username].active ∨ schedules[username].active) ⟹ 
    registry.getUserAddress(username) != address(0)
```

**PP8: Migration Consistency**
```solidity
// After migration, stream points to current username address
// This invariant is temporarily relaxed during migration but must hold eventually
streamRecipients[username] != registry.getUserAddress(username) ⟹ 
    migration_is_pending OR streams[username].active == false
```

## High Priority Invariants (Priority 2)

### Username Validation (AR7-AR12)

**AR7: Username Format Enforcement**
```solidity
// All claimed usernames meet format requirements
isUsernameAvailable(username) == false ⟹ 
    bytes(username).length > 0 ∧ 
    bytes(username).length <= 32 ∧
    _isLetter(bytes(username)[0])
```

**AR8: Character Validation**
```solidity
// All characters in claimed usernames are valid
∀username where !isUsernameAvailable(username):
    ∀i ∈ [0, bytes(username).length): 
        _isValidUsernameChar(bytes(username)[i])
```

### Financial Bounds (PP9-PP15)

**PP9: Arithmetic Safety**
```solidity
// Schedule payouts don't overflow
schedule.amount * periodsToPayFor >= schedule.amount
```

**PP10: Decimal Precision Accuracy**
```solidity
// Amount per second calculation is approximately correct
_calculateAmountPerSec(totalAmount, duration, token) * duration / 
    (10 ** (20 - IERC20WithDecimals(token).decimals())) ≈ totalAmount
```

**PP11: DAO Balance Sufficiency**
```solidity
// DAO has sufficient balance for active obligations
∀token: sum(active_stream_amounts[token]) + sum(pending_schedule_amounts[token]) <= 
    IERC20(token).balanceOf(address(dao)) + llamaPayBalance[token]
```

**PP12: Schedule Timing Logic**
```solidity
// One-time schedules deactivate after payout
schedules[username].isOneTime == true ∧ 
schedules[username].nextPayout < block.timestamp ⟹ 
    schedules[username].active == false
```

**PP13: Interval Alignment**
```solidity
// Recurring schedule timing is aligned to intervals
schedules[username].isOneTime == false ⟹ 
    (schedules[username].nextPayout - schedules[username].firstPaymentDate) % 
    _getIntervalSeconds(schedules[username].interval) == 0
```

### Permission Security (PS1-PS5)

**PS1: Manager Permission Requirement**
```solidity
// All payment modifications require manager permission
(createStream_success ∨ cancelStream_success ∨ editStream_success ∨ 
 createSchedule_success ∨ cancelSchedule_success ∨ editSchedule_success) ⟹ 
    dao().hasPermission(caller, MANAGER_PERMISSION_ID)
```

**PS2: Execute Permission for Plugin**
```solidity
// Plugin can execute DAO actions
dao().hasPermission(address(this), EXECUTE_PERMISSION_ID) == true
```

**PS3: Migration Authorization**
```solidity
// Only current username holder can migrate
migrateStream_success ⟹ 
    msg.sender == registry.getUserAddress(username)
```

## Medium Priority Invariants (Priority 3)

### State Atomicity (SA1-SA8)

**SA1: Username Claim Atomicity**
```solidity
// Username claiming updates both mappings atomically
claimUsername_success ⟹ 
    (getUserAddress(username) == msg.sender ∧ 
     addressToUsername[msg.sender] == username) ∨ 
    transaction_reverted
```

**SA2: Address Update Atomicity**
```solidity
// Address updates clear old mappings and set new ones atomically
updateUserAddress_success ⟹ 
    (addressToUsername[oldAddress] == "" ∧ 
     addressToUsername[newAddress] == username ∧
     getUserAddress(username) == newAddress) ∨ 
    transaction_reverted
```

**SA3: Stream Creation Atomicity**
```solidity
// Stream creation sets all state consistently
createStream_success ⟹ 
    (streams[username].active == true ∧ 
     streamRecipients[username] != address(0) ∧
     tokenToLlamaPay[token] != address(0)) ∨ 
    transaction_reverted
```

**SA4: Stream Cancellation Cleanup**
```solidity
// Stream cancellation clears all related state
cancelStream_success ⟹ 
    streams[username].active == false ∧ 
    streamRecipients[username] == address(0)
```

### LlamaPay Integration (LI1-LI6)

**LI1: Stream Synchronization**
```solidity
// Active PayNest streams have corresponding LlamaPay streams
streams[username].active == true ⟹ 
    ILlamaPay(tokenToLlamaPay[streams[username].token])
        .withdrawable(dao(), streamRecipients[username], streams[username].amount)
        .withdrawableAmount >= 0
```

**LI2: Token Approval Adequacy**
```solidity
// DAO has approved LlamaPay for stream amounts
streams[username].active == true ⟹ 
    IERC20(streams[username].token)
        .allowance(dao(), tokenToLlamaPay[streams[username].token]) >= 
    streams[username].amount * (streams[username].endDate - block.timestamp)
```

### Cross-Contract Consistency (CC1-CC4)

**CC1: Factory Registry Sharing**
```solidity
// All factory-created DAOs share the same registry
∀dao created by PayNestDAOFactory: 
    PaymentsPlugin(daoInfo[dao].paymentsPlugin).registry() == addressRegistry
```

**CC2: DAO Metadata Validity**
```solidity
// DAO metadata is consistent
∀dao in daoInfo: 
    daoInfo[dao].createdAt <= block.timestamp ∧ 
    daoInfo[dao].admin != address(0)
```

## Low Priority Invariants (Priority 4)

### Performance and Gas Limits (PG1-PG5)

**PG1: Bounded Computation**
```solidity
// Schedule payouts have reasonable period limits
requestSchedulePayout_success ⟹ 
    periodsToPayFor <= MAX_REASONABLE_PERIODS
```

**PG2: Username Length Bounds**
```solidity
// Username operations complete in bounded time
claimUsername_gas_used < MAX_USERNAME_CLAIM_GAS
```

### Edge Cases and Recovery (EC1-EC8)

**EC1: Orphaned Stream Recovery**
```solidity
// Orphaned streams can be migrated
streams[username].active == true ∧ 
streamRecipients[username] != registry.getUserAddress(username) ⟹ 
    migrateStream(username) can be called successfully
```

**EC2: Zero State Consistency**
```solidity
// Inactive entities have zero state
streams[username].active == false ⟹ 
    streams[username].token == address(0) ∧ 
    streams[username].amount == 0 ∧
    streams[username].endDate == 0
```

**EC3: Initialization Completeness**
```solidity
// Plugin is properly initialized
initialized == true ⟹ 
    registry != IRegistry(address(0)) ∧ 
    llamaPayFactory != ILlamaPayFactory(address(0)) ∧
    dao() != IDAO(address(0))
```

## Implementation Guidelines

### Testing Framework Setup

```solidity
contract PayNestInvariants is Test {
    // Target contracts for invariant testing
    AddressRegistry public registry;
    PaymentsPlugin public plugin;
    PayNestDAOFactory public factory;
    
    // Mock external dependencies
    MockLlamaPay public llamaPay;
    MockERC20 public token;
    MockDAO public dao;
    
    // Invariant testing actors
    address[] public actors;
    
    function setUp() public {
        // Initialize all contracts
        // Set up test actors with different permissions
        // Configure reasonable bounds for fuzzing
    }
}
```

### Critical Invariant Tests

**Priority 1: Must be implemented first**
- AR1-AR6: AddressRegistry bidirectional mapping
- PP1-PP8: PaymentsPlugin financial integrity

**Priority 2: High value, moderate complexity**
- AR7-AR12: Username validation
- PP9-PP15: Financial bounds and calculations
- PS1-PS5: Permission security

**Priority 3: Important for edge cases**
- SA1-SA8: State atomicity
- LI1-LI6: LlamaPay integration
- CC1-CC4: Cross-contract consistency

**Priority 4: Nice to have, complex to test**
- PG1-PG5: Performance bounds
- EC1-EC8: Edge cases and recovery

### Testing Strategy

1. **Unit Invariant Tests**: Test individual contract invariants in isolation
2. **Integration Invariant Tests**: Test cross-contract invariants with real integrations
3. **Fork Invariant Tests**: Test LlamaPay integration invariants against mainnet
4. **Stateful Fuzzing**: Use sequence-based fuzzing to validate invariants across operation sequences

### Metrics and Coverage

- **Target**: 100% of Priority 1 invariants tested
- **Goal**: 90% of Priority 2 invariants tested
- **Stretch**: 75% of Priority 3 invariants tested

### Implementation Notes

- Use Foundry's `invariant` testing framework
- Implement custom `targetSelector` functions for each priority level
- Create helper functions for complex invariant checks
- Use ghost variables to track aggregate state for financial invariants
- Implement proper actor management for permission-based invariants

This specification provides a roadmap for implementing comprehensive invariant testing that will validate the correctness and security of the PayNest system under all possible operation sequences.