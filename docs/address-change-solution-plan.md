# Address Change Solution Plan

## Overview

This document outlines the implementation plan to solve the orphaned stream problem when users update their addresses in the AddressRegistry.

## Solution Architecture

### Phase 1: Enhanced AddressRegistry

**Add stream tracking and coordination capabilities**

```solidity
contract AddressRegistry {
    // Track which contracts have active streams for each username
    mapping(bytes32 => address[]) public activeStreamContracts;
    
    // Events for coordination
    event AddressChangeRequested(bytes32 indexed usernameHash, address oldAddress, address newAddress);
    event AddressChangeCompleted(bytes32 indexed usernameHash, address oldAddress, address newAddress);
    
    // New functions
    function requestAddressChange(string memory username, address newAddress) external;
    function completeAddressChange(string memory username) external;
    function registerStreamContract(string memory username, address streamContract) external;
    function unregisterStreamContract(string memory username, address streamContract) external;
    function getActiveStreamContracts(string memory username) external view returns (address[]);
}
```

### Phase 2: Enhanced PaymentsPlugin

**Add orphaned stream management and migration capabilities**

```solidity
contract PaymentsPlugin {
    // Track original addresses for streams
    mapping(bytes32 => address) public streamOriginalAddresses;
    
    // Events for tracking
    event StreamOrphaned(bytes32 indexed usernameHash, address originalAddress, address newAddress);
    event StreamMigrated(bytes32 indexed usernameHash, address fromAddress, address toAddress);
    
    // New admin functions
    function cleanupOrphanedStream(string memory username) external auth(MANAGER_PERMISSION_ID);
    function migrateStream(string memory username, uint256 newAmount, uint40 newEndDate) external auth(MANAGER_PERMISSION_ID);
    function forceRemoveStream(string memory username) external auth(MANAGER_PERMISSION_ID);
    
    // Enhanced stream creation
    function createStream(string memory username, uint256 amount, address token, uint40 endDate) external {
        // Register with AddressRegistry
        registry.registerStreamContract(username, address(this));
        // ... existing logic
    }
}
```

### Phase 3: Coordinated Address Change Workflow

**Implement clean address change process**

1. **User initiates address change**:
   ```solidity
   registry.requestAddressChange("alice", newAddress);
   ```

2. **Registry identifies affected contracts**:
   ```solidity
   address[] memory contracts = registry.getActiveStreamContracts("alice");
   ```

3. **Automatic cleanup notification**:
   ```solidity
   for (uint i = 0; i < contracts.length; i++) {
       IStreamManager(contracts[i]).handleAddressChange("alice", oldAddr, newAddr);
   }
   ```

4. **PaymentsPlugin handles transition**:
   ```solidity
   function handleAddressChange(string memory username, address oldAddr, address newAddr) external {
       require(msg.sender == address(registry), "Only registry");
       _markStreamOrphaned(username, oldAddr, newAddr);
   }
   ```

5. **Admin recreates streams manually**:
   ```solidity
   paymentsPlugin.cleanupOrphanedStream("alice");
   paymentsPlugin.createStream("alice", newAmount, token, endDate);
   ```

## Implementation Steps

### Step 1: Registry Enhancement
- [ ] Add stream contract tracking
- [ ] Add address change request/completion pattern
- [ ] Add coordination events and hooks
- [ ] Add security controls (only username owner can change)

### Step 2: PaymentsPlugin Enhancement  
- [ ] Add orphaned stream detection
- [ ] Add cleanup functions for admins
- [ ] Add migration helper functions
- [ ] Add original address tracking

### Step 3: Integration Testing
- [ ] Test coordinated address changes
- [ ] Test admin cleanup workflows
- [ ] Test security boundaries
- [ ] Test gas costs

### Step 4: Documentation Updates
- [ ] Update usage guide with new workflows
- [ ] Add admin operational procedures
- [ ] Update security considerations
- [ ] Add migration examples

## Detailed Function Specifications

### AddressRegistry.sol Additions

```solidity
/**
 * @notice Requests an address change for a username
 * @dev Initiates coordination with active stream contracts
 * @param username The username to update
 * @param newAddress The new address to map to
 */
function requestAddressChange(string memory username, address newAddress) external {
    bytes32 usernameHash = keccak256(abi.encodePacked(username));
    require(usernames[usernameHash] == msg.sender, "Not username owner");
    require(newAddress != address(0), "Invalid new address");
    
    address oldAddress = usernames[usernameHash];
    
    // Emit coordination event
    emit AddressChangeRequested(usernameHash, oldAddress, newAddress);
    
    // Notify active stream contracts
    address[] memory contracts = activeStreamContracts[usernameHash];
    for (uint256 i = 0; i < contracts.length; i++) {
        if (contracts[i] != address(0)) {
            try IStreamManager(contracts[i]).handleAddressChange(username, oldAddress, newAddress) {
                // Success
            } catch {
                // Log but don't fail - admin can handle manually
                emit StreamNotificationFailed(usernameHash, contracts[i]);
            }
        }
    }
    
    // Update the mapping
    usernames[usernameHash] = newAddress;
    reverseUsernames[newAddress] = usernameHash;
    delete reverseUsernames[oldAddress];
    
    emit UserAddressUpdated(usernameHash, newAddress);
    emit AddressChangeCompleted(usernameHash, oldAddress, newAddress);
}

/**
 * @notice Registers a stream contract for a username
 * @param username The username with active streams
 * @param streamContract The contract managing streams
 */
function registerStreamContract(string memory username, address streamContract) external {
    bytes32 usernameHash = keccak256(abi.encodePacked(username));
    // Only allow registered PayNest plugins to register
    // Add security check here
    
    activeStreamContracts[usernameHash].push(streamContract);
    emit StreamContractRegistered(usernameHash, streamContract);
}
```

### PaymentsPlugin.sol Additions

```solidity
/**
 * @notice Handles address change notification from registry
 * @param username The username being changed
 * @param oldAddress Previous address
 * @param newAddress New address
 */
function handleAddressChange(string memory username, address oldAddress, address newAddress) external {
    require(msg.sender == address(registry), "Only registry can notify");
    
    bytes32 usernameHash = keccak256(abi.encodePacked(username));
    Stream storage stream = streams[usernameHash];
    
    if (stream.active) {
        // Mark stream as orphaned
        stream.active = false;
        streamOriginalAddresses[usernameHash] = oldAddress;
        
        emit StreamOrphaned(usernameHash, oldAddress, newAddress);
    }
}

/**
 * @notice Admin function to clean up orphaned stream
 * @param username Username with orphaned stream
 */
function cleanupOrphanedStream(string memory username) external auth(MANAGER_PERMISSION_ID) {
    bytes32 usernameHash = keccak256(abi.encodePacked(username));
    
    require(!streams[usernameHash].active, "Stream not orphaned");
    require(streamOriginalAddresses[usernameHash] != address(0), "No orphaned stream");
    
    // Clear the stream data
    delete streams[usernameHash];
    delete streamOriginalAddresses[usernameHash];
    
    // Unregister from registry
    registry.unregisterStreamContract(username, address(this));
    
    emit StreamCleaned(usernameHash);
}

/**
 * @notice Admin function to migrate orphaned stream to new address
 * @param username Username to migrate
 * @param newAmount New stream amount (allows adjustments)
 * @param newEndDate New end date
 */
function migrateStream(string memory username, uint256 newAmount, uint40 newEndDate) 
    external 
    auth(MANAGER_PERMISSION_ID) 
{
    // Clean up old stream
    cleanupOrphanedStream(username);
    
    // Create new stream with current address
    createStream(username, newAmount, streams[usernameHash].token, newEndDate);
    
    bytes32 usernameHash = keccak256(abi.encodePacked(username));
    emit StreamMigrated(usernameHash, streamOriginalAddresses[usernameHash], registry.getUserAddress(username));
}
```

## Security Considerations

1. **Authorization**: Only username owners can initiate address changes
2. **Admin controls**: Only MANAGER_PERMISSION holders can clean up streams
3. **Coordination failures**: System gracefully handles notification failures
4. **Reentrancy**: Proper checks for external calls during coordination
5. **Gas limits**: Batch operations to avoid gas limit issues

## User Experience Improvements

1. **Clear documentation**: Step-by-step guides for address changes
2. **Admin tools**: Dashboard for managing orphaned streams
3. **Event monitoring**: Frontend can track coordination events
4. **Recovery procedures**: Clear paths for edge case resolution

## Testing Strategy

1. **Unit tests**: Each new function individually
2. **Integration tests**: Full address change workflows
3. **Fork tests**: Real contract coordination
4. **Gas analysis**: Cost of address change operations
5. **Security tests**: Permission boundaries and attack vectors

## Rollout Plan

1. **Development**: Implement and test new functionality
2. **Internal review**: Security and design review
3. **Testnet deployment**: Deploy to Base Sepolia
4. **Community testing**: Get feedback from test users
5. **Mainnet deployment**: Deploy coordinated upgrade

---

**Next Actions**:
1. Start with AddressRegistry enhancement
2. Add PaymentsPlugin coordination functions
3. Create comprehensive test suite
4. Update documentation and guides

This solution provides a robust, secure, and user-friendly way to handle address changes while maintaining system integrity.