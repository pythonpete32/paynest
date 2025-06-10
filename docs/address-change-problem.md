# Address Change Problem Statement

## Problem Identified

During end-to-end testing, we discovered a critical design limitation in the PayNest system when users need to update their addresses (wallet recovery scenarios).

## Current Behavior

1. **User has active stream**: Alice has a LlamaPay stream created via PayNest
2. **Address compromise**: Alice's wallet is compromised, she needs to change addresses
3. **Address update**: Alice updates her address in the AddressRegistry
4. **Broken state**: System enters inconsistent state:
   - PayNest tracks an "active" stream for username "alice"
   - LlamaPay stream is tied to old address and inaccessible with new address
   - `requestStreamPayout("alice")` fails with "stream doesn't exist"
   - `cancelStream("alice")` fails with "stream doesn't exist" 
   - `createStream("alice", ...)` fails with "StreamAlreadyExists"

## Root Cause

**Two-layer tracking disconnect**: PayNest tracks streams by username, but LlamaPay tracks streams by specific addresses. When the username→address mapping changes, these layers become disconnected.

## Current System Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ PayNest Plugin  │    │ AddressRegistry  │    │ LlamaPay        │
│                 │    │                  │    │                 │
│ streams["alice"]│────┤ "alice" → addr1  │    │ stream(dao,     │
│ = active        │    │         → addr2  │    │   addr1, rate)  │
│                 │    │ (updated)        │    │ = exists        │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                         │
                        When alice updates to addr2:    │
                        - PayNest thinks stream active  │
                        - LlamaPay stream tied to addr1 │
                        - Lookup with addr2 fails ──────┘
```

## Impact

- **User funds stuck**: Legitimate users can't access their payments after address changes
- **Admin burden**: No clean way for admins to resolve orphaned streams
- **Security risk**: Compromised wallets might still have accessible streams
- **UX friction**: Complex manual intervention required

## User Scenarios Affected

1. **Wallet compromise**: User's keys are stolen, needs new wallet
2. **Hardware wallet failure**: User switches to new hardware wallet
3. **Mobile wallet switch**: User changes from mobile to desktop wallet
4. **Corporate wallet changes**: Company updates treasury management setup

## Requirements for Solution

1. **Automatic cleanup**: When address changes, handle existing streams gracefully
2. **Security**: Prevent compromised wallets from accessing new streams
3. **Admin tools**: Give DAO admins ability to handle edge cases
4. **Backward compatibility**: Don't break existing functionality
5. **Gas efficiency**: Don't make address changes prohibitively expensive

## Potential Solutions

### Option 1: Registry-Coordinated Stream Migration
- AddressRegistry notifies PayNest about address changes
- PayNest automatically cancels old streams and recreates for new address
- Requires cross-contract coordination

### Option 2: Stream Cleanup Functions
- Add admin functions to force-clean orphaned streams
- Add user functions to handle their own orphaned streams
- Manual but flexible approach

### Option 3: Dual-Address Stream Tracking
- Track both username and specific address in PayNest
- Validate both username and address when operating on streams
- More complex but more robust

### Option 4: Registry Lock-and-Migrate Pattern
- Prevent address changes while streams are active
- Require explicit stream migration or cancellation before address changes
- Safest but potentially restrictive

## Recommended Approach

**Hybrid solution combining Options 1 and 2**:

1. **Enhanced AddressRegistry**: 
   - Add hooks for address change notifications
   - Track active stream contracts per username

2. **PayNest Stream Management**:
   - Add cleanup functions for orphaned streams
   - Add migration helper functions
   - Emit events for external tracking

3. **Coordinated Migration Workflow**:
   - Address change triggers automatic stream cleanup
   - Admin can recreate streams for new address
   - Clear audit trail of all changes

## Next Steps

1. Design enhanced AddressRegistry interface
2. Add PayNest cleanup and migration functions  
3. Implement coordinated address change workflow
4. Update tests to cover new functionality
5. Document new operational procedures

## Test Cases to Address

- ✅ Address change makes existing streams inaccessible
- ❌ Clean recovery from orphaned stream state
- ❌ Admin tools for manual intervention
- ❌ Prevent duplicate streams after address change
- ❌ Security: old compromised address can't affect new streams
- ❌ Gas costs reasonable for address change operations

---

**Status**: Problem identified, solution design in progress
**Priority**: High - blocks mainnet deployment
**Impact**: Critical functionality for wallet recovery scenarios