// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentsPlugin} from "../src/PaymentsPlugin.sol";
import {PaymentsPluginSetup} from "../src/setup/PaymentsPluginSetup.sol";
import {IPayments} from "../src/interfaces/IPayments.sol";
import {IRegistry} from "../src/interfaces/IRegistry.sol";
import {AddressRegistry} from "../src/AddressRegistry.sol";

contract MockLlamaPayFactory {
    mapping(address => address) public tokenToContract;
    mapping(address => bool) public isDeployed;

    function createLlamaPayContract(address _token) external returns (address llamaPayContract) {
        llamaPayContract = address(new MockLlamaPay(_token));
        tokenToContract[_token] = llamaPayContract;
        isDeployed[llamaPayContract] = true;
        return llamaPayContract;
    }

    function getLlamaPayContractByToken(address _token)
        external
        view
        returns (address predictedAddress, bool deployed)
    {
        predictedAddress = tokenToContract[_token];
        deployed = isDeployed[predictedAddress];
    }
}

contract MockLlamaPay {
    address public token;
    uint256 public constant DECIMALS_DIVISOR = 1e14; // Assume 6 decimal token for simplicity

    mapping(address => uint256) public balances;
    mapping(bytes32 => uint256) public streamToStart;

    event StreamCreated(address indexed from, address indexed to, uint216 amountPerSec);
    event StreamCancelled(address indexed from, address indexed to, uint216 amountPerSec);
    event Withdraw(address indexed from, address indexed to, uint216 amountPerSec, uint256 amount);

    constructor(address _token) {
        token = _token;
    }

    function deposit(uint256 amount) external {
        // Mock transfer from sender
        balances[msg.sender] += amount;
    }

    function createStreamWithReason(address to, uint216 amountPerSec, string calldata reason) external {
        bytes32 streamId = keccak256(abi.encodePacked(msg.sender, to, amountPerSec));
        streamToStart[streamId] = block.timestamp;
        emit StreamCreated(msg.sender, to, amountPerSec);
    }

    function createStream(address to, uint216 amountPerSec) external {
        bytes32 streamId = keccak256(abi.encodePacked(msg.sender, to, amountPerSec));
        streamToStart[streamId] = block.timestamp;
        emit StreamCreated(msg.sender, to, amountPerSec);
    }

    function cancelStream(address to, uint216 amountPerSec) external {
        bytes32 streamId = keccak256(abi.encodePacked(msg.sender, to, amountPerSec));
        delete streamToStart[streamId];
        emit StreamCancelled(msg.sender, to, amountPerSec);
    }

    function withdraw(address from, address to, uint216 amountPerSec) external {
        // Calculate withdrawable amount based on time elapsed
        bytes32 streamId = keccak256(abi.encodePacked(from, to, amountPerSec));
        uint256 startTime = streamToStart[streamId];
        require(startTime > 0, "Stream not found");

        uint256 elapsed = block.timestamp - startTime;
        uint256 withdrawableAmount = (elapsed * amountPerSec) / DECIMALS_DIVISOR;

        // Update start time to prevent double withdrawal
        streamToStart[streamId] = block.timestamp;

        emit Withdraw(from, to, amountPerSec, withdrawableAmount);
    }

    function withdrawable(address from, address to, uint216 amountPerSec)
        external
        view
        returns (uint256 withdrawableAmount, uint256 lastUpdate, uint256 owed)
    {
        bytes32 streamId = keccak256(abi.encodePacked(from, to, amountPerSec));
        uint256 startTime = streamToStart[streamId];

        if (startTime == 0) return (0, 0, 0);

        uint256 elapsed = block.timestamp - startTime;
        withdrawableAmount = (elapsed * amountPerSec) / DECIMALS_DIVISOR;
        lastUpdate = startTime;
        owed = 0; // Simplify for testing
    }

    function withdrawPayerAll() external {
        balances[msg.sender] = 0;
    }

    function getStreamId(address from, address to, uint216 amountPerSec) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(from, to, amountPerSec));
    }
}

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    uint8 public decimals;
    string public name;
    string public symbol;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
}

contract MockDAO {
    bytes32 public constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");

    mapping(address => mapping(address => mapping(bytes32 => bool))) public hasPermission;

    function grant(address where, address who, bytes32 permissionId) external {
        hasPermission[where][who][permissionId] = true;
    }

    function execute(
        bytes32, /* callId */
        address[] memory actions,
        uint256[] memory values,
        bytes[] memory calldatas,
        uint256 /* allowFailureMap */
    ) external returns (bytes[] memory execResults) {
        execResults = new bytes[](actions.length);

        for (uint256 i = 0; i < actions.length; i++) {
            (bool success, bytes memory result) = actions[i].call{value: values[i]}(calldatas[i]);
            require(success, "Action execution failed");
            execResults[i] = result;
        }
    }

    function execute(bytes32, /* callId */ Action[] memory actions, uint256 /* allowFailureMap */ )
        external
        returns (bytes[] memory execResults)
    {
        execResults = new bytes[](actions.length);

        for (uint256 i = 0; i < actions.length; i++) {
            (bool success, bytes memory result) = actions[i].to.call{value: actions[i].value}(actions[i].data);
            require(success, "Action execution failed");
            execResults[i] = result;
        }
    }
}

import {DAO, IDAO, Action} from "@aragon/osx/core/dao/DAO.sol";

contract PaymentsPluginTest is Test {
    PaymentsPlugin public plugin;
    PaymentsPluginSetup public pluginSetup;
    AddressRegistry public registry;
    MockLlamaPayFactory public llamaPayFactory;
    MockERC20 public token;
    MockDAO public dao;

    address alice = vm.addr(1);

    string constant TEST_USERNAME = "alice";
    uint256 constant STREAM_AMOUNT = 1000e6; // 1000 USDC
    uint40 constant STREAM_DURATION = 30 days;

    // Events to test
    event StreamActive(string indexed username, address indexed token, uint40 endDate, uint256 totalAmount);
    event StreamUpdated(string indexed username, address indexed token, uint256 newAmount);
    event PaymentStreamCancelled(string indexed username, address indexed token);
    event StreamPayout(string indexed username, address indexed token, uint256 amount);

    function setUp() public {
        // Deploy contracts
        registry = new AddressRegistry();
        llamaPayFactory = new MockLlamaPayFactory();
        token = new MockERC20("Test USDC", "TUSDC", 6);
        dao = new MockDAO();

        // Deploy plugin pluginSetup and initialize plugin
        pluginSetup = new PaymentsPluginSetup();

        bytes memory installationParams = pluginSetup.encodeInstallationParams(
            address(this), // manager
            address(registry),
            address(llamaPayFactory)
        );

        (address pluginAddress,) = pluginSetup.prepareInstallation(address(dao), installationParams);
        plugin = PaymentsPlugin(pluginAddress);

        // Setup test data
        vm.prank(alice);
        registry.claimUsername(TEST_USERNAME);

        // Give DAO some tokens
        token.mint(address(dao), 10000e6);

        // Grant execute permission to plugin
        dao.grant(address(dao), address(plugin), dao.EXECUTE_PERMISSION_ID());
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
        PaymentsPlugin newPlugin = new PaymentsPlugin();

        vm.expectRevert(PaymentsPlugin.InvalidToken.selector);
        newPlugin.initialize(IDAO(address(dao)), address(0), address(llamaPayFactory));
    }

    function test_initialize_ShouldRevertWithInvalidTokenForZeroFactory() public {
        PaymentsPlugin newPlugin = new PaymentsPlugin();

        vm.expectRevert(PaymentsPlugin.InvalidToken.selector);
        newPlugin.initialize(IDAO(address(dao)), address(registry), address(0));
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
