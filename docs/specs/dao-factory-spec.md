# PayNest DAO Factory Specification

## Overview

This document specifies the PayNestDAOFactory contract that creates fully configured Aragon DAOs with both Admin plugin and PayNest plugin installed in a single transaction. The factory provides a streamlined way to deploy payment-enabled DAOs for the PayNest ecosystem, replacing the current standalone payment contract architecture with the more robust and upgradeable Aragon framework.

## Architecture Overview

```
PayNestDAOFactory.sol
├── Creates DAO via Aragon DAOFactory
├── Installs Admin Plugin (single-owner control)
├── Installs PayNest Plugin (streaming + scheduled payments)
└── Configures complete permission system
```

## PayNestDAOFactory Contract

### Base Architecture

```solidity
contract PayNestDAOFactory {
    /// @notice Shared AddressRegistry for all PayNest DAOs
    AddressRegistry public immutable addressRegistry;
    
    /// @notice Aragon DAO factory for creating DAOs
    DAOFactory public immutable daoFactory;
    
    /// @notice Plugin repository for Admin plugin
    PluginRepo public immutable adminPluginRepo;
    
    /// @notice Plugin repository for PayNest plugin  
    PluginRepo public immutable paymentsPluginRepo;
    
    /// @notice DAO deployment information
    mapping(address dao => DAOInfo) public daoInfo;
    
    /// @notice Track all created DAOs
    address[] public createdDAOs;
    
    struct DAOInfo {
        address admin;
        address adminPlugin;
        address paymentsPlugin;
        uint256 createdAt;
    }
}
```

### Core Function

```solidity
function createPayNestDAO(
    address admin,
    string memory daoName
) external returns (
    address dao,
    address adminPlugin,
    address paymentsPlugin
);
```

**Function Logic**:

- Validate admin address is not zero
- Validate DAO name is not empty
- Prepare DAO settings with metadata
- Configure Admin plugin installation parameters
- Configure PayNest plugin installation parameters
- Call Aragon DAOFactory.createDao() with both plugins
- Extract plugin addresses from installation results
- Store DAO information in mapping
- Add DAO to created DAOs array
- Emit PayNestDAOCreated event
- Return DAO and plugin addresses

### View Functions

```solidity
function getAddressRegistry() external view returns (address);
function getDAOInfo(address dao) external view returns (DAOInfo memory);
function getCreatedDAOsCount() external view returns (uint256);
function getCreatedDAO(uint256 index) external view returns (address);
```

### Events

```solidity
event PayNestDAOCreated(
    address indexed dao,
    address indexed admin,
    address adminPlugin,
    address paymentsPlugin,
    string daoName
);
```

### Custom Errors

```solidity
error AdminAddressZero();
error DAONameEmpty();
error DAOCreationFailed();
error PluginInstallationFailed();
```

## DAO Creation Process

### Input Validation

- Admin address must not be zero address
- DAO name must not be empty string
- All immutable contract references must be valid

### DAO Settings Configuration

**DAO Metadata**:
- trustedForwarder: address(0) (no meta-transactions)
- daoURI: Generated based on DAO name
- subdomain: Empty (no ENS subdomain)
- metadata: Encoded DAO name and creation timestamp

### Plugin Installation Configuration

**Admin Plugin Setup**:
- Uses latest version from admin plugin repository
- Installation data: admin address (becomes sole member)
- Grants EXECUTE_PROPOSAL_PERMISSION_ID to admin on plugin
- Grants EXECUTE_PERMISSION_ID to plugin on DAO

**PayNest Plugin Setup**:
- Uses latest version from payments plugin repository  
- Installation data: shared AddressRegistry address
- Grants MANAGER_PERMISSION_ID to DAO on plugin
- Grants EXECUTE_PERMISSION_ID to plugin on DAO

### Atomic Creation

- Single transaction creates DAO and installs both plugins
- Uses Aragon's DAOFactory.createDao() for proven reliability
- All permissions configured during installation
- No intermediate states or manual setup required

## Permission Model

### Permission Flow Architecture

```
Admin Address
    ↓ (EXECUTE_PROPOSAL_PERMISSION_ID)
Admin Plugin
    ↓ (EXECUTE_PERMISSION_ID) 
DAO
    ↓ (MANAGER_PERMISSION_ID)
PayNest Plugin
```

### Permission Setup

**Admin Control**:
- Admin gets EXECUTE_PROPOSAL_PERMISSION_ID on Admin plugin
- Allows admin to execute proposals immediately (auto-execution)
- Admin controls all DAO actions through Admin plugin

**Plugin Permissions**:
- Admin plugin gets EXECUTE_PERMISSION_ID on DAO
- PayNest plugin gets EXECUTE_PERMISSION_ID on DAO (for treasury actions)
- DAO gets MANAGER_PERMISSION_ID on PayNest plugin

### Usage Flow

When admin wants to create a payment:

```solidity
// Admin calls Admin plugin which executes DAO action on PayNest plugin
adminPlugin.executeProposal(
    metadata: "",
    actions: [
        {
            to: address(paymentsPlugin),
            value: 0,
            data: abi.encodeCall(paymentsPlugin.createStream, (...))
        }
    ],
    allowFailureMap: 0
);
```

## Integration Points

### AddressRegistry Integration

- Factory stores immutable reference to shared AddressRegistry
- All created DAOs use the same registry for username resolution
- No per-DAO registry deployment or configuration needed
- Consistent username → address resolution across all PayNest DAOs

### Aragon Integration

- Uses official Aragon DAOFactory for DAO creation
- References official Admin plugin repository
- Uses standard Aragon plugin installation process
- Leverages proven Aragon permission system

### PayNest Plugin Integration

- References deployed PayNest plugin repository
- Passes AddressRegistry address during plugin installation
- Ensures plugin has proper permissions to execute DAO actions
- Maintains compatibility with existing LlamaPay infrastructure

## Factory Deployment

### Immutable Dependencies

**Constructor Parameters**:
- addressRegistry: Deployed AddressRegistry contract
- daoFactory: Aragon's DAOFactory contract
- adminPluginRepo: Aragon's Admin plugin repository
- paymentsPluginRepo: PayNest plugin repository

### Network Deployment

- Factory deployed once per network using CREATE2
- Same bytecode across networks for consistency
- Different constructor parameters for network-specific contract addresses
- Deterministic addresses across Base and Base Sepolia

### Deployment Order

1. Deploy AddressRegistry (CREATE2, deterministic)
2. Deploy and publish PayNest plugin repository
3. Deploy PayNestDAOFactory with network-specific parameters

## Testing Strategy

### Unit Tests

**Factory Creation Tests**:
- Valid DAO creation with both plugins
- Input validation (zero admin, empty name)
- Event emission verification
- DAO info storage correctness

**Permission Tests**:
- Admin has control over Admin plugin
- Admin plugin has control over DAO
- DAO has control over PayNest plugin
- PayNest plugin has execution permissions

### Integration Tests

**End-to-End Workflows**:
- Create DAO → admin creates payment → payment execution
- Multiple DAO creation with shared registry
- Admin plugin → PayNest plugin interaction
- Username resolution through shared registry

**Cross-Component Tests**:
- DAO treasury interaction with PayNest plugin
- LlamaPay streaming through created DAOs
- Permission inheritance verification

### Fork Tests

**Real Aragon Integration**:
- Test against deployed Aragon contracts
- Verify Admin plugin installation works
- Test with real plugin repositories
- Validate permission setup on live networks

## Error Handling Strategy

### Input Validation

- Admin address validation prevents zero address assignment
- DAO name validation ensures meaningful identification
- Plugin repository validation ensures installation capability

### Creation Failures

- Handle Aragon DAOFactory failures gracefully
- Provide clear error messages for debugging
- Ensure atomic creation (all or nothing)

### Plugin Installation Failures

- Validate plugin repositories exist and are accessible
- Handle permission setup failures appropriately
- Ensure consistent state on any failure

## Security Considerations

### Access Control

- Factory is permissionless (anyone can create DAOs)
- Each DAO has independent admin control
- No central factory control over created DAOs
- Factory never holds or manages funds

### Permission Security

- Uses battle-tested Aragon permission system
- Admin plugin provides secure single-owner control
- PayNest plugin follows Aragon security patterns
- All fund movements through DAO treasury

### Registry Security

- Shared registry creates consistent username resolution
- Registry ownership separate from factory
- Username conflicts handled at registry level

## Gas Optimization

### Creation Efficiency

- Single transaction for complete DAO setup
- Minimal storage operations in factory
- Efficient plugin configuration encoding
- Reuse of immutable contract references

### Optimization Strategies

- Custom errors for efficient error handling
- Minimal external calls during creation
- Efficient event emission
- Optimized storage layout for DAO info

## Contract Invariants

**Critical invariants that must ALWAYS hold for testing and security:**

### Factory State Invariants

**Immutable References**:
- AddressRegistry reference MUST never be zero
- DAOFactory reference MUST never be zero
- Plugin repository references MUST never be zero
- All immutable references MUST remain constant post-deployment

**DAO Tracking**:
- Created DAOs array MUST only contain valid DAO addresses
- DAO info mapping MUST exist for all tracked DAOs
- DAO count MUST match created DAOs array length
- No duplicate DAOs in tracking arrays

### Creation Process Invariants

**Atomic Creation**:
- DAO creation MUST be atomic (all plugins installed or none)
- Permission setup MUST complete for successful creation
- Failed creation MUST NOT leave partial state
- All created DAOs MUST have both required plugins

**Permission Integrity**:
- Admin MUST have EXECUTE_PROPOSAL_PERMISSION_ID on Admin plugin
- Admin plugin MUST have EXECUTE_PERMISSION_ID on DAO
- PayNest plugin MUST have EXECUTE_PERMISSION_ID on DAO
- DAO MUST have MANAGER_PERMISSION_ID on PayNest plugin

### Plugin Configuration Invariants

**Admin Plugin Setup**:
- Admin plugin MUST be configured with correct admin address
- Admin plugin MUST have immediate execution capability
- Admin plugin MUST be connected to created DAO

**PayNest Plugin Setup**:
- PayNest plugin MUST reference shared AddressRegistry
- PayNest plugin MUST be connected to created DAO
- PayNest plugin MUST have proper treasury access permissions

### Registry Integration Invariants

**Shared Registry**:
- All created DAOs MUST use the same AddressRegistry
- Registry address MUST be consistent across all plugin installations
- Registry reference MUST never change post-deployment

### Security Invariants

**Access Control**:
- Factory MUST NOT hold funds at any time
- Factory MUST NOT have control over created DAOs
- Each DAO MUST have independent admin control
- Admin permissions MUST be correctly assigned to specified address

**State Consistency**:
- DAO info MUST accurately reflect created DAO state
- Plugin addresses MUST match actual installed plugins
- Creation timestamps MUST be accurate
- Event emission MUST be consistent with state changes

## Summary

The PayNest DAO Factory specification provides:

- ✅ **Single Transaction DAO Creation**: Complete setup in one call
- ✅ **Admin Plugin Integration**: Immediate single-owner control
- ✅ **PayNest Plugin Integration**: Full payment functionality
- ✅ **Shared Registry**: Consistent username resolution
- ✅ **Aragon Compatibility**: Uses proven DAO framework
- ✅ **Permission Security**: Proper access control setup
- ✅ **Upgrade Path**: Can evolve from admin to complex governance
- ✅ **Deterministic Deployment**: CREATE2 for consistent addresses

The factory serves as the foundation for PayNest's transition from standalone contracts to the robust, upgradeable Aragon plugin ecosystem while maintaining simple single-owner control that can evolve over time.