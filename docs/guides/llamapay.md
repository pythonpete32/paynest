# LlamaPay Integration Specification

## Executive Summary

This document provides a comprehensive specification for integrating with LlamaPay streaming payment contracts in the PayNest payments plugin. LlamaPay is a battle-tested, gas-optimized streaming payment protocol that handles continuous token transfers with high precision and minimal gas costs.

## LlamaPay Architecture Overview

### Core Components

1. **LlamaPayFactory.sol** - Deploys deterministic LlamaPay instances per token
2. **LlamaPay.sol** - Core streaming payment contract for each token
3. **Stream Management** - Per-second streaming with debt management
4. **High Precision Math** - 20 decimal internal representation

### Key Features

- **Gas Efficient**: 69,963 gas per stream creation (3.2x-3.7x cheaper than competitors)
- **Debt Management**: Streams continue when balance depleted, accumulating debt
- **High Precision**: Uses 20 decimals internally to prevent precision errors
- **Anyone Can Withdraw**: Third parties can trigger withdrawals for recipients
- **No Duration Limits**: Indefinite streams that draw from payer balance
- **Batch Operations**: Multiple operations in single transaction

## LlamaPay Contract Interface Analysis

### Factory Contract

```solidity
interface ILlamaPayFactory {
    function createLlamaPayContract(address _token) external returns (address llamaPayContract);
    function getLlamaPayContractByToken(address _token) external view returns (address predictedAddress, bool isDeployed);
    function getLlamaPayContractCount() external view returns (uint256);
    function getLlamaPayContractByIndex(uint256 index) external view returns (address);
}
```

**Key Insights**:
- CREATE2 deterministic deployment: `keccak256(factory, token, salt)`
- One LlamaPay contract per token address
- Predictable addresses enable gas-efficient integration

### Core LlamaPay Contract Interface

```solidity
interface ILlamaPay {
    // Stream Management
    function createStream(address to, uint216 amountPerSec) external;
    function createStreamWithReason(address to, uint216 amountPerSec, string calldata reason) external;
    function cancelStream(address to, uint216 amountPerSec) external;
    function pauseStream(address to, uint216 amountPerSec) external;
    function modifyStream(address oldTo, uint216 oldAmountPerSec, address to, uint216 amountPerSec) external;
    
    // Withdrawals
    function withdraw(address from, address to, uint216 amountPerSec) external;
    function withdrawable(address from, address to, uint216 amountPerSec) external view returns (uint withdrawableAmount, uint lastUpdate, uint owed);
    
    // Balance Management
    function deposit(uint amount) external;
    function depositAndCreate(uint amountToDeposit, address to, uint216 amountPerSec) external;
    function withdrawPayer(uint amount) external;
    function withdrawPayerAll() external;
    function getPayerBalance(address payerAddress) external view returns (int);
    
    // Utilities
    function getStreamId(address from, address to, uint216 amountPerSec) external pure returns (bytes32);
    function streamToStart(bytes32 streamId) external view returns (uint);
    function balances(address payer) external view returns (uint);
    function token() external view returns (address);
    function DECIMALS_DIVISOR() external view returns (uint);
}
```

### Critical Implementation Details

#### Decimal Handling
```solidity
// LlamaPay uses 20 decimals internally for precision
// External amounts use native token decimals
// DECIMALS_DIVISOR = 10**(20 - tokenDecimals)

// Internal conversion formula:
internalAmount = externalAmount * DECIMALS_DIVISOR
externalAmount = internalAmount / DECIMALS_DIVISOR
```

#### Stream Identification
```solidity
// Streams are identified by hash of (from, to, amountPerSec)
streamId = keccak256(abi.encodePacked(from, to, amountPerSec))

// Multiple streams between same addresses require different amounts
// Or cancel existing stream before creating new one
```

#### Debt Management System
- When payer balance depleted, streams accumulate debt instead of stopping
- `withdrawable()` returns both available amount and owed amount
- Streams resume automatically when payer deposits more funds
- No penalty system or liquidation - streams gracefully handle insufficient funds

## Integration Strategy for PayNest

### 1. Factory Integration Pattern

```solidity
contract PaymentsPlugin {
    ILlamaPayFactory public constant LLAMAPAY_FACTORY = ILlamaPayFactory(0x...);
    
    mapping(address => address) public tokenToLlamaPay;
    
    function _getLlamaPayContract(address token) internal returns (address) {
        address llamaPayContract = tokenToLlamaPay[token];
        if (llamaPayContract == address(0)) {
            (address predicted, bool deployed) = LLAMAPAY_FACTORY.getLlamaPayContractByToken(token);
            if (!deployed) {
                llamaPayContract = LLAMAPAY_FACTORY.createLlamaPayContract(token);
            } else {
                llamaPayContract = predicted;
            }
            tokenToLlamaPay[token] = llamaPayContract;
        }
        return llamaPayContract;
    }
}
```

### 2. Stream Management Integration

```solidity
function createStream(
    string calldata username,
    uint256 amount,
    address token,
    uint40 endStream
) external auth(MANAGER_PERMISSION_ID) {
    // 1. Resolve username to address
    address recipient = registry.getUserAddress(username);
    require(recipient != address(0), "Invalid username");
    
    // 2. Get LlamaPay contract for token
    address llamaPayContract = _getLlamaPayContract(token);
    
    // 3. Calculate amount per second with proper decimals
    uint256 duration = endStream - block.timestamp;
    uint216 amountPerSec = _calculateAmountPerSec(amount, duration, token);
    
    // 4. Ensure DAO has sufficient approved balance
    _ensureDAOApproval(token, llamaPayContract, amount);
    
    // 5. Deposit funds to LlamaPay
    ILlamaPay(llamaPayContract).deposit(amount);
    
    // 6. Create the stream
    ILlamaPay(llamaPayContract).createStreamWithReason(
        recipient, 
        amountPerSec, 
        string(abi.encodePacked("PayNest stream for ", username))
    );
    
    // 7. Store stream metadata
    streams[username] = Stream({
        token: token,
        endDate: endStream,
        active: true,
        amount: amountPerSec,
        lastPayout: uint40(block.timestamp)
    });
    
    emit StreamActive(username, token, endStream, amount);
}
```

### 3. Decimal Conversion Utilities

```solidity
function _calculateAmountPerSec(
    uint256 totalAmount,
    uint256 duration,
    address token
) internal view returns (uint216) {
    // Get token decimals
    uint8 tokenDecimals = IERC20WithDecimals(token).decimals();
    uint256 decimalsMultiplier = 10**(20 - tokenDecimals);
    
    // Convert to per-second rate with 20 decimal precision
    uint256 amountPerSec = (totalAmount * decimalsMultiplier) / duration;
    
    // Ensure fits in uint216
    require(amountPerSec <= type(uint216).max, "Amount per second overflow");
    
    return uint216(amountPerSec);
}

function _convertFromLlamaPayDecimals(
    uint256 llamaPayAmount,
    address token
) internal view returns (uint256) {
    uint8 tokenDecimals = IERC20WithDecimals(token).decimals();
    uint256 decimalsMultiplier = 10**(20 - tokenDecimals);
    return llamaPayAmount / decimalsMultiplier;
}
```

### 4. Fund Management Strategy

#### DAO Treasury Integration
```solidity
function _ensureDAOApproval(
    address token,
    address llamaPayContract,
    uint256 amount
) internal {
    // Check if DAO has already approved LlamaPay contract
    uint256 currentAllowance = IERC20(token).allowance(address(dao()), llamaPayContract);
    
    if (currentAllowance < amount) {
        // Create action to approve LlamaPay contract
        Action[] memory actions = new Action[](1);
        actions[0].to = token;
        actions[0].data = abi.encodeCall(
            IERC20.approve,
            (llamaPayContract, type(uint256).max)
        );
        
        // Execute via DAO
        dao().execute(
            keccak256(abi.encodePacked("approve-llamapay-", token)),
            actions,
            0
        );
    }
}

function _depositToLlamaPay(
    address token,
    address llamaPayContract,
    uint256 amount
) internal {
    // Create action to deposit to LlamaPay
    Action[] memory actions = new Action[](1);
    actions[0].to = llamaPayContract;
    actions[0].data = abi.encodeCall(ILlamaPay.deposit, (amount));
    
    // Execute via DAO
    dao().execute(
        keccak256(abi.encodePacked("deposit-llamapay-", token)),
        actions,
        0
    );
}
```

## Error Handling & Edge Cases

### 1. Stream Creation Failures

```solidity
function _handleStreamCreation(address to, uint216 amountPerSec, address llamaPayContract) internal {
    try ILlamaPay(llamaPayContract).createStream(to, amountPerSec) {
        // Success
    } catch Error(string memory reason) {
        if (keccak256(bytes(reason)) == keccak256("stream already exists")) {
            // Cancel existing stream and create new one
            ILlamaPay(llamaPayContract).cancelStream(to, amountPerSec);
            ILlamaPay(llamaPayContract).createStream(to, amountPerSec);
        } else {
            revert(reason);
        }
    }
}
```

### 2. Insufficient Balance Handling

```solidity
function _checkStreamHealth(string calldata username) external view returns (bool healthy, uint256 owed) {
    Stream memory stream = streams[username];
    address recipient = registry.getUserAddress(username);
    address llamaPayContract = tokenToLlamaPay[stream.token];
    
    (, , uint256 owedAmount) = ILlamaPay(llamaPayContract).withdrawable(
        address(dao()),
        recipient,
        stream.amount
    );
    
    return (owedAmount == 0, owedAmount);
}
```

### 3. Username Resolution Failures

```solidity
function requestStreamPayout(string calldata username) external returns (uint256) {
    address recipient = registry.getUserAddress(username);
    require(recipient != address(0), "Username not found");
    
    Stream memory stream = streams[username];
    require(stream.active, "Stream not active");
    
    address llamaPayContract = tokenToLlamaPay[stream.token];
    
    // Withdraw on behalf of recipient
    ILlamaPay(llamaPayContract).withdraw(address(dao()), recipient, stream.amount);
    
    // Get actual withdrawn amount
    (uint256 withdrawableAmount, ,) = ILlamaPay(llamaPayContract).withdrawable(
        address(dao()),
        recipient,
        stream.amount
    );
    
    emit StreamPayout(username, stream.token, withdrawableAmount);
    return withdrawableAmount;
}
```

## Gas Optimization Strategies

### 1. Batch Operations
- Use LlamaPay's `BoringBatchable` for multiple operations
- Batch multiple stream creations in single transaction
- Combine deposit and stream creation operations

### 2. Factory Contract Caching
- Cache LlamaPay contract addresses per token
- Use CREATE2 deterministic addresses to skip factory calls
- Pre-compute contract addresses off-chain

### 3. Approval Management
- Use `approve(type(uint256).max)` to avoid repeated approvals
- Check existing allowances before creating approval actions
- Batch multiple token approvals when possible

## Security Considerations

### 1. Permission Validation
- Always validate DAO has MANAGER_PERMISSION before stream operations
- Ensure plugin has EXECUTE_PERMISSION on DAO for treasury access
- Validate username resolution before stream creation

### 2. Amount Validation
```solidity
function _validateStreamAmount(uint256 amount, uint256 duration) internal pure {
    require(amount > 0, "Amount must be positive");
    require(duration > 0, "Duration must be positive");
    
    // Ensure per-second amount doesn't overflow uint216
    uint256 amountPerSec = amount / duration;
    require(amountPerSec <= type(uint216).max, "Amount per second overflow");
    
    // Ensure minimum meaningful stream (1 token per day minimum)
    require(amountPerSec >= 1e20 / 86400, "Stream rate too small");
}
```

### 3. Reentrancy Protection
- LlamaPay uses proper reentrancy patterns
- Plugin should still use ReentrancyGuard for public functions
- External calls to registry should be safe but validate responses

## Integration Testing Strategy

### 1. Unit Tests
- Mock LlamaPay factory and contracts
- Test decimal conversion functions
- Test error handling for all edge cases

### 2. Integration Tests
- Deploy actual LlamaPay contracts in test environment
- Test with multiple token types (6, 8, 18 decimals)
- Test stream lifecycle: create → payout → cancel

### 3. Fork Tests
- Test against live LlamaPay deployments
- Validate gas costs match expectations
- Test with real token contracts

## Deployment Addresses

### Mainnet
- Factory: `0xde1C04855c2828431ba637675B6929A684f84C7`
- Registry: Deterministic per token via CREATE2

### Polygon
- Factory: `0xde1C04855c2828431ba637675B6929A684f84C7`
- Registry: Same deterministic deployment

### Arbitrum
- Factory: `0xde1C04855c2828431ba637675B6929A684f84C7`
- Registry: Same deterministic deployment

*Note: LlamaPay uses same addresses across all chains*

## Contract Invariants

**Critical invariants for LlamaPay integration:**

### LlamaPay Integration Invariants

**Decimal Precision**:
- Internal amounts (20 decimals) MUST correctly convert to/from native token decimals
- No precision loss during decimal conversions
- AmountPerSec calculations MUST fit in uint216

**Factory Pattern**:
- One LlamaPay contract per token address
- Factory addresses MUST be deterministic via CREATE2
- Contract deployment MUST be idempotent

**Stream Integrity**:
- LlamaPay stream IDs MUST be deterministic: `keccak256(from, to, amountPerSec)`
- Stream state MUST be consistent between plugin and LlamaPay
- Stream operations MUST be atomic

**Fund Security**:
- Funds MUST flow: DAO → LlamaPay → Recipient
- No intermediate custody by plugin
- Proper approval and deposit patterns

**Error Handling**:
- Failed LlamaPay operations MUST revert cleanly
- Decimal overflow/underflow MUST be prevented
- Invalid token addresses MUST be rejected

## Implementation Checklist

- [ ] Deploy and test LlamaPay factory integration
- [ ] Implement decimal conversion utilities with tests
- [ ] Create stream management wrapper functions
- [ ] Implement DAO treasury integration patterns
- [ ] Add comprehensive error handling
- [ ] Optimize for gas efficiency
- [ ] Add monitoring and health check functions
- [ ] Create emergency pause/recovery mechanisms
- [ ] Test with multiple token types
- [ ] Validate against live LlamaPay contracts

## Conclusion

LlamaPay provides a robust, gas-efficient foundation for streaming payments. The key integration challenges are:

1. **Decimal Management**: Careful conversion between native and 20-decimal precision
2. **Factory Pattern**: Efficient contract discovery and deployment
3. **DAO Integration**: Proper approval and execution patterns
4. **Error Handling**: Graceful handling of edge cases and failures

The specification provides clear patterns for each challenge, enabling secure and efficient integration with the PayNest payments plugin ecosystem.

---

*This specification serves as the foundation for implementing LlamaPay streaming functionality in the PayNest payments plugin.*