# Address Change Coordination Solution Plan

## Problem Summary

When users update their address in the AddressRegistry (e.g., due to wallet compromise), existing LlamaPay streams become orphaned because PayNest tracks streams by username while LlamaPay tracks by specific addresses. This creates an inconsistent state where stream management operations fail.

**Note: Scheduled payments are NOT affected** - they automatically resolve usernames to current addresses at payment time.

## Solution Approach: User-Driven Stream Migration

### Overview

Users migrate their own streams after changing addresses. This approach is:
- **Scalable**: No O(N) callbacks to multiple DAOs
- **User-controlled**: Users decide when and which streams to migrate
- **Simple**: No complex coordination between registry and plugins
- **Gas-efficient**: One stream migration at a time

### Phase 1: Enhanced AddressRegistry

#### Registry Improvements
- **Address History**: Store both current and previous addresses for migration
- **Simple Updates**: Address changes remain simple, no callbacks

#### Implementation Details
```solidity
contract AddressRegistry {
    struct AddressHistory {
        address currentAddress;
        address previousAddress;  // For migration support
        uint256 lastChangeTime;
    }
    
    mapping(string => AddressHistory) userAddresses;
    
    function updateUserAddress(string memory username, address newAddress) external {
        if (msg.sender != userAddresses[username].currentAddress) {
            revert UnauthorizedAddressUpdate();
        }
        
        userAddresses[username] = AddressHistory({
            currentAddress: newAddress,
            previousAddress: userAddresses[username].currentAddress,
            lastChangeTime: block.timestamp
        });
        
        emit AddressUpdated(username, newAddress, userAddresses[username].previousAddress);
    }
    
    function getAddressHistory(string memory username) external view returns (AddressHistory memory) {
        return userAddresses[username];
    }
}
```

### Phase 2: User Stream Migration

#### PaymentsPlugin Enhancements
- **Self-Migration**: Users can migrate their own streams
- **Optional Process**: Migration is optional, users control timing
- **Frontend Support**: UI can detect which streams need migration

#### Implementation Details
```solidity
contract PaymentsPlugin {
    error UnauthorizedMigration();
    error StreamNotFound();
    error NoMigrationNeeded();
    
    /// @notice Migrate user's stream to their current address
    /// @param username The username to migrate stream for
    function migrateStream(string calldata username) external {
        // Only current address holder can migrate
        address currentAddress = registry.getUserAddress(username);
        if (msg.sender != currentAddress) revert UnauthorizedMigration();
        
        // Get address history
        IRegistry.AddressHistory memory history = registry.getAddressHistory(username);
        Stream storage stream = streams[username];
        
        if (!stream.active) revert StreamNotFound();
        
        // Check if migration is needed (stream tied to old address)
        if (stream.recipient == currentAddress) revert NoMigrationNeeded();
        
        // Migrate stream from old to new address
        _migrateStreamToNewAddress(username, history.previousAddress, currentAddress);
        
        emit StreamMigrated(username, history.previousAddress, currentAddress);
    }
    
    function _migrateStreamToNewAddress(
        string memory username,
        address oldAddress, 
        address newAddress
    ) internal {
        Stream storage stream = streams[username];
        
        // Cancel old LlamaPay stream (returns funds to DAO)
        _cancelLlamaPayStream(stream.llamaPayContract, oldAddress, stream.amountPerSec);
        
        // Create new LlamaPay stream for new address with same parameters
        _createLlamaPayStream(stream.llamaPayContract, newAddress, stream.amountPerSec, username);
        
        // Update stream record
        stream.recipient = newAddress;
    }
    
    event StreamMigrated(string indexed username, address indexed oldAddress, address indexed newAddress);
}
```

## User Workflow

### 1. Address Change
```solidity
// User updates their address (simple, no callbacks)
registry.updateUserAddress("alice", newWalletAddress);
```

### 2. Stream Migration (Optional)
```solidity
// Alice migrates her streams in each DAO she's part of
daoPlugin1.migrateStream("alice");
daoPlugin2.migrateStream("alice"); 
// ... for each DAO
```

### 3. Frontend Integration
- UI detects address changes via events
- Shows user which DAOs have streams that need migration
- Provides batch migration via smart account/multicall
- Users can migrate at their own pace

## Benefits

1. **Scalable**: No gas limit issues with multiple DAOs
2. **User Control**: Users decide when and which streams to migrate
3. **Simple Registry**: No complex coordination callbacks
4. **Optional**: Users can leave some streams on old addresses if desired
5. **Frontend Friendly**: Easy to detect and batch migrations
6. **Scheduled Payments Work**: No migration needed for schedules

## Implementation Steps

### Step 1: Registry Enhancement
- [ ] Add AddressHistory struct to track current and previous addresses
- [ ] Update updateUserAddress to store previous address
- [ ] Add getAddressHistory function
- [ ] Update events to include previous address

### Step 2: PaymentsPlugin Migration Function
- [ ] Add migrateStream function with proper authorization
- [ ] Implement _migrateStreamToNewAddress internal function
- [ ] Add custom errors (UnauthorizedMigration, StreamNotFound, NoMigrationNeeded)
- [ ] Add StreamMigrated event

### Step 3: Testing and Integration
- [ ] Unit tests for address history tracking
- [ ] Unit tests for stream migration functionality
- [ ] Fork tests with real LlamaPay integration
- [ ] End-to-end migration workflow tests
- [ ] Gas cost analysis for migration operations

### Step 4: Frontend Integration Support
- [ ] Update contracts to emit events with previous addresses
- [ ] Ensure events provide enough data for UI to detect needed migrations
- [ ] Document event structure for frontend developers

## Detailed Function Specifications

### AddressRegistry.sol Enhancements

```solidity
// Custom errors
error UnauthorizedAddressUpdate();

// Enhanced address structure
struct AddressHistory {
    address currentAddress;
    address previousAddress;
    uint256 lastChangeTime;
}

// Updated storage
mapping(string => AddressHistory) private userAddresses;

// Enhanced address update
function updateUserAddress(string memory username, address newAddress) external {
    if (msg.sender != userAddresses[username].currentAddress) {
        revert UnauthorizedAddressUpdate();
    }
    if (newAddress == address(0)) revert InvalidAddress();
    
    address previousAddress = userAddresses[username].currentAddress;
    
    userAddresses[username] = AddressHistory({
        currentAddress: newAddress,
        previousAddress: previousAddress,
        lastChangeTime: block.timestamp
    });
    
    emit AddressUpdated(username, newAddress, previousAddress);
}

// New view function
function getAddressHistory(string memory username) external view returns (AddressHistory memory) {
    return userAddresses[username];
}

// Updated getUserAddress for compatibility
function getUserAddress(string memory username) external view returns (address) {
    return userAddresses[username].currentAddress;
}
```

### PaymentsPlugin.sol Enhancements

```solidity
// Import registry interface
interface IRegistry {
    struct AddressHistory {
        address currentAddress;
        address previousAddress;
        uint256 lastChangeTime;
    }
    
    function getAddressHistory(string memory username) external view returns (AddressHistory memory);
}

// Custom errors
error UnauthorizedMigration();
error StreamNotFound();
error NoMigrationNeeded();

// Migration function
function migrateStream(string calldata username) external {
    address currentAddress = registry.getUserAddress(username);
    if (msg.sender != currentAddress) revert UnauthorizedMigration();
    
    IRegistry.AddressHistory memory history = IRegistry(address(registry)).getAddressHistory(username);
    Stream storage stream = streams[username];
    
    if (!stream.active) revert StreamNotFound();
    if (stream.recipient == currentAddress) revert NoMigrationNeeded();
    
    _migrateStreamToNewAddress(username, history.previousAddress, currentAddress);
    
    emit StreamMigrated(username, history.previousAddress, currentAddress);
}

// Internal migration logic
function _migrateStreamToNewAddress(
    string memory username,
    address oldAddress, 
    address newAddress
) internal {
    Stream storage stream = streams[username];
    
    // Cancel old LlamaPay stream (returns funds to DAO)
    _cancelLlamaPayStream(stream.llamaPayContract, oldAddress, stream.amountPerSec);
    
    // Create new LlamaPay stream for new address with same parameters
    _createLlamaPayStream(stream.llamaPayContract, newAddress, stream.amountPerSec, username);
    
    // Update stream record
    stream.recipient = newAddress;
}

// New event
event StreamMigrated(string indexed username, address indexed oldAddress, address indexed newAddress);
```

## Edge Cases and Considerations

### Technical Considerations
- **Multiple Migrations**: Users can migrate multiple times if needed
- **Partial Migration**: Users can choose which streams to migrate
- **Failed Migrations**: Proper error handling if stream recreation fails
- **Gas Costs**: Users pay for their own migration gas

### User Experience
- **Discovery**: Frontend helps users find streams that need migration
- **Batching**: Smart accounts can batch multiple migrations
- **Education**: Clear documentation on when migration is needed
- **Optional**: Users control their own migration timeline

### Security
- **Authorization**: Only current address holder can migrate
- **Stream Validation**: Proper checks before migration
- **Error Handling**: Clear error messages for failed migrations

## Testing Strategy

### Unit Tests
- AddressHistory storage and retrieval
- Migration authorization checks
- Error conditions and edge cases
- Event emission verification

### Integration Tests
- Complete address change and migration workflow
- Multiple DAO migration scenarios
- Failed migration recovery
- Gas optimization tests

### Fork Tests
- Real LlamaPay integration testing
- Stream recreation on actual Base mainnet
- Multiple user migration scenarios
- Performance under realistic conditions

This solution provides a robust, user-controlled approach to stream migration that scales well and puts users in control of their own payment streams while keeping the system architecture simple and maintainable.