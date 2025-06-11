# PayNest Contracts Usage Guide

## Overview

PayNest is an Aragon OSx plugin ecosystem that provides comprehensive payment infrastructure for DAOs. It combines streaming payments (via LlamaPay integration) and scheduled payments with a username-based addressing system, all deployable through a single factory contract.

## Architecture Components

### Core Contracts

#### 1. AddressRegistry
- **Purpose**: Global username → address mapping system
- **Deployment**: Standalone contract, shared across all PayNest DAOs
- **Key Features**:
  - Username claiming and validation
  - Address updates for wallet recovery scenarios
  - Username resolution for payment routing

#### 2. PaymentsPlugin
- **Purpose**: Main Aragon plugin handling all payment functionality
- **Deployment**: One instance per DAO (deployed via PayNestDAOFactory)
- **Key Features**:
  - Streaming payments via LlamaPay integration
  - Scheduled payments (one-time and recurring)
  - Username-based payment addressing
  - DAO treasury management

#### 3. PaymentsPluginSetup
- **Purpose**: Aragon plugin setup contract for installation/permissions
- **Deployment**: Implementation deployed once, used by plugin repository
- **Key Features**:
  - Plugin initialization and configuration
  - Permission management (MANAGER_PERMISSION, EXECUTE_PERMISSION)
  - Plugin upgrades and uninstallation

#### 4. PayNestDAOFactory
- **Purpose**: One-transaction DAO creation with pre-installed plugins
- **Deployment**: Deployed once per network
- **Key Features**:
  - Creates DAO with Admin + PayNest plugins
  - Automatic permission setup
  - Shared registry integration

## Contract Interactions

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ PayNest DAO     │    │ AddressRegistry  │    │ LlamaPay        │
│ Factory         │    │ (Shared)         │    │ Factory         │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         │ creates               │                       │
         ▼                       │                       │
┌─────────────────┐              │                       │
│ DAO Instance    │              │                       │
│ ┌─────────────┐ │              │                       │
│ │ Admin Plugin│ │              │                       │
│ └─────────────┘ │              │                       │
│ ┌─────────────┐ │              │                       │
│ │ PayNest     │ │──────────────┼───────────────────────┼─────────┐
│ │ Plugin      │ │              │                       │         │
│ └─────────────┘ │              │                       │         │
└─────────────────┘              │                       │         │
                                 │                       │         │
         ┌───────────────────────┼───────────────────────┘         │
         │                       │                                 │
         ▼                       ▼                                 ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ Username        │    │ Address          │    │ Stream          │
│ Resolution      │    │ Updates          │    │ Management      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Usage Workflows

### 1. DAO Creation and Setup

```solidity
// 0. Factory requires 5 parameters for deployment
PayNestDAOFactory factory = new PayNestDAOFactory(
    addressRegistry,     // Global username registry
    daoFactory,          // Aragon's DAO factory  
    adminPluginRepo,     // Admin plugin repository
    paymentsPluginRepo,  // Payments plugin repository
    llamaPayFactory      // LlamaPay factory address
);

// 1. Deploy PayNest DAO with factory
(address dao, address adminPlugin, address paymentsPlugin) = 
    factory.createPayNestDAO(adminAddress, "company-dao");

// 2. Fund DAO treasury
IERC20(usdc).transfer(dao, fundingAmount);

// 3. Employees claim usernames
registry.claimUsername("alice");
registry.claimUsername("bob");
```

### 2. Payment Creation

#### Streaming Payments
```solidity
// Admin creates monthly salary stream
paymentsPlugin.createStream(
    "alice",                    // username
    5000e6,                     // 5000 USDC per month
    address(usdc),              // token
    uint40(block.timestamp + 365 days) // end date
);
```

#### Scheduled Payments
```solidity
// Admin creates weekly allowance (recurring)
paymentsPlugin.createSchedule(
    "bob",                      // username
    500e6,                      // 500 USDC
    address(usdc),              // token
    IPayments.IntervalType.Weekly, // interval
    false,                      // not one-time
    uint40(block.timestamp + 7 days) // first payment
);

// Admin creates one-time project payment
paymentsPlugin.createSchedule(
    "freelancer",               // username
    2500e6,                     // 2500 USDC
    address(usdc),              // token
    IPayments.IntervalType.Weekly, // doesn't matter for one-time
    true,                       // one-time payment
    uint40(block.timestamp + 3 days) // payment date
);
```

### 3. Payment Execution

```solidity
// Anyone can request payouts (funds go to username holder)
uint256 streamPayout = paymentsPlugin.requestStreamPayout("alice");
paymentsPlugin.requestSchedulePayout("bob");
```

### 4. Stream Management

```solidity
// Admin can edit stream amounts
paymentsPlugin.editStream("alice", newAmountPerSecond);

// Admin can cancel streams (returns remaining funds to DAO)
paymentsPlugin.cancelStream("alice");
```

## Address Change and Stream Migration Workflow

**This is a critical workflow for wallet recovery scenarios.**

### Scenario: User Loses Wallet Access

When a user loses access to their wallet (hacked, lost keys, etc.), they need to update their address in the registry. The system now supports user-driven stream migration to handle this automatically.

#### Enhanced Registry Features

The AddressRegistry now tracks address history:

```solidity
struct AddressHistory {
    address currentAddress;
    address previousAddress;  // For migration support
    uint256 lastChangeTime;
}

// Get address history for migration
IRegistry.AddressHistory memory history = registry.getAddressHistory("alice");
```

#### User-Driven Migration Workflow:

1. **Address Update**: User (from new wallet) updates registry:
   ```solidity
   registry.updateUserAddress("alice", newWalletAddress);
   ```

2. **Stream Migration**: User migrates their own streams:
   ```solidity
   // Alice migrates her stream to new address (user-controlled)
   paymentsPlugin.migrateStream("alice");
   ```

3. **Automatic Resolution**: All future payments automatically go to new address

#### Migration Function Details

```solidity
function migrateStream(string calldata username) external {
    // Only current address holder can migrate
    address currentAddress = registry.getUserAddress(username);
    if (msg.sender != currentAddress) revert UnauthorizedMigration();
    
    Stream storage stream = streams[username];
    if (!stream.active) revert StreamNotFound();
    
    address oldStreamRecipient = streamRecipients[username];
    if (oldStreamRecipient == currentAddress) revert NoMigrationNeeded();
    
    // Migrate stream from old to new address
    _migrateStreamToNewAddress(username, oldStreamRecipient, currentAddress);
    
    emit StreamMigrated(username, oldStreamRecipient, currentAddress);
}
```

#### Migration Behavior:

- **User-Controlled**: Only the current username holder can migrate
- **Automatic Cleanup**: Old LlamaPay stream is cancelled (final payout to old address)
- **Seamless Recreation**: New LlamaPay stream created for new address
- **Identical Parameters**: Same amount, token, and end date
- **Security**: Old compromised wallet cannot migrate after address change

#### Important Notes:

- **No Admin Required**: Users migrate their own streams without admin intervention
- **Scalable**: No O(N) complexity across multiple DAOs
- **Final Payout**: Old address receives any accrued funds during migration
- **Scheduled Payments Unaffected**: Automatically resolve to new address
- **Multiple Migrations**: Users can migrate multiple times if needed

### Example Address Change and Migration Test Case

Our test `test_UsernameAddressUpdateDuringPayments()` demonstrates this enhanced workflow:

1. Alice has active stream with original wallet
2. Alice updates address (simulating wallet recovery)
3. Old stream becomes inaccessible (LlamaPay tied to old address)
4. **Alice migrates stream herself** (new user-driven approach)
5. Stream works correctly with new address
6. Future payments go to new address automatically

## Permission System

### PayNest Plugin Permissions

#### MANAGER_PERMISSION_ID
- **Granted to**: DAO admin (specified in factory)
- **Allows**: 
  - Creating streams and schedules
  - Editing and canceling payments
  - Managing payment infrastructure

#### EXECUTE_PERMISSION_ID
- **Granted to**: PayNest plugin (on the DAO)
- **Allows**:
  - Plugin to execute payments from DAO treasury
  - Plugin to interact with LlamaPay on behalf of DAO

### Security Model

- **Admin Control**: Only authorized addresses can create/manage payments
- **Public Payouts**: Anyone can trigger payouts (funds go to registered addresses)
- **DAO Treasury**: All funds remain in DAO until payment execution
- **Username Security**: Username ownership controls payment destination

## Integration Considerations

### LlamaPay Integration

- **Factory Address**: Hardcoded per network (Base: `0x09c39B8311e4B7c678cBDAD76556877ecD3aEa07`)
- **Stream Precision**: LlamaPay uses per-second rates, PayNest converts from period amounts
- **Cancellation**: Returns remaining funds to DAO treasury
- **Address Binding**: Streams permanently tied to creation-time addresses

### Aragon OSx Integration

- **Plugin Standard**: Full compliance with Aragon plugin architecture
- **Upgradeable**: UUPS proxy pattern for plugin upgrades
- **Permission System**: Native Aragon permission management
- **DAO Execution**: All payments executed through DAO's execute function

## Best Practices

### For DAO Admins

1. **Regular Monitoring**: Check stream balances and upcoming scheduled payments
2. **Address Changes**: Respond quickly to user wallet compromise reports
3. **Treasury Management**: Ensure sufficient DAO funds for ongoing payments
4. **Documentation**: Keep records of payment arrangements and changes

### For Users

1. **Username Security**: Choose unique, memorable usernames
2. **Address Updates**: Immediately report wallet compromise to DAO admin
3. **Regular Claims**: Regularly claim available payments to avoid accumulation
4. **Backup Planning**: Have secure backup access to wallet private keys

### For Developers

1. **Testing**: Always test with real fork environment for LlamaPay integration
2. **Gas Limits**: Account for gas costs in payment execution
3. **Error Handling**: Implement proper error handling for LlamaPay interactions
4. **Precision**: Handle wei-level precision differences in fund calculations

## Common Issues and Solutions

### "stream doesn't exist" Error

**Cause**: Username address was updated after stream creation  
**Solution**: User should migrate their own stream using `migrateStream(username)`

```solidity
// User migrates their own stream after address change
paymentsPlugin.migrateStream("alice");
```

### Permission Denied Errors

**Cause**: Unauthorized address trying to manage payments
**Solution**: Ensure proper MANAGER_PERMISSION setup

### Conservation of Funds Failures

**Cause**: Wei-level precision differences in LlamaPay calculations
**Solution**: Allow small tolerance (≤10 wei) in assertions

### Gas Limit Exceeded

**Cause**: Complex payment operations hitting gas limits
**Solution**: Batch operations or increase gas limits

## Future Enhancements

### Potential Improvements

1. **Batch Operations**: Enable multiple payment operations in single transaction
2. **Payment Notifications**: Event-based notification system
3. **Advanced Scheduling**: More complex scheduling patterns
4. **Multi-Token Support**: Enhanced support for various ERC20 tokens
5. **Automated Migration Detection**: Frontend tools to automatically detect needed migrations

### Known Limitations

1. **Single Registry**: One global registry per deployment
2. **Gas Costs**: Individual payment execution can be expensive  
3. **Manual Migration**: Users must manually trigger stream migration after address changes
4. **Migration Timing**: Old address receives final payout during migration
5. **Network-Specific**: LlamaPay factory address is hardcoded per network

---

This documentation covers the core functionality and critical workflows. For implementation details, see the individual contract specifications in the `docs/` directory.