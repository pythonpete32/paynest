# Address Registry Specification

## Overview

The Address Registry is a simple, global contract that manages username-to-address mappings for the PayNest ecosystem. It implements the `IRegistry` interface and provides basic username claiming and address resolution functionality without complex features like username releasing or transferring.

## Architecture Overview

```
AddressRegistry.sol
├── Implements IRegistry interface
├── Manages bidirectional username ↔ address mappings
├── Provides username claiming functionality
└── Validates username format and uniqueness
```

## AddressRegistry Contract

### Base Architecture

```solidity
contract AddressRegistry is IRegistry {
    /// @notice Maps usernames to their owner addresses
    mapping(string => address) public usernameToAddress;
    
    /// @notice Maps addresses to their claimed usernames
    mapping(address => string) public addressToUsername;
}
```

### Core Functions

#### Username Claiming

```solidity
function claimUsername(string calldata username) external;
```

**Function Logic**:

- Validate username format (alphanumeric + underscore, 1-32 chars)
- Check username is not already claimed
- Check caller doesn't already have a username
- Store bidirectional mapping (username → address, address → username)
- Emit UsernameClaimed event

#### Address Updates (IRegistry Interface)

```solidity
function updateUserAddress(string calldata username, address userAddress) external;
```

**Function Logic**:

- Verify caller owns the username
- Validate new address is not zero and doesn't have a username
- Update username to point to new address
- Clear old address mapping and update new address mapping
- Emit UserAddressUpdated event

#### Address Resolution (IRegistry Interface)

```solidity
function getUserAddress(string calldata username) external view returns (address);
```

**Function Logic**:

- Simple mapping lookup from usernameToAddress
- Returns zero address if username doesn't exist
- No validation needed for view function

### View Functions

```solidity
function isUsernameAvailable(string calldata username) external view returns (bool);
function getUsernameByAddress(address userAddress) external view returns (string memory);
function hasUsername(address userAddress) external view returns (bool);
```

### Events

```solidity
event UsernameClaimed(string indexed username, address indexed claimor);
event UserAddressUpdated(string indexed username, address indexed newAddress);
```

### Custom Errors

```solidity
error UsernameAlreadyClaimed();
error AddressAlreadyHasUsername();
error NotUsernameOwner();
error UsernameEmpty();
error UsernameTooLong();
error InvalidAddress();
error UsernameCannotStartWithUnderscore();
error UsernameCannotStartWithNumber();
error InvalidCharacterInUsername(bytes1 char, uint256 position);
```

## Username Validation Rules

### Format Requirements

**Length**: 1-32 characters
**Characters**: a-z, A-Z, 0-9, underscore only
**Start Character**: Must start with a letter (a-z, A-Z)
**Restrictions**: Cannot start with underscore or number

### Validation Logic

- Check length is within bounds (1-32 characters)
- Validate first character is a letter
- Loop through each character and validate it's allowed
- Reject usernames starting with underscore or number
- Use custom errors for specific validation failures

## Security Model

### Access Control

- Username claiming is permissionless (anyone can claim)
- Address updates restricted to username owner only
- No admin controls or central authority
- No username releasing or transferring functionality

### Ownership Model

- Each address can claim exactly one username
- Each username belongs to exactly one address
- Bidirectional 1:1 mapping enforced
- Address updates maintain ownership constraints

### Input Validation

- Username format strictly enforced
- Address validation prevents zero address updates
- Duplicate prevention across all mappings
- Atomic updates ensure consistent state

## Integration Points

### PayNest Plugin Integration

- Payments plugins resolve usernames via getUserAddress()
- Consistent username resolution across all DAOs
- No dependency on specific DAO or plugin
- Standalone contract design

### Registry Interface Compliance

- Implements required IRegistry interface
- Maintains compatibility with existing payment contracts
- Event emission matches interface requirements
- Function signatures exactly match interface

### Cross-Chain Deployment

- Same contract deployed on multiple networks
- Deterministic CREATE2 deployment for consistent addresses
- Independent username spaces per network
- No cross-chain synchronization needed

## Testing Strategy

### Unit Tests

**Username Claiming**:
- Valid username formats and claiming
- Invalid format rejection (length, characters, start character)
- Duplicate username prevention
- Address already has username prevention

**Address Updates**:
- Owner can update address successfully
- Non-owner cannot update address
- Address validation (zero address, existing username)
- Bidirectional mapping consistency

**Username Resolution**:
- Existing username resolution
- Non-existing username returns zero address
- Address to username lookup accuracy

### Integration Tests

**Multi-User Scenarios**:
- Multiple users claiming different usernames
- Address changes and mapping updates
- Concurrent claiming scenarios
- Username availability checks

**PayNest Integration**:
- Payment creation with username resolution
- Address changes mid-payment scenarios
- Cross-DAO username consistency

### Security Tests

**Attack Scenarios**:
- Username squatting attempts
- Malicious address update attempts
- Input validation bypass attempts
- State consistency attacks

## Error Handling Strategy

### Validation Errors

- Custom errors for each validation failure type
- Specific error messages for debugging
- Gas-efficient error handling
- Clear error context for frontend integration

### State Protection

- Prevent partial state updates
- Atomic bidirectional mapping updates
- Consistent error handling across functions
- Input sanitization for all external calls

## Gas Optimization

### Storage Efficiency

- Minimal storage slots used
- Efficient string storage for usernames ≤ 31 bytes
- Optimized mapping structures
- No unnecessary storage operations

### Validation Efficiency

- Early validation failures for gas savings
- Efficient character validation loops
- Custom errors instead of require strings
- Minimal external calls

## Contract Invariants

**Critical invariants that must ALWAYS hold for testing and security:**

### Bidirectional Consistency

**Mapping Synchronization**:
- If usernameToAddress[username] = address, then addressToUsername[address] = username
- If addressToUsername[address] = username, then usernameToAddress[username] = address
- Mappings MUST be perfectly synchronized at all times
- No orphaned mappings allowed

### Uniqueness Constraints

**One-to-One Mapping**:
- Each address MUST have at most one username
- Each username MUST have exactly one address (if claimed)
- No duplicate username entries across addresses
- No duplicate address entries across usernames

### Data Integrity

**Valid Data Only**:
- Active usernames MUST never be empty strings
- Username mappings MUST never point to zero address
- Address mappings MUST never point to empty usernames
- All stored usernames MUST pass format validation

### Format Consistency

**Username Standards**:
- All usernames MUST be 1-32 characters in length
- All usernames MUST contain only alphanumeric characters and underscores
- All usernames MUST start with a letter (a-z, A-Z)
- No usernames starting with underscore or number

### State Consistency

**Atomic Updates**:
- All state changes MUST be atomic
- Failed operations MUST NOT leave partial state
- Bidirectional updates MUST succeed or fail together
- Contract state MUST be deterministic and reproducible

### Access Control Integrity

**Ownership Enforcement**:
- Only username owners can update their addresses
- No unauthorized username modifications allowed
- Username claiming MUST respect ownership rules
- Address updates MUST maintain uniqueness constraints

## Deployment Considerations

### Standalone Deployment

- Deploy as independent contract (not Aragon plugin)
- No dependencies on DAO or plugin infrastructure
- Simple contract with minimal complexity
- No admin controls or upgrade mechanisms needed

### Network Strategy

- Deploy once per network using CREATE2
- Deterministic addresses across Base and Base Sepolia
- Independent username registries per network
- Consistent interface across all deployments

### Monitoring Requirements

- Track username claiming patterns
- Monitor for potential abuse or squatting
- Gas usage optimization opportunities
- Integration health across PayNest ecosystem

## Summary

The Address Registry specification provides:

- ✅ **Simple Username System**: One username per address, no complexity
- ✅ **IRegistry Compliance**: Implements required interface for payments
- ✅ **Format Validation**: Strict alphanumeric username rules
- ✅ **Bidirectional Mapping**: Consistent username ↔ address resolution
- ✅ **Access Control**: Owner-only address updates
- ✅ **Gas Efficiency**: Custom errors and optimized validation
- ✅ **Cross-DAO Compatibility**: Shared registry for all PayNest DAOs
- ✅ **No Admin Controls**: Permissionless and decentralized

The design maintains simplicity by avoiding complex features like username releasing or transferring, while providing robust username-to-address resolution for the PayNest payment ecosystem.