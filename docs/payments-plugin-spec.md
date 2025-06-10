# Payments Plugin Specification

## Overview

This document specifies both the main PaymentsPlugin contract and its PaymentsPluginSetup contract, following the Aragon OSx plugin architecture patterns. The plugin implements the IPayments interface while integrating with LlamaPay for streaming and the AddressRegistry for username resolution.

## Architecture Overview

```
PaymentsPluginSetup.sol
├── Manages plugin installation/uninstallation
├── Sets up permissions
└── Deploys PaymentsPlugin proxy

PaymentsPlugin.sol
├── Implements IPayments interface
├── Integrates with LlamaPay for streaming
├── Uses AddressRegistry for username resolution
└── Uses Aragon permission system
```

## Part 1: PaymentsPlugin Contract

### Base Architecture

```solidity
contract PaymentsPlugin is PluginUUPSUpgradeable, IPayments {
    // Permission constants
    bytes32 public constant MANAGER_PERMISSION_ID = keccak256("MANAGER_PERMISSION");

    // External contract references
    IRegistry public registry;
    ILlamaPayFactory public llamaPayFactory;

    // Storage mappings (from IPayments interface)
    mapping(string => Stream) public streams;
    mapping(string => Schedule) public schedules;

    // Storage gap for upgrades
    uint256[46] private __gap;
}
```

### Initialization

```solidity
function initialize(
    IDAO _dao,
    address _registryAddress,
    address _llamaPayFactoryAddress
) external initializer;
```

**Initialization Logic**:

- Call `__PluginUUPSUpgradeable_init(_dao)`
- Store registry and LlamaPay factory addresses
- Initialize any default settings
- Emit initialization event

### IPayments Interface Implementation

#### Stream Management

```solidity
function createStream(
    string calldata username,
    uint256 amount,
    address token,
    uint40 endStream
) external auth(MANAGER_PERMISSION_ID);
```

**Function Logic**:

- Resolve username to address via registry
- Get/deploy LlamaPay contract for token
- Calculate amountPerSec with proper decimals
- Execute DAO action to approve token to LlamaPay
- Execute DAO action to deposit funds to LlamaPay
- Create LlamaPay stream to resolved address
- Store stream metadata
- Emit StreamActive event

```solidity
function cancelStream(string calldata username) external auth(MANAGER_PERMISSION_ID);
```

**Function Logic**:

- Get stream metadata
- Resolve current username address
- Cancel LlamaPay stream
- Withdraw remaining funds back to DAO
- Clear stream metadata
- Emit PaymentStreamCancelled event

```solidity
function editStream(string calldata username, uint256 amount) external auth(MANAGER_PERMISSION_ID);
```

**Function Logic**:

- Validate stream exists and is active
- Cancel existing LlamaPay stream
- Calculate new amountPerSec
- Create new LlamaPay stream with updated amount
- Update stream metadata
- Emit StreamUpdated event

```solidity
function requestStreamPayout(string calldata username) external payable returns (uint256);
```

**Function Logic**:

- Get stream metadata
- Resolve username to current address
- Call LlamaPay withdraw on behalf of recipient
- Update lastPayout timestamp
- Emit StreamPayout event
- Return payout amount

#### Schedule Management

```solidity
function createSchedule(
    string calldata username,
    uint256 amount,
    address token,
    IntervalType interval,
    bool isOneTime,
    uint40 firstPaymentDate
) external auth(MANAGER_PERMISSION_ID);
```

**Function Logic**:

- Validate username exists
- Store schedule metadata
- Emit ScheduleActive event
- Note: No immediate token movement (happens on requestSchedulePayout)

```solidity
function requestSchedulePayout(string calldata username) external payable;
```

**Function Logic**:

- Get schedule metadata
- Validate schedule is active and payment is due
- Resolve username to current address
- Calculate missed payments for recurring schedules (eager payout)
- Execute DAO action to transfer total amount to recipient
- Update nextPayout timestamp (if recurring) or deactivate (if one-time)
- Emit SchedulePayout event

**Scheduling Intervals**:

- Weekly: 7 days
- Monthly: 30 days
- Quarterly: 90 days
- Yearly: 365 days

**Eager Payout Logic**: For recurring payments, if multiple intervals have passed, pay for all missed periods at once

```solidity
function cancelSchedule(string calldata username) external auth(MANAGER_PERMISSION_ID);
```

**Function Logic**:

- Get schedule metadata
- Mark as inactive
- Emit PaymentScheduleCancelled event

```solidity
function editSchedule(string calldata username, uint256 amount) external auth(MANAGER_PERMISSION_ID);
```

**Function Logic**:

- Validate schedule exists and is active
- Update schedule amount (no edit restrictions)
- Emit ScheduleUpdated event

### DAO Treasury Integration

```solidity
function _executeDAOActions(Action[] memory actions) internal;
```

**Function Logic**:

- Create execution ID
- Call dao().execute() with actions
- Handle any failures appropriately

**Common DAO Actions**:

- Token approvals for LlamaPay contracts
- Token deposits to LlamaPay
- Direct token transfers for scheduled payments

### LlamaPay Integration

```solidity
function _getLlamaPayContract(address token) internal returns (address);
```

**Function Logic**:

- Check if LlamaPay contract exists for token via factory
- Deploy if needed using factory.createLlamaPayContract(token)
- Return contract address

```solidity
function _calculateAmountPerSec(uint256 totalAmount, uint256 duration, address token) internal view returns (uint216);
```

**Function Logic**:

- Get token decimals
- Convert to LlamaPay's 20-decimal precision
- Calculate per-second rate
- Validate fits in uint216

### Username Resolution

```solidity
function _resolveUsername(string calldata username) internal view returns (address);
```

**Function Logic**:

- Call registry.getUserAddress(username)
- Validate returned address is not zero
- Return resolved address

### View Functions

```solidity
function getStream(string calldata username) external view returns (Stream memory);
function getSchedule(string calldata username) external view returns (Schedule memory);
```

### Custom Errors

```solidity
error UsernameNotFound();
error StreamNotActive();
error ScheduleNotActive();
error PaymentNotDue();
error InsufficientDAOBalance();
error LlamaPayOperationFailed();
error InvalidToken();
error InvalidAmount();
error StreamAlreadyExists();
error ScheduleAlreadyExists();
```

## Part 2: PaymentsPluginSetup Contract

### Base Architecture

```solidity
contract PaymentsPluginSetup is PluginSetup {
    constructor() PluginSetup(address(new PaymentsPlugin())) {}
}
```

### Installation

```solidity
function prepareInstallation(
    address _dao,
    bytes memory _installationParams
) external returns (address plugin, PreparedSetupData memory preparedSetupData);
```

**Function Logic**:

- Decode installation parameters
- Deploy UUPS proxy of PaymentsPlugin
- Initialize plugin with DAO and parameters
- Set up permission array
- Return plugin address and setup data

**Installation Parameters**:

```solidity
struct InstallationParams {
    address managerAddress;      // Who can manage payments
    address registryAddress;     // Address registry contract
    address llamaPayFactory;     // LlamaPay factory contract
}
```

**Permissions Setup**:

1. `managerAddress` gets `MANAGER_PERMISSION_ID` on plugin
2. Plugin gets `EXECUTE_PERMISSION_ID` on DAO

### Uninstallation

```solidity
function prepareUninstallation(
    address _dao,
    SetupPayload calldata _payload
) external view returns (PermissionLib.MultiTargetPermission[] memory);
```

**Function Logic**:

- Decode uninstallation parameters
- Create permissions array to revoke
- Return revocation permissions

### Parameter Helpers

```solidity
function encodeInstallationParams(
    address _managerAddress,
    address _registryAddress,
    address _llamaPayFactory
) external pure returns (bytes memory);

function decodeInstallationParams(bytes memory _data)
    public pure returns (address, address, address);

function encodeUninstallationParams(address _managerAddress)
    external pure returns (bytes memory);

function decodeUninstallationParams(bytes memory _data)
    public pure returns (address);
```

## Integration Patterns

### DAO Action Execution Pattern

```solidity
// Example: Approve tokens for LlamaPay
Action[] memory actions = new Action[](1);
actions[0].to = tokenAddress;
actions[0].value = 0;
actions[0].data = abi.encodeCall(IERC20.approve, (llamaPayContract, amount));

dao().execute(
    keccak256(abi.encodePacked("approve-", tokenAddress, "-", llamaPayContract)),
    actions,
    0 // failSafeMap
);
```

### Error Handling Strategy

- Use custom errors for gas efficiency
- Validate all external calls (registry, LlamaPay)
- Handle LlamaPay decimal conversions carefully
- Graceful handling of username resolution failures
- Proper validation of DAO treasury balance

### Permission Strategy

- `MANAGER_PERMISSION_ID`: Required for all payment management functions
- `EXECUTE_PERMISSION_ID`: Plugin needs this on DAO to move treasury funds
- No public functions that directly transfer funds
- All fund movements go through DAO actions

## Testing Strategy

### PaymentsPlugin Tests

**Unit Tests**:

- Stream creation with username resolution
- Scheduled payment creation and execution
- LlamaPay integration with decimal handling
- Permission boundary testing
- Error condition handling

**Integration Tests**:

- Full workflow: create stream → payout → cancel
- DAO treasury integration
- Multiple token support
- Username address changes mid-stream

### PaymentsPluginSetup Tests

**Setup Tests**:

- Installation parameter encoding/decoding
- Permission granting during installation
- Plugin proxy deployment
- Uninstallation cleanup

**Integration Tests**:

- Full install → use → uninstall workflow
- Permission verification
- Parameter validation

## Deployment Considerations

### Plugin Deployment

1. Deploy AddressRegistry first
2. Deploy PaymentsPluginSetup
3. Publish to Aragon plugin repository
4. DAOs install via standard Aragon mechanisms

### Configuration

- Registry address: Global across all chains
- LlamaPay factory: Deterministic address across chains
- Manager address: Per-DAO configuration

### Security Considerations

- Plugin never holds funds directly
- All fund movements via DAO.execute()
- Username resolution at payment execution time
- Proper decimal handling for all tokens
- Protection against reentrancy via Aragon patterns

## Gas Optimization

- Cache LlamaPay contract addresses
- Batch multiple DAO actions when possible
- Efficient storage layout
- Custom errors for error handling
- Minimal external calls during view functions

## Summary

The Payments Plugin specification provides:

**PaymentsPlugin.sol**:

- ✅ Full IPayments interface implementation
- ✅ LlamaPay streaming integration
- ✅ AddressRegistry username resolution
- ✅ Aragon permission system integration
- ✅ DAO treasury integration via actions
- ✅ UUPS upgradeable pattern

**PaymentsPluginSetup.sol**:

- ✅ Standard Aragon plugin installation
- ✅ Proper permission configuration
- ✅ Parameter encoding/decoding helpers
- ✅ Clean uninstallation process

The design maintains security by never holding funds directly, uses the proven Aragon permission system, and integrates seamlessly with existing LlamaPay infrastructure while adding the convenience of username-based payments.
