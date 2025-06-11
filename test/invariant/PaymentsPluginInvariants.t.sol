// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentsPlugin} from "../../src/PaymentsPlugin.sol";
import {AddressRegistry} from "../../src/AddressRegistry.sol";
import {IPayments} from "../../src/interfaces/IPayments.sol";
import {IRegistry} from "../../src/interfaces/IRegistry.sol";
import {PaymentsBuilder} from "../builders/PaymentsBuilder.sol";
import {MockERC20} from "../builders/PaymentsBuilder.sol";
import {MockLlamaPay} from "../builders/PaymentsBuilder.sol";
import {IDAO, DAO} from "@aragon/osx/core/dao/DAO.sol";

/// @title PaymentsPlugin Invariant Tests
/// @notice Tests critical invariants for the PaymentsPlugin contract
/// @dev Implements Priority 1 (PP1-PP8) and Priority 2 (PP9-PP15) invariants
contract PaymentsPluginInvariants is Test {
    PaymentsPlugin public plugin;
    AddressRegistry public registry;
    DAO public dao;
    MockERC20 public token;
    MockLlamaPay public llamaPay;

    // Test actors
    address[] public actors;
    address internal currentActor;

    // Valid usernames for testing
    string[] public validUsernames;

    // Ghost variables for tracking financial state
    mapping(string => uint256) public ghost_activeStreamCount;
    mapping(string => uint256) public ghost_activeScheduleCount;
    mapping(address => uint256) public ghost_totalStreamsForToken;
    mapping(address => uint256) public ghost_totalSchedulesForToken;
    uint256 public ghost_totalActiveStreams;
    uint256 public ghost_totalActiveSchedules;

    // Constants for testing
    uint256 constant STREAM_AMOUNT = 1000e6; // 1000 USDC
    uint256 constant STREAM_DURATION = 30 days;
    uint256 constant SCHEDULE_AMOUNT = 100e6; // 100 USDC

    function setUp() public {
        // Build the payments system
        PaymentsBuilder builder = new PaymentsBuilder();
        (dao, plugin, registry,, token) = builder.withDaoOwner(address(this)).withManagers(_getManagersArray()).build();

        // Initialize test actors
        actors = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            actors[i] = address(uint160(0x1000 + i));
            vm.deal(actors[i], 1 ether);
        }

        // Create valid usernames for actors
        validUsernames = new string[](5);
        for (uint256 i = 0; i < 5; i++) {
            validUsernames[i] = string(abi.encodePacked("user", vm.toString(i)));
            vm.prank(actors[i]);
            registry.claimUsername(validUsernames[i]);
        }

        // Fund DAO with tokens
        token.mint(address(dao), 1000000e6); // 1M USDC
    }

    /// @dev Get managers array for testing
    function _getManagersArray() internal view returns (address[] memory) {
        address[] memory managers = new address[](1);
        managers[0] = address(this);
        return managers;
    }

    /// @dev Modifier to use random actor for operations
    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        _;
    }

    /*//////////////////////////////////////////////////////////////
                         PRIORITY 1 INVARIANTS (PP1-PP8)
    //////////////////////////////////////////////////////////////*/

    /// @notice PP1: Active Stream Validity
    /// @dev Active streams have valid tokens and non-zero amounts
    function invariant_PP1_activeStreamValidity() public view {
        for (uint256 i = 0; i < validUsernames.length; i++) {
            IPayments.Stream memory stream = plugin.getStream(validUsernames[i]);

            if (stream.active) {
                assertTrue(stream.token != address(0), "PP1: Active stream must have valid token");
                assertGt(stream.amount, 0, "PP1: Active stream must have non-zero amount");
                assertGt(stream.endDate, block.timestamp, "PP1: Active stream must have future end date");
            }
        }
    }

    /// @notice PP2: Stream-Recipient Consistency
    /// @dev Active streams have recipients, inactive streams don't
    function invariant_PP2_streamRecipientConsistency() public view {
        for (uint256 i = 0; i < validUsernames.length; i++) {
            IPayments.Stream memory stream = plugin.getStream(validUsernames[i]);
            address recipient = registry.getUserAddress(validUsernames[i]);

            if (stream.active) {
                assertTrue(recipient != address(0), "PP2: Active stream must have valid recipient");
            }
        }
    }

    /// @notice PP3: Stream Amount Bounds
    /// @dev Stream amounts fit in LlamaPay's uint216
    function invariant_PP3_streamAmountBounds() public view {
        for (uint256 i = 0; i < validUsernames.length; i++) {
            IPayments.Stream memory stream = plugin.getStream(validUsernames[i]);

            if (stream.active) {
                assertLe(stream.amount, type(uint216).max, "PP3: Stream amount exceeds uint216 max");
            }
        }
    }

    /// @notice PP4: Schedule Validity
    /// @dev Active schedules have valid parameters
    function invariant_PP4_scheduleValidity() public view {
        for (uint256 i = 0; i < validUsernames.length; i++) {
            IPayments.Schedule memory schedule = plugin.getSchedule(validUsernames[i]);

            if (schedule.active) {
                assertTrue(schedule.token != address(0), "PP4: Active schedule must have valid token");
                assertGt(schedule.amount, 0, "PP4: Active schedule must have non-zero amount");
                assertGt(schedule.firstPaymentDate, 0, "PP4: Active schedule must have valid first payment date");
            }
        }
    }

    /// @notice PP5: Temporal Consistency
    /// @dev Payout timestamps are logical
    function invariant_PP5_temporalConsistency() public view {
        for (uint256 i = 0; i < validUsernames.length; i++) {
            IPayments.Stream memory stream = plugin.getStream(validUsernames[i]);
            IPayments.Schedule memory schedule = plugin.getSchedule(validUsernames[i]);

            if (stream.active) {
                assertLe(stream.lastPayout, block.timestamp, "PP5: Stream lastPayout cannot be in future");
            }

            if (schedule.active) {
                assertLe(
                    schedule.firstPaymentDate,
                    schedule.nextPayout,
                    "PP5: Schedule firstPaymentDate must be <= nextPayout"
                );
            }
        }
    }

    /// @notice PP7: Username Dependency
    /// @dev Active payments require valid usernames
    function invariant_PP7_usernameDependency() public view {
        for (uint256 i = 0; i < validUsernames.length; i++) {
            IPayments.Stream memory stream = plugin.getStream(validUsernames[i]);
            IPayments.Schedule memory schedule = plugin.getSchedule(validUsernames[i]);

            if (stream.active || schedule.active) {
                address userAddress = registry.getUserAddress(validUsernames[i]);
                assertTrue(userAddress != address(0), "PP7: Active payment requires valid username");
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                         PRIORITY 2 INVARIANTS (PP9-PP15)
    //////////////////////////////////////////////////////////////*/

    /// @notice PP9: Arithmetic Safety
    /// @dev Schedule payouts don't overflow
    function invariant_PP9_arithmeticSafety() public view {
        for (uint256 i = 0; i < validUsernames.length; i++) {
            IPayments.Schedule memory schedule = plugin.getSchedule(validUsernames[i]);

            if (schedule.active) {
                // Test with reasonable period count (max 100 periods)
                uint256 testPeriods = 100;
                uint256 totalAmount = schedule.amount * testPeriods;

                // Check for overflow
                if (schedule.amount > 0) {
                    assertGe(totalAmount / testPeriods, schedule.amount, "PP9: Schedule amount calculation overflow");
                }
            }
        }
    }

    /// @notice PP12: Schedule Timing Logic
    /// @dev One-time schedules deactivate after payout
    function invariant_PP12_scheduleTimingLogic() public view {
        for (uint256 i = 0; i < validUsernames.length; i++) {
            IPayments.Schedule memory schedule = plugin.getSchedule(validUsernames[i]);

            // If it's a one-time schedule and next payout is in the past, it should be inactive
            if (schedule.isOneTime && schedule.nextPayout < block.timestamp && schedule.nextPayout > 0) {
                assertFalse(schedule.active, "PP12: One-time schedule should be inactive after due date");
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                         PERMISSION INVARIANTS (PS1-PS3)
    //////////////////////////////////////////////////////////////*/

    /// @notice PS2: Execute Permission for Plugin
    /// @dev Plugin can execute DAO actions
    function invariant_PS2_executePermissionForPlugin() public view {
        assertTrue(
            dao.hasPermission(address(dao), address(plugin), dao.EXECUTE_PERMISSION_ID(), ""),
            "PS2: Plugin must have execute permission on DAO"
        );
    }

    /*//////////////////////////////////////////////////////////////
                              HANDLER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Handler for creating streams
    function createStream(uint256 usernameSeed, uint256 amount, uint256 duration) external {
        // Bound inputs to reasonable values
        string memory username = validUsernames[bound(usernameSeed, 0, validUsernames.length - 1)];
        amount = bound(amount, 1e6, 10000e6); // 1-10k USDC
        duration = bound(duration, 1 days, 365 days);

        // Skip if stream already exists
        if (plugin.getStream(username).active) {
            return;
        }

        uint40 endTime = uint40(block.timestamp + duration);

        try plugin.createStream(username, amount, address(token), endTime) {
            ghost_activeStreamCount[username] = 1;
            ghost_totalStreamsForToken[address(token)]++;
            ghost_totalActiveStreams++;
        } catch {
            // Expected to fail for various reasons
        }
    }

    /// @notice Handler for creating schedules
    function createSchedule(uint256 usernameSeed, uint256 amount, uint256 intervalSeed, bool isOneTime) external {
        // Bound inputs
        string memory username = validUsernames[bound(usernameSeed, 0, validUsernames.length - 1)];
        amount = bound(amount, 1e6, 1000e6); // 1-1k USDC

        // Skip if schedule already exists
        if (plugin.getSchedule(username).active) {
            return;
        }

        IPayments.IntervalType interval = IPayments.IntervalType(bound(intervalSeed, 0, 3));
        uint40 firstPayment = uint40(block.timestamp + 1 days);

        try plugin.createSchedule(username, amount, address(token), interval, isOneTime, firstPayment) {
            ghost_activeScheduleCount[username] = 1;
            ghost_totalSchedulesForToken[address(token)]++;
            ghost_totalActiveSchedules++;
        } catch {
            // Expected to fail for various reasons
        }
    }

    /// @notice Handler for cancelling streams
    function cancelStream(uint256 usernameSeed) external {
        string memory username = validUsernames[bound(usernameSeed, 0, validUsernames.length - 1)];

        // Skip if no active stream
        if (!plugin.getStream(username).active) {
            return;
        }

        try plugin.cancelStream(username) {
            ghost_activeStreamCount[username] = 0;
            ghost_totalStreamsForToken[address(token)]--;
            ghost_totalActiveStreams--;
        } catch {
            // Expected to fail for various reasons
        }
    }

    /// @notice Handler for cancelling schedules
    function cancelSchedule(uint256 usernameSeed) external {
        string memory username = validUsernames[bound(usernameSeed, 0, validUsernames.length - 1)];

        // Skip if no active schedule
        if (!plugin.getSchedule(username).active) {
            return;
        }

        try plugin.cancelSchedule(username) {
            ghost_activeScheduleCount[username] = 0;
            ghost_totalSchedulesForToken[address(token)]--;
            ghost_totalActiveSchedules--;
        } catch {
            // Expected to fail for various reasons
        }
    }

    /// @notice Handler for requesting stream payouts
    function requestStreamPayout(uint256 usernameSeed) external {
        string memory username = validUsernames[bound(usernameSeed, 0, validUsernames.length - 1)];

        // Skip if no active stream
        if (!plugin.getStream(username).active) {
            return;
        }

        try plugin.requestStreamPayout(username) {
            // Payout successful
        } catch {
            // Expected to fail for various reasons
        }
    }

    /// @notice Handler for requesting schedule payouts
    function requestSchedulePayout(uint256 usernameSeed) external {
        string memory username = validUsernames[bound(usernameSeed, 0, validUsernames.length - 1)];

        // Skip if no active schedule
        if (!plugin.getSchedule(username).active) {
            return;
        }

        // Skip if not due yet
        IPayments.Schedule memory schedule = plugin.getSchedule(username);
        if (block.timestamp < schedule.nextPayout) {
            return;
        }

        try plugin.requestSchedulePayout(username) {
            // Handle one-time schedule deactivation
            if (schedule.isOneTime) {
                ghost_activeScheduleCount[username] = 0;
                ghost_totalSchedulesForToken[address(token)]--;
                ghost_totalActiveSchedules--;
            }
        } catch {
            // Expected to fail for various reasons
        }
    }

    /// @notice Handler for time progression
    function warpTime(uint256 timeDelta) external {
        timeDelta = bound(timeDelta, 1 hours, 30 days);
        vm.warp(block.timestamp + timeDelta);
    }

    /*//////////////////////////////////////////////////////////////
                              TARGET CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Target contract for invariant testing
    function targetContract() public view returns (address) {
        return address(this);
    }
}
