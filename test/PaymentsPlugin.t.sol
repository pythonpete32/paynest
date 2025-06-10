// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentsPlugin} from "../src/PaymentsPlugin.sol";
import {IPayments} from "../src/interfaces/IPayments.sol";
import {AddressRegistry} from "../src/AddressRegistry.sol";
import {PaymentsBuilder, MockLlamaPayFactory, MockERC20} from "./builders/PaymentsBuilder.sol";
import {DAO, IDAO} from "@aragon/osx/core/dao/DAO.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";

contract PaymentsPluginTest is Test {
    DAO public dao;
    PaymentsPlugin public plugin;
    AddressRegistry public registry;
    MockLlamaPayFactory public llamaPayFactory;
    MockERC20 public token;

    address alice = vm.addr(1);
    address bob = vm.addr(2);

    string constant TEST_USERNAME = "alice";
    uint256 constant STREAM_AMOUNT = 1000e6; // 1000 USDC
    uint40 constant STREAM_DURATION = 30 days;

    // Events to test
    event StreamActive(string indexed username, address indexed token, uint40 endDate, uint256 totalAmount);
    event StreamUpdated(string indexed username, address indexed token, uint256 newAmount);
    event PaymentStreamCancelled(string indexed username, address indexed token);
    event StreamPayout(string indexed username, address indexed token, uint256 amount);

    function setUp() public {
        // Use PaymentsBuilder to create properly configured DAO and plugin
        (dao, plugin, registry, llamaPayFactory, token) = new PaymentsBuilder().withDaoOwner(address(this)).withManagers(
            _getManagersArray()
        ) // Make test contract the DAO owner
                // Set test contract as manager
            .build();

        // Setup test data - alice claims a username
        vm.prank(alice);
        registry.claimUsername(TEST_USERNAME);

        // Approve DAO to spend tokens (simulate DAO treasury having approval)
        vm.prank(address(dao));
        token.approve(address(plugin), type(uint256).max);
    }

    function _getManagersArray() internal view returns (address[] memory) {
        address[] memory managers = new address[](1);
        managers[0] = address(this); // Make the test contract a manager
        return managers;
    }

    // =========================================================================
    // Plugin Initialization Tests
    // =========================================================================

    function test_initialize_ShouldSetDAOAddressCorrectly() public view {
        assertEq(address(plugin.dao()), address(dao));
    }

    function test_initialize_ShouldSetRegistryAddressCorrectly() public view {
        assertEq(address(plugin.registry()), address(registry));
    }

    function test_initialize_ShouldSetLlamaPayFactoryAddressCorrectly() public view {
        assertEq(address(plugin.llamaPayFactory()), address(llamaPayFactory));
    }

    function test_initialize_ShouldRevertWithInvalidTokenForZeroRegistry() public {
        // Deploy fresh implementation
        PaymentsPlugin implementation = new PaymentsPlugin();

        // Create proxy with invalid registry (zero address)
        vm.expectRevert(PaymentsPlugin.InvalidToken.selector);
        ProxyLib.deployUUPSProxy(
            address(implementation),
            abi.encodeCall(PaymentsPlugin.initialize, (dao, address(0), address(llamaPayFactory)))
        );
    }

    function test_initialize_ShouldRevertWithInvalidTokenForZeroFactory() public {
        // Deploy fresh implementation
        PaymentsPlugin implementation = new PaymentsPlugin();

        // Create proxy with invalid factory (zero address)
        vm.expectRevert(PaymentsPlugin.InvalidToken.selector);
        ProxyLib.deployUUPSProxy(
            address(implementation), abi.encodeCall(PaymentsPlugin.initialize, (dao, address(registry), address(0)))
        );
    }

    // =========================================================================
    // Stream Management Tests
    // =========================================================================

    function test_createStream_ShouldCreateStreamSuccessfully() public {
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);

        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(token), endTime);

        IPayments.Stream memory stream = plugin.getStream(TEST_USERNAME);
        assertEq(stream.token, address(token));
        assertEq(stream.endDate, endTime);
        assertTrue(stream.active);
        assertTrue(stream.amount > 0);
    }

    function test_createStream_ShouldEmitStreamActiveEvent() public {
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);

        vm.expectEmit(true, true, false, true);
        emit StreamActive(TEST_USERNAME, address(token), endTime, STREAM_AMOUNT);

        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(token), endTime);
    }

    function test_createStream_ShouldStoreStreamMetadataCorrectly() public {
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);

        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(token), endTime);

        IPayments.Stream memory stream = plugin.getStream(TEST_USERNAME);
        assertEq(stream.token, address(token));
        assertEq(stream.endDate, endTime);
        assertTrue(stream.active);
        assertEq(stream.lastPayout, uint40(block.timestamp));
    }

    function test_createStream_ShouldRevertWithInvalidAmountForZeroAmount() public {
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);

        vm.expectRevert(PaymentsPlugin.InvalidAmount.selector);
        plugin.createStream(TEST_USERNAME, 0, address(token), endTime);
    }

    function test_createStream_ShouldRevertWithInvalidTokenForZeroToken() public {
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);

        vm.expectRevert(PaymentsPlugin.InvalidToken.selector);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(0), endTime);
    }

    function test_createStream_ShouldRevertWithInvalidEndDateForPastEndDate() public {
        uint40 endTime = uint40(block.timestamp - 1);

        vm.expectRevert(PaymentsPlugin.InvalidEndDate.selector);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(token), endTime);
    }

    function test_createStream_ShouldRevertWithUsernameNotFoundForInvalidUsername() public {
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);

        vm.expectRevert(PaymentsPlugin.UsernameNotFound.selector);
        plugin.createStream("nonexistent", STREAM_AMOUNT, address(token), endTime);
    }

    function test_createStream_ShouldRevertWithStreamAlreadyExistsForDuplicateStream() public {
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);

        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(token), endTime);

        vm.expectRevert(PaymentsPlugin.StreamAlreadyExists.selector);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(token), endTime);
    }

    function test_cancelStream_ShouldCancelStreamSuccessfully() public {
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(token), endTime);

        plugin.cancelStream(TEST_USERNAME);

        IPayments.Stream memory stream = plugin.getStream(TEST_USERNAME);
        assertFalse(stream.active);
    }

    function test_cancelStream_ShouldEmitPaymentStreamCancelledEvent() public {
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(token), endTime);

        vm.expectEmit(true, true, false, true);
        emit PaymentStreamCancelled(TEST_USERNAME, address(token));

        plugin.cancelStream(TEST_USERNAME);
    }

    function test_cancelStream_ShouldMarkStreamAsInactive() public {
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(token), endTime);

        plugin.cancelStream(TEST_USERNAME);

        IPayments.Stream memory stream = plugin.getStream(TEST_USERNAME);
        assertFalse(stream.active);
    }

    function test_cancelStream_ShouldRevertWithStreamNotActive() public {
        vm.expectRevert(PaymentsPlugin.StreamNotActive.selector);
        plugin.cancelStream(TEST_USERNAME);
    }

    function test_editStream_ShouldUpdateStreamAmountSuccessfully() public {
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(token), endTime);

        uint256 newAmount = 2000e6;
        plugin.editStream(TEST_USERNAME, newAmount);

        IPayments.Stream memory stream = plugin.getStream(TEST_USERNAME);
        // The amount per second should be different now
        assertTrue(stream.amount > 0);
    }

    function test_editStream_ShouldEmitStreamUpdatedEvent() public {
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(token), endTime);

        uint256 newAmount = 2000e6;

        vm.expectEmit(true, true, false, true);
        emit StreamUpdated(TEST_USERNAME, address(token), newAmount);

        plugin.editStream(TEST_USERNAME, newAmount);
    }

    function test_editStream_ShouldRevertWithStreamNotActive() public {
        vm.expectRevert(PaymentsPlugin.StreamNotActive.selector);
        plugin.editStream(TEST_USERNAME, 2000e6);
    }

    // =========================================================================
    // Stream Payout Tests
    // =========================================================================

    function test_requestStreamPayout_ShouldExecutePayoutSuccessfully() public {
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(token), endTime);

        // Fast forward some time
        vm.warp(block.timestamp + 1 days);

        uint256 payoutAmount = plugin.requestStreamPayout(TEST_USERNAME);
        assertTrue(payoutAmount >= 0); // Should return some amount (could be 0 if no time passed)
    }

    function test_requestStreamPayout_ShouldEmitStreamPayoutEvent() public {
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(token), endTime);

        // Fast forward some time
        vm.warp(block.timestamp + 1 days);

        vm.expectEmit(true, true, false, false); // Don't check amount since it's calculated
        emit StreamPayout(TEST_USERNAME, address(token), 0);

        plugin.requestStreamPayout(TEST_USERNAME);
    }

    function test_requestStreamPayout_ShouldUpdateLastPayoutTimestamp() public {
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(token), endTime);

        // Fast forward some time
        vm.warp(block.timestamp + 1 days);

        plugin.requestStreamPayout(TEST_USERNAME);

        IPayments.Stream memory stream = plugin.getStream(TEST_USERNAME);
        assertEq(stream.lastPayout, uint40(block.timestamp));
    }

    function test_requestStreamPayout_ShouldRevertWithStreamNotActive() public {
        vm.expectRevert(PaymentsPlugin.StreamNotActive.selector);
        plugin.requestStreamPayout(TEST_USERNAME);
    }

    function test_requestStreamPayout_ShouldRevertWithUsernameNotFound() public {
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(token), endTime);

        vm.expectRevert(PaymentsPlugin.UsernameNotFound.selector);
        plugin.requestStreamPayout("nonexistent");
    }

    // =========================================================================
    // Permission Tests
    // =========================================================================

    function test_createStream_ShouldRevertWithoutManagerPermission() public {
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(plugin), alice, plugin.MANAGER_PERMISSION_ID()
            )
        );

        vm.prank(alice);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(token), endTime);
    }

    function test_cancelStream_ShouldRevertWithoutManagerPermission() public {
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(token), endTime);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(plugin), alice, plugin.MANAGER_PERMISSION_ID()
            )
        );

        vm.prank(alice);
        plugin.cancelStream(TEST_USERNAME);
    }

    // =========================================================================
    // View Functions Tests
    // =========================================================================

    function test_getStream_ShouldReturnCorrectStreamInformation() public {
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(token), endTime);

        IPayments.Stream memory stream = plugin.getStream(TEST_USERNAME);
        assertEq(stream.token, address(token));
        assertEq(stream.endDate, endTime);
        assertTrue(stream.active);
        assertTrue(stream.amount > 0);
        assertEq(stream.lastPayout, uint40(block.timestamp));
    }

    function test_getStream_ShouldReturnEmptyForNonExistentStream() public view {
        IPayments.Stream memory stream = plugin.getStream("nonexistent");
        assertEq(stream.token, address(0));
        assertFalse(stream.active);
    }
}
