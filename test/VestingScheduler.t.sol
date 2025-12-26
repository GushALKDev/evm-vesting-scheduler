// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {VestingScheduler} from "../src/VestingScheduler.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/**
 * @title VestingSchedulerTest
 * @notice Comprehensive test suite for VestingScheduler contract
 */
contract VestingSchedulerTest is Test {
    VestingScheduler public vesting;
    MockERC20 public token;

    address public admin;
    address public beneficiary;
    address public nonAdmin;

    uint256 public constant TOTAL_AMOUNT = 1000 ether;
    uint64 public constant START_TIME = 1000;
    uint64 public constant CLIFF_DURATION = 100;
    uint64 public constant VESTING_DURATION = 1000;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ScheduleCreated(
        address indexed user,
        uint256 totalAmount,
        uint256 amountClaimed,
        uint64 startTime,
        uint64 cliffDuration,
        uint64 vestingDuration,
        bool initialized
    );

    event TokensReleased(address indexed user, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        admin = address(this);
        beneficiary = makeAddr("beneficiary");
        nonAdmin = makeAddr("nonAdmin");

        token = new MockERC20("Test Token", "TEST", 18);
        vesting = new VestingScheduler(address(token));

        // Mint tokens to admin and approve vesting contract
        token.mint(admin, 10_000 ether);
        token.approve(address(vesting), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor_SetsToken() public view {
        assertEq(address(vesting.TOKEN()), address(token));
    }

    function test_Constructor_SetsAdmin() public view {
        assertEq(vesting.ADMIN(), admin);
    }

    /*//////////////////////////////////////////////////////////////
                        CREATE SCHEDULE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CreateSchedule_RevertsWithAddressZero() public {
        vm.expectRevert(VestingScheduler.AddressZero.selector);
        vesting.createSchedule(address(0), TOTAL_AMOUNT, START_TIME, CLIFF_DURATION, VESTING_DURATION);
    }

    function test_CreateSchedule_RevertsWithZeroAmount() public {
        vm.expectRevert(VestingScheduler.ZeroAmount.selector);
        vesting.createSchedule(beneficiary, 0, START_TIME, CLIFF_DURATION, VESTING_DURATION);
    }

    function test_CreateSchedule_RevertsWithInvalidCliffDuration() public {
        vm.expectRevert(VestingScheduler.InvalidCliffDuration.selector);
        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME, VESTING_DURATION + 1, VESTING_DURATION);
    }

    function test_CreateSchedule_RevertsWithInvalidStartTime() public {
        vm.expectRevert(VestingScheduler.InvalidStartTime.selector);
        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, 0, CLIFF_DURATION, VESTING_DURATION);
    }

    function test_CreateSchedule_RevertsWithOnlyAdmin() public {
        vm.prank(nonAdmin);
        vm.expectRevert(VestingScheduler.OnlyAdmin.selector);
        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME, CLIFF_DURATION, VESTING_DURATION);
    }

    function test_CreateSchedule_RevertsWithScheduleAlreadyExists() public {
        // Create first schedule
        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME, CLIFF_DURATION, VESTING_DURATION);

        // Try to create another while first is not finished
        vm.expectRevert(VestingScheduler.ScheduleAlreadyExists.selector);
        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME + 1000, CLIFF_DURATION, VESTING_DURATION);
    }

    function test_CreateSchedule_Success() public {
        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME, CLIFF_DURATION, VESTING_DURATION);

        (
            uint256 totalAmount,
            uint256 amountClaimed,
            uint64 startTime,
            uint64 cliffDuration,
            uint64 vestingDuration,
            bool initialized
        ) = vesting.schedules(beneficiary);

        assertEq(totalAmount, TOTAL_AMOUNT);
        assertEq(amountClaimed, 0);
        assertEq(startTime, START_TIME);
        assertEq(cliffDuration, CLIFF_DURATION);
        assertEq(vestingDuration, VESTING_DURATION);
        assertTrue(initialized);
    }

    function test_CreateSchedule_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit ScheduleCreated(beneficiary, TOTAL_AMOUNT, 0, START_TIME, CLIFF_DURATION, VESTING_DURATION, true);

        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME, CLIFF_DURATION, VESTING_DURATION);
    }

    function test_CreateSchedule_TransfersTokens() public {
        uint256 adminBalanceBefore = token.balanceOf(admin);
        uint256 vestingBalanceBefore = token.balanceOf(address(vesting));

        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME, CLIFF_DURATION, VESTING_DURATION);

        assertEq(token.balanceOf(admin), adminBalanceBefore - TOTAL_AMOUNT);
        assertEq(token.balanceOf(address(vesting)), vestingBalanceBefore + TOTAL_AMOUNT);
    }

    function test_CreateSchedule_AllowsNewScheduleAfterFullyClaimed() public {
        // Create and fully claim first schedule
        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME, CLIFF_DURATION, VESTING_DURATION);

        // Warp to after vesting complete
        vm.warp(START_TIME + VESTING_DURATION + 1);

        // Claim all tokens
        vm.prank(beneficiary);
        vesting.release();

        // Should allow new schedule
        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME + 2000, CLIFF_DURATION, VESTING_DURATION);

        (uint256 totalAmount,,,,, bool initialized) = vesting.schedules(beneficiary);
        assertEq(totalAmount, TOTAL_AMOUNT);
        assertTrue(initialized);
    }

    /*//////////////////////////////////////////////////////////////
                            RELEASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Release_RevertsWithNoScheduleFound() public {
        vm.prank(beneficiary);
        vm.expectRevert(VestingScheduler.NoScheduleFound.selector);
        vesting.release();
    }

    function test_Release_RevertsBeforeStartTime() public {
        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME, CLIFF_DURATION, VESTING_DURATION);

        vm.warp(START_TIME - 1);
        vm.prank(beneficiary);
        vm.expectRevert(VestingScheduler.NothingToClaim.selector);
        vesting.release();
    }

    function test_Release_RevertsDuringCliff() public {
        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME, CLIFF_DURATION, VESTING_DURATION);

        // Warp to during cliff period (after start but before cliff ends)
        vm.warp(START_TIME + CLIFF_DURATION - 1);
        vm.prank(beneficiary);
        vm.expectRevert(VestingScheduler.NothingToClaim.selector);
        vesting.release();
    }

    function test_Release_SuccessAfterCliff() public {
        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME, CLIFF_DURATION, VESTING_DURATION);

        // Warp to just after cliff
        vm.warp(START_TIME + CLIFF_DURATION);

        uint256 expectedAmount = (TOTAL_AMOUNT * CLIFF_DURATION) / VESTING_DURATION;

        vm.prank(beneficiary);
        vesting.release();

        assertEq(token.balanceOf(beneficiary), expectedAmount);
    }

    function test_Release_ProportionalAmountMidVesting() public {
        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME, CLIFF_DURATION, VESTING_DURATION);

        // Warp to 50% of vesting
        uint64 halfVesting = VESTING_DURATION / 2;
        vm.warp(START_TIME + halfVesting);

        uint256 expectedAmount = (TOTAL_AMOUNT * halfVesting) / VESTING_DURATION;

        vm.prank(beneficiary);
        vesting.release();

        assertEq(token.balanceOf(beneficiary), expectedAmount);
    }

    function test_Release_AllRemainingAfterVestingComplete() public {
        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME, CLIFF_DURATION, VESTING_DURATION);

        // Warp to after vesting complete
        vm.warp(START_TIME + VESTING_DURATION + 1);

        vm.prank(beneficiary);
        vesting.release();

        assertEq(token.balanceOf(beneficiary), TOTAL_AMOUNT);
    }

    function test_Release_RevertsWhenAlreadyClaimedAll() public {
        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME, CLIFF_DURATION, VESTING_DURATION);

        // Warp to after vesting complete and claim all
        vm.warp(START_TIME + VESTING_DURATION + 1);
        vm.prank(beneficiary);
        vesting.release();

        // Try to claim again
        vm.prank(beneficiary);
        vm.expectRevert(VestingScheduler.NothingToClaim.selector);
        vesting.release();
    }

    function test_Release_EmitsEvent() public {
        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME, CLIFF_DURATION, VESTING_DURATION);

        vm.warp(START_TIME + VESTING_DURATION);

        vm.expectEmit(true, false, false, true);
        emit TokensReleased(beneficiary, TOTAL_AMOUNT);

        vm.prank(beneficiary);
        vesting.release();
    }

    /*//////////////////////////////////////////////////////////////
                          GET SCHEDULE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetSchedule_ReturnsCorrectData() public {
        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME, CLIFF_DURATION, VESTING_DURATION);

        VestingScheduler.VestingSchedule memory schedule = vesting.getSchedule(beneficiary);

        assertEq(schedule.totalAmount, TOTAL_AMOUNT);
        assertEq(schedule.amountClaimed, 0);
        assertEq(schedule.startTime, START_TIME);
        assertEq(schedule.cliffDuration, CLIFF_DURATION);
        assertEq(schedule.vestingDuration, VESTING_DURATION);
        assertTrue(schedule.initialized);
    }

    function test_GetSchedule_RevertsWithOnlyAdmin() public {
        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME, CLIFF_DURATION, VESTING_DURATION);

        vm.prank(nonAdmin);
        vm.expectRevert(VestingScheduler.OnlyAdmin.selector);
        vesting.getSchedule(beneficiary);
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CreateSchedule_WithZeroCliff() public {
        // Create schedule with no cliff period
        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME, 0, VESTING_DURATION);

        // At exactly start time, elapsed=0, so tokensToRelease=0, should revert
        vm.warp(START_TIME);
        vm.prank(beneficiary);
        vm.expectRevert(VestingScheduler.NothingToClaim.selector);
        vesting.release();

        // Warp 1 second and claim - now there are tokens to claim
        vm.warp(START_TIME + 1);
        vm.prank(beneficiary);
        vesting.release();

        assertEq(token.balanceOf(beneficiary), TOTAL_AMOUNT / VESTING_DURATION);
    }

    function test_CreateSchedule_WithCliffEqualToVesting() public {
        // Create schedule where cliff == vesting (all tokens release at once)
        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME, VESTING_DURATION, VESTING_DURATION);

        // Before cliff ends - should revert
        vm.warp(START_TIME + VESTING_DURATION - 1);
        vm.prank(beneficiary);
        vm.expectRevert(VestingScheduler.NothingToClaim.selector);
        vesting.release();

        // Exactly at cliff/vesting end - should get all tokens
        vm.warp(START_TIME + VESTING_DURATION);
        vm.prank(beneficiary);
        vesting.release();

        assertEq(token.balanceOf(beneficiary), TOTAL_AMOUNT);
    }

    function test_Release_ExactlyAtVestingEnd() public {
        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME, CLIFF_DURATION, VESTING_DURATION);

        // Warp to exactly vesting end (not +1)
        vm.warp(START_TIME + VESTING_DURATION);

        vm.prank(beneficiary);
        vesting.release();

        // Should receive all tokens
        assertEq(token.balanceOf(beneficiary), TOTAL_AMOUNT);
    }

    function test_Release_UpdatesAmountClaimed() public {
        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME, CLIFF_DURATION, VESTING_DURATION);

        // First release at 50%
        vm.warp(START_TIME + VESTING_DURATION / 2);
        vm.prank(beneficiary);
        vesting.release();

        (, uint256 amountClaimed,,,,) = vesting.schedules(beneficiary);
        uint256 expectedClaimed = (TOTAL_AMOUNT * (VESTING_DURATION / 2)) / VESTING_DURATION;
        assertEq(amountClaimed, expectedClaimed);

        // Second release at 75%
        vm.warp(START_TIME + (VESTING_DURATION * 3) / 4);
        vm.prank(beneficiary);
        vesting.release();

        (, amountClaimed,,,,) = vesting.schedules(beneficiary);
        uint256 expectedClaimed2 = (TOTAL_AMOUNT * ((VESTING_DURATION * 3) / 4)) / VESTING_DURATION;
        assertEq(amountClaimed, expectedClaimed2);
    }

    function test_MultipleBeneficiaries_IsolatedSchedules() public {
        address beneficiary2 = makeAddr("beneficiary2");

        // Create schedules for two beneficiaries
        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME, CLIFF_DURATION, VESTING_DURATION);
        vesting.createSchedule(beneficiary2, TOTAL_AMOUNT / 2, START_TIME + 100, CLIFF_DURATION, VESTING_DURATION);

        // First beneficiary releases after full vesting
        vm.warp(START_TIME + VESTING_DURATION + 1);
        vm.prank(beneficiary);
        vesting.release();

        // Second beneficiary should still have their own schedule
        (uint256 totalAmount2,,,,, bool initialized2) = vesting.schedules(beneficiary2);
        assertEq(totalAmount2, TOTAL_AMOUNT / 2);
        assertTrue(initialized2);

        // Second beneficiary releases after their vesting
        vm.warp(START_TIME + 100 + VESTING_DURATION + 1);
        vm.prank(beneficiary2);
        vesting.release();

        // Both should have received their respective amounts
        assertEq(token.balanceOf(beneficiary), TOTAL_AMOUNT);
        assertEq(token.balanceOf(beneficiary2), TOTAL_AMOUNT / 2);
    }

    function test_Release_PartialClaimsAccumulateCorrectly() public {
        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME, CLIFF_DURATION, VESTING_DURATION);

        uint256 totalReceived = 0;

        // Claim at 25%, 50%, 75%, 100%
        uint64[] memory checkpoints = new uint64[](4);
        checkpoints[0] = VESTING_DURATION / 4;
        checkpoints[1] = VESTING_DURATION / 2;
        checkpoints[2] = (VESTING_DURATION * 3) / 4;
        checkpoints[3] = VESTING_DURATION;

        for (uint256 i = 0; i < checkpoints.length; i++) {
            vm.warp(START_TIME + checkpoints[i]);
            uint256 balanceBefore = token.balanceOf(beneficiary);
            vm.prank(beneficiary);
            vesting.release();
            totalReceived += token.balanceOf(beneficiary) - balanceBefore;
        }

        // Total should equal TOTAL_AMOUNT
        assertEq(token.balanceOf(beneficiary), TOTAL_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                             FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_CreateSchedule_ValidInputs(
        address _beneficiary,
        uint256 _totalAmount,
        uint64 _startTime,
        uint64 _cliffDuration,
        uint64 _vestingDuration
    ) public {
        // Bound inputs to valid ranges
        vm.assume(_beneficiary != address(0));
        vm.assume(_totalAmount > 0 && _totalAmount <= 10_000 ether);
        vm.assume(_startTime > 0);
        vm.assume(_vestingDuration > 0);
        vm.assume(_cliffDuration <= _vestingDuration);

        vesting.createSchedule(_beneficiary, _totalAmount, _startTime, _cliffDuration, _vestingDuration);

        (uint256 totalAmount,,,,, bool initialized) = vesting.schedules(_beneficiary);
        assertEq(totalAmount, _totalAmount);
        assertTrue(initialized);
    }

    function testFuzz_VestedAmountCalculation(uint64 _elapsedTime) public {
        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME, CLIFF_DURATION, VESTING_DURATION);

        // Bound elapsed time to after cliff
        vm.assume(_elapsedTime >= CLIFF_DURATION);
        vm.assume(_elapsedTime <= VESTING_DURATION * 2); // Allow some overflow past vesting

        vm.warp(START_TIME + _elapsedTime);

        vm.prank(beneficiary);
        vesting.release();

        uint256 beneficiaryBalance = token.balanceOf(beneficiary);

        if (_elapsedTime >= VESTING_DURATION) {
            // Should have received all tokens
            assertEq(beneficiaryBalance, TOTAL_AMOUNT);
        } else {
            // Should have received proportional amount
            uint256 expectedAmount = (TOTAL_AMOUNT * _elapsedTime) / VESTING_DURATION;
            assertEq(beneficiaryBalance, expectedAmount);
        }
    }

    function testFuzz_MultipleReleases(uint8 _numReleases) public {
        vm.assume(_numReleases > 0 && _numReleases <= 10);

        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME, CLIFF_DURATION, VESTING_DURATION);

        uint256 timeIncrement = (VESTING_DURATION - CLIFF_DURATION) / _numReleases;
        uint256 totalClaimed = 0;

        for (uint8 i = 0; i < _numReleases; i++) {
            // Safe cast: timeIncrement is bounded by VESTING_DURATION (uint64) and (i+1) <= 10
            // forge-lint: disable-next-line(unsafe-typecast)
            uint64 currentTime = START_TIME + CLIFF_DURATION + uint64(timeIncrement * (i + 1));
            vm.warp(currentTime);

            uint256 balanceBeforeIteration = token.balanceOf(beneficiary);
            vm.prank(beneficiary);
            
            try vesting.release() {
                totalClaimed += token.balanceOf(beneficiary) - balanceBeforeIteration;
            } catch {
                // NothingToClaim is acceptable if rounding leaves nothing
            }
        }

        // Final release to get any remaining
        vm.warp(START_TIME + VESTING_DURATION + 1);
        uint256 balanceBefore = token.balanceOf(beneficiary);
        vm.prank(beneficiary);
        try vesting.release() {
            totalClaimed += token.balanceOf(beneficiary) - balanceBefore;
        } catch {}

        // Total claimed should equal total amount
        assertEq(token.balanceOf(beneficiary), TOTAL_AMOUNT);
    }

    function testFuzz_CliffBoundary(uint64 _timeOffset) public {
        vm.assume(_timeOffset <= CLIFF_DURATION * 2);

        vesting.createSchedule(beneficiary, TOTAL_AMOUNT, START_TIME, CLIFF_DURATION, VESTING_DURATION);

        vm.warp(START_TIME + _timeOffset);

        if (_timeOffset < CLIFF_DURATION) {
            // Should revert - cliff not reached
            vm.prank(beneficiary);
            vm.expectRevert(VestingScheduler.NothingToClaim.selector);
            vesting.release();
        } else {
            // Should succeed - cliff reached
            vm.prank(beneficiary);
            vesting.release();
            assertTrue(token.balanceOf(beneficiary) > 0);
        }
    }
}
