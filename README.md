# PayNest 💸

A comprehensive payments plugin for Aragon DAOs that enables username-based streaming payments and scheduled payouts through LlamaPay integration.

## What is PayNest?

PayNest simplifies DAO treasury management by allowing DAOs to:

- **Stream payments** to contributors using human-readable usernames instead of wallet addresses
- **Schedule recurring payments** (weekly, monthly, quarterly, yearly) for regular contributors
- **Integrate with LlamaPay** for gas-efficient, continuous token streaming
- **Resolve usernames** through a global address registry system

## Key Features ✨

- **Username-Based Payments**: Send payments to `@alice` instead of `0x1234...`
- **LlamaPay Integration**: Leverage battle-tested streaming payment infrastructure
- **Flexible Scheduling**: Support for one-time and recurring payment schedules
- **DAO Treasury Integration**: Secure fund management through Aragon's permission system
- **Multi-Token Support**: Stream any ERC-20 token with proper decimal handling
- **Gas Optimized**: Efficient operations using LlamaPay's 69k gas stream creation

## Prerequisites 📋
- [Foundry](https://getfoundry.sh/)
- Git
- [Make](https://www.gnu.org/software/make/)
- [Docker](https://www.docker.com) (optional)

## Architecture Overview

PayNest consists of three main components:

### 1. PaymentsPlugin Contract
The core plugin that handles streaming and scheduled payments:
- Implements the `IPayments` interface 
- Integrates with LlamaPay for streaming functionality
- Manages scheduled payments with flexible intervals
- Resolves usernames through the AddressRegistry

### 2. AddressRegistry Contract  
A global username-to-address mapping system:
- One username per address (1:1 mapping)
- Alphanumeric usernames with strict validation
- Cross-DAO compatibility for consistent username resolution
- No admin controls - fully decentralized

### 3. LlamaPay Integration
Battle-tested streaming payment infrastructure:
- Gas-efficient continuous token transfers (69k gas per stream)
- High-precision math with 20-decimal internal representation
- Debt management when DAO balance insufficient
- Multi-token support across all networks

## Getting Started 🏁

```bash
git clone https://github.com/your-org/paynest
cd paynest
cp .env.example .env
make init
forge build
```

Edit `.env` to configure your target network and deployment settings.

### Installing dependencies

```sh
forge install <github-org>/<repo-name>  # replace accordingly

# Use the version you need
cd lib/<repo-name>
git checkout v1.9.0

# Commit the version to use
cd -
git add lib/<repo-name>
git commit -m"Using repo-name v1.9.0"
```

Add the new package to `remappings.txt`:

```txt
@organiation/repo-name/=lib/repo-name
```

### Using the Makefile

The `Makefile` is the target launcher of the project. It's the recommended way to operate the repository. It manages the env variables of common tasks and executes only the steps that need to be run.

```
$ make
Available targets:

- make help               Display the available targets

- make init               Check the dependencies and prompt to install if needed
- make clean              Clean the build artifacts

Testing lifecycle:

- make test               Run unit tests, locally
- make test-fork          Run fork tests, using RPC_URL
- make test-coverage      Generate an HTML coverage report under ./report

- make sync-tests         Scaffold or sync test definitions into solidity tests
- make check-tests        Checks if the solidity test files are out of sync
- make markdown-tests     Generates a markdown file with the test definitions rendered as a tree

Deployment targets:

- make predeploy          Simulate a protocol deployment
- make deploy             Deploy the protocol, verify the source code and write to ./artifacts

Verification:

- make verify-etherscan   Verify the last deployment on an Etherscan (compatible) explorer
- make verify-blockscout  Verify the last deployment on BlockScout
- make verify-sourcify    Verify the last deployment on Sourcify

- make refund             Refund the remaining balance left on the deployment account
```

### Initial set up

Create your `.env` file:

```sh
cp .env.example .env
```

Next, set the values of `.env` according to your environment.

Run `make init`:
- It ensures that the dependencies are installed
- It runs a first compilation of the project

## Core Functionality

### Streaming Payments 🌊

Create continuous token streams to contributors:

```solidity
// Stream 1000 USDC to @alice over 30 days
plugin.createStream("alice", 1000e6, USDC_ADDRESS, block.timestamp + 30 days);

// Recipients can claim their accrued tokens anytime
plugin.requestStreamPayout("alice");

// Cancel streams when needed
plugin.cancelStream("alice");
```

### Scheduled Payments 📅

Set up recurring payments for regular contributors:

```solidity
// Pay @bob 500 USDC monthly starting next week
plugin.createSchedule(
    "bob", 
    500e6, 
    USDC_ADDRESS, 
    IntervalType.MONTHLY, 
    false, // recurring
    block.timestamp + 7 days
);

// Recipients request payouts when due
plugin.requestSchedulePayout("bob");
```

### Username Management 👤

Contributors claim and manage their usernames:

```solidity
// Claim a username (one per address)
registry.claimUsername("alice");

// Update address while keeping same username
registry.updateUserAddress("alice", newAddress);

// DAOs resolve usernames to current addresses
address recipient = registry.getUserAddress("alice");
```

## Testing 🔍

PayNest includes comprehensive testing with both unit tests (mocked) and fork tests (real contracts).

### Test Commands

```bash
# Unit tests (fast, with mocks) - 115 tests
make test
forge test --match-path "./test/*.sol"

# Fork tests (real Base mainnet contracts) - 15 tests
make test-fork
forge test --match-contract "PaymentsPluginForkTest"

# All tests (unit + fork) - 130 tests
forge test

# Coverage report
make test-coverage
```

### Test Architecture

**Unit Tests (115 tests)**
- Mock LlamaPay contracts for fast, deterministic testing
- Mock USDC tokens with controlled behavior
- Real Aragon DAO contracts using SimpleBuilder
- Purpose: Fast development, edge cases, gas optimization

**Fork Tests (15 tests)**
- **Zero mocking** - 100% real contracts on Base mainnet
- Real USDC: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`
- Real LlamaPay: `0x09c39B8311e4B7c678cBDAD76556877ecD3aEa07`
- Real USDC whale: `0x0B0A5886664376F59C351ba3f598C8A8B4D0A6f3`
- Purpose: Production-ready integration testing

All tests use Bulloak for structured test scaffolding from YAML specifications.

### Writing tests

Optionally, test hierarchies can be described using yaml files like [ProtocolFactory.t.yaml](./test/ProtocolFactory.t.yaml), which will be transformed into solidity files by running `make sync-tests`, thanks to [bulloak](https://github.com/alexfertel/bulloak).

Create a file with `.t.yaml` extension within the `test` folder and describe a hierarchy as follows:

```yaml
# MyTest.t.yaml

MyContractTest:
- given: proposal exists
  comment: Comment here
  and:
  - given: proposal is in the last stage
    and:

    - when: proposal can advance
      then:
      - it: Should return true

    - when: proposal cannot advance
      then:
      - it: Should return false

  - when: proposal is not in the last stage
    then:
    - it: should do A
      comment: This is an important remark
    - it: should do B
    - it: should do C

- when: proposal doesn't exist
  comment: Testing edge cases here
  then:
  - it: should revert
```

Then use `make` to automatically sync the described branches into solidity test files.

```sh
$ make
Testing lifecycle:
# ...
- make sync-tests       Scaffold or sync tree files into solidity tests
- make check-tests      Checks if solidity files are out of sync
- make markdown-tests   Generates a markdown file with the test definitions rendered as a tree

$ make sync-tests
```

Each yaml file will generate (or sync) a solidity test file with functions ready to be implemented. It will also generate a human readable summary in [TESTS.md](./TESTS.md) file.

### Testing with a local OSx

You can deploy an in-memory, local OSx deployment to run your E2E tests on top of.

```sh
forge install aragon/protocol-factory
```

You may need to set `via_ir` to `true` on `foundry.toml`.

Given that this repository already depends on OSx, you may want to replace the existing `remappings.txt` entry and use the OSx path provided by `protocol-factory` itself.

```diff
-@aragon/osx/=lib/osx/packages/contracts/src/

+@aragon/protocol-factory/=lib/protocol-factory/
+@aragon/osx/=lib/protocol-factory/lib/osx/packages/contracts/src/
```

Then, use the protocol factory to deploy OSx and use them as you need.

```solidity
// Set the path according to your remappings.txt file
import {ProtocolFactoryBuilder} from "@aragon/protocol-factory/test/helpers/ProtocolFactoryBuilder.sol";

// Prepare an OSx factory
ProtocolFactory factory = new ProtocolFactoryBuilder().build();
factory.deployOnce();

// Get the protocol addresses
ProtocolFactory.Deployment memory deployment = factory.getDeployment();
console.log("DaoFactory", deployment.daoFactory);
```

You can even [customize your local OSx test environment](https://github.com/aragon/protocol-factory?tab=readme-ov-file#if-you-need-to-override-some-parameters) if needed.

## Installation for DAOs

PayNest can be installed on any Aragon DAO through the standard plugin installation process:

### Prerequisites
- Registry address: `0x...` (deployed globally per network)
- LlamaPay factory: `0xde1C04855c2828431ba637675B6929A684f84C7` (all networks)
- Manager address: Who can create/manage payments in your DAO

### Installation Steps
1. Navigate to your DAO in the Aragon App
2. Go to Settings → Plugins → Browse Plugins
3. Search for "PayNest" and click Install
4. Configure installation parameters:
   - Manager address (typically DAO multisig or governance)
   - Registry address for your network
   - LlamaPay factory address
5. Approve the installation proposal
6. Once installed, the plugin will appear in your DAO sidebar

## Deployment 🚀

For developers deploying the plugin infrastructure:

```bash
# Simulate deployment
make predeploy

# Deploy to network
make deploy

# Verify contracts on explorers
make verify-etherscan
```

### Deployment Checklist

- [ ] I have cloned the official repository on my computer and I have checked out the `main` branch
- [ ] I am using the latest official docker engine, running a Debian Linux (stable) image
  - [ ] I have run `docker run --rm -it -v .:/deployment debian:bookworm-slim`
  - [ ] I have run `apt update && apt install -y make curl git vim neovim bc`
  - [ ] I have run `curl -L https://foundry.paradigm.xyz | bash`
  - [ ] I have run `source /root/.bashrc && foundryup`
  - [ ] I have run `cd /deployment`
  - [ ] I have run `cp .env.example .env`
  - [ ] I have run `make init`
- [ ] I am opening an editor on the `/deployment` folder, within the Docker container
- [ ] The `.env` file contains the correct parameters for the deployment
  - [ ] I have created a new burner wallet with `cast wallet new` and copied the private key to `DEPLOYMENT_PRIVATE_KEY` within `.env`
  - [ ] I have set the correct `RPC_URL` for the network
  - [ ] I have set the correct `CHAIN_ID` for the network
  - [ ] The value of `NETWORK_NAME` is listed within `constants.mk`, at the appropriate place
  - [ ] I have set `ETHERSCAN_API_KEY` or `BLOCKSCOUT_HOST_NAME` (when relevant to the target network)
  - [ ] (TO DO: Add a step to check your own variables here)
  - [ ] I have printed the contents of `.env` to the screen
  - [ ] I am the only person of the ceremony that will operate the deployment wallet
- [ ] All the tests run clean (`make test`)
- My computer:
  - [ ] Is running in a safe location and using a trusted network
  - [ ] It exposes no services or ports
    - MacOS: `sudo lsof -iTCP -sTCP:LISTEN -nP`
    - Linux: `netstat -tulpn`
    - Windows: `netstat -nao -p tcp`
  - [ ] The wifi or wired network in use does not expose any ports to a WAN
- [ ] I have run `make predeploy` and the simulation completes with no errors
- [ ] The deployment wallet has sufficient native token for gas
  - At least, 15% more than the amount estimated during the simulation
- [ ] `make test` still runs clean
- [ ] I have run `git status` and it reports no local changes
- [ ] The current local git branch (`main`) corresponds to its counterpart on `origin`
  - [ ] I confirm that the rest of members of the ceremony pulled the last git commit on `main` and reported the same commit hash as my output for `git log -n 1`
- [ ] I have initiated the production deployment with `make deploy`

### Post deployment checklist

- [ ] The deployment process completed with no errors
- [ ] The factory contract was deployed by the deployment address
- [ ] All the project's smart contracts are correctly verified on the reference block explorer of the target network.
- [ ] The output of the latest `logs/deployment-<network>-<date>.log` file corresponds to the console output
- [ ] A file called `artifacts/addresses-<network>-<timestamp>.json` has been created, and the addresses match those logged to the screen
- [ ] I have uploaded the following files to a shared location:
  - `logs/deployment-<network>.log` (the last one)
  - `artifacts/addresses-<network>-<timestamp>.json`  (the last one)
  - `broadcast/Deploy.s.sol/<chain-id>/run-<timestamp>.json` (the last one)
- [ ] The rest of members confirm that the values are correct
- [ ] I have transferred the remaining funds of the deployment wallet to the address that originally funded it
  - `make refund`

This concludes the deployment ceremony.

## Contract source verification

When running a deployment with `make deploy`, Foundry will attempt to verify the contracts on the corresponding block explorer.

If you need to verify on multiple explorers or the automatic verification did not work, you have three `make` targets available:

```
$ make
[...]
Verification:

- make verify-etherscan   Verify the last deployment on an Etherscan (compatible) explorer
- make verify-blockscout  Verify the last deployment on BlockScout
- make verify-sourcify    Verify the last deployment on Sourcify
```

These targets use the last deployment data under `broadcast/Deploy.s.sol/<chain-id>/run-latest.json`.
- Ensure that the required variables are set within the `.env` file.
- Ensure that `NETWORK_NAME` is listed on the right section under `constants.mk`, according to the block explorer that you want to target

This flow will attempt to verify all the contracts in one go, but yo umay still need to issue additional manual verifications, depending on the circumstances.

### Routescan verification (manual)

```sh
$ forge verify-contract <address> <path/to/file.sol>:<contract-name> --verifier-url 'https://api.routescan.io/v2/network/<testnet|mainnet>/evm/<chain-id>/etherscan' --etherscan-api-key "verifyContract" --num-of-optimizations 200 --compiler-version 0.8.28 --constructor-args <args>
```

Where:
- `<address>` is the address of the contract to verify
- `<path/to/file.sol>:<contract-name>` is the path of the source file along with the contract name
- `<testnet|mainnet>` the type of network
- `<chain-id>` the ID of the chain
- `<args>` the constructor arguments
  - Get them with `$(cast abi-encode "constructor(address param1, uint256 param2,...)" param1 param2 ...)`

## Security 🔒

If you believe you've found a security issue, we encourage you to notify us. We welcome working with you to resolve the issue promptly.

Security Contact Email: sirt@aragon.org

Please do not use the public issue tracker to report security issues.

## Benefits for DAOs

### For DAO Contributors
- **Simplified Onboarding**: No need to share wallet addresses - just claim a username
- **Flexible Payments**: Receive streams or scheduled payments based on contribution type
- **Self-Service**: Claim payments when convenient without waiting for manual processing
- **Address Flexibility**: Update wallet address while keeping the same username

### For DAO Treasurers
- **Automated Payments**: Set up recurring payments that execute automatically
- **Gas Efficiency**: Leverage LlamaPay's optimized streaming for significant gas savings
- **Multi-Token Support**: Stream any ERC-20 token with proper decimal handling
- **Transparent Tracking**: All payments are on-chain and auditable

### For DAO Operations
- **Reduced Admin Overhead**: Automate regular contributor payments
- **Improved Cash Flow**: Stream payments reduce large lump-sum treasury outflows
- **Better Budgeting**: Predictable payment schedules aid in treasury planning
- **Enhanced Security**: Aragon's permission system ensures only authorized payments

## Documentation

- [Payments Plugin Specification](./docs/payments-plugin-spec.md) - Complete technical specification
- [LlamaPay Integration](./docs/llamapay-integration-spec.md) - Integration details and patterns
- [Address Registry](./docs/address-registry-spec.md) - Username system documentation
- [Testing Strategy](./docs/testing-strategy.md) - Comprehensive testing approach

## Contributing 🤝

Contributions are welcome! Please read our contributing guidelines and check the specifications in the `docs/` folder for implementation details.

## License 📄

This project is licensed under AGPL-3.0-or-later.

## Support 💬

For support, open an issue in this repository or reach out through Aragon's community channels.
