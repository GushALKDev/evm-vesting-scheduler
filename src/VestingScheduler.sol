// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title VestingScheduler
 * @author GushALKDev
 * @notice A gas-optimized token vesting contract
 * @dev Implements linear vesting with cliff period. Uses storage packing for gas efficiency.
 */
contract VestingScheduler {
    
    /**
     * @notice Represents a vesting schedule for a beneficiary
     * @dev Struct is packed to minimize storage slots (3 slots total)
     */
    struct VestingSchedule {
        // Slot 1 (Packed): 8+64+64+64 = 200 bits, fits in one slot
        bool initialized;           // 1 byte
        uint64 startTime;           // 8 bytes
        uint64 cliffDuration;       // 8 bytes
        uint64 vestingDuration;     // 8 bytes
        // Slot 2: Total tokens allocated to this schedule
        uint256 totalAmount;
        // Slot 3: Tokens already claimed by beneficiary
        uint256 amountClaimed;
    }

    // The ERC20 token being vested
    IERC20 public immutable TOKEN;
    
    // The admin address that can create vesting schedules
    address public immutable ADMIN;
    
    // Mapping of beneficiary addresses to their vesting schedules
    mapping(address => VestingSchedule) public schedules;

    /*//////////////////////////////////////////////////////////////
                              CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/
    
    // Thrown when address is zero
    error AddressZero();
    // Thrown when amount is zero
    error ZeroAmount();
    // Thrown when caller is not admin
    error OnlyAdmin();
    // Thrown when cliff duration exceeds vesting duration
    error InvalidCliffDuration();
    // Thrown when start time is zero
    error InvalidStartTime();
    // Thrown when schedule already exists and is not finished
    error ScheduleAlreadyExists();
    // Thrown when no schedule exists for caller
    error NoScheduleFound();
    // Thrown when there are no tokens available to claim
    error NothingToClaim();
    // Thrown when token transfer fails
    error TransferFailed();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a new vesting schedule is created
     * @param user The beneficiary address
     * @param totalAmount Total tokens in the schedule
     * @param amountClaimed Tokens already claimed (always 0 at creation)
     * @param startTime Unix timestamp when vesting begins
     * @param cliffDuration Duration in seconds before any tokens vest
     * @param vestingDuration Total vesting duration in seconds
     * @param initialized Whether the schedule is active
     */
    event ScheduleCreated(
        address indexed user,
        uint256 totalAmount,
        uint256 amountClaimed,
        uint64 startTime,
        uint64 cliffDuration,
        uint64 vestingDuration,
        bool initialized
    );

    /**
     * @notice Emitted when tokens are released to a beneficiary
     * @param user The beneficiary who received tokens
     * @param amount The amount of tokens released
     */
    event TokensReleased(
        address indexed user,
        uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the vesting contract
     * @param _token Address of the ERC20 token to be vested
     * @dev Sets deployer as admin
     */
    constructor(address _token) {
        TOKEN = IERC20(_token);
        ADMIN = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Restricts function access to admin only
     */
    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    function _onlyAdmin() internal view {
        if (msg.sender != ADMIN) revert OnlyAdmin();
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new vesting schedule for a beneficiary
     * @dev Admin must approve token transfer before calling this function
     * @param _beneficiary Address that will receive vested tokens
     * @param _totalAmount Total tokens to vest
     * @param _startTime Unix timestamp when vesting starts
     * @param _cliffDuration Seconds before first tokens become claimable
     * @param _vestingDuration Total seconds for complete vesting
     * @custom:throws AddressZero if beneficiary is zero address
     * @custom:throws ZeroAmount if total amount is zero
     * @custom:throws InvalidCliffDuration if cliff exceeds vesting duration
     * @custom:throws InvalidStartTime if start time is zero
     * @custom:throws ScheduleAlreadyExists if active schedule exists
     * @custom:throws TransferFailed if token transfer fails
     */
    function createSchedule(
        address _beneficiary,
        uint256 _totalAmount,
        uint64 _startTime,
        uint64 _cliffDuration,
        uint64 _vestingDuration
    ) external onlyAdmin {
        // Checks
        if (_beneficiary == address(0)) revert AddressZero();
        if (_totalAmount == 0) revert ZeroAmount();
        if (_cliffDuration > _vestingDuration) revert InvalidCliffDuration();
        if (_startTime == 0) revert InvalidStartTime();

        // Check if the schedule already exists and it is not finished
        VestingSchedule storage v = schedules[_beneficiary];
        if (v.initialized && v.amountClaimed < v.totalAmount) revert ScheduleAlreadyExists();

        // Effects: Create schedule
        schedules[_beneficiary] = VestingSchedule({
            totalAmount: _totalAmount,
            amountClaimed: 0,
            startTime: _startTime,
            cliffDuration: _cliffDuration,
            vestingDuration: _vestingDuration,
            initialized: true
        });

        // Interactions: Transfer tokens from admin
        bool success = TOKEN.transferFrom(msg.sender, address(this), _totalAmount);
        if (!success) revert TransferFailed();

        // Emit event
        emit ScheduleCreated(
            _beneficiary,
            _totalAmount,
            0,
            _startTime,
            _cliffDuration,
            _vestingDuration,
            true
        );
    }

    /**
     * @notice Releases vested tokens to the caller
     * @dev Calculates vested amount based on elapsed time and transfers tokens
     * @custom:throws NoScheduleFound if caller has no vesting schedule
     * @custom:throws NothingToClaim if cliff not reached or no tokens available
     * @custom:throws TransferFailed if token transfer fails
     */
    function release() external {
        VestingSchedule storage s = schedules[msg.sender];
        
        // Check schedule exists
        if (!s.initialized) revert NoScheduleFound();
        
        // Check vesting has started
        uint64 currentTime = uint64(block.timestamp);
        if (currentTime < s.startTime) revert NothingToClaim();
        
        // Calculate elapsed time
        uint64 elapsedTime;
        unchecked { elapsedTime = currentTime - s.startTime; }
        
        // Check cliff period has passed
        if (elapsedTime < s.cliffDuration) revert NothingToClaim();

        // Calculate tokens to release
        uint256 tokensToRelease = _computeVestedAmount(s, elapsedTime);
        
        // Check there are tokens to claim
        if (tokensToRelease == 0) revert NothingToClaim();

        // Effects: Update claimed amount
        unchecked { s.amountClaimed += tokensToRelease; }

        // Interactions: Transfer tokens
        bool success = TOKEN.transfer(msg.sender, tokensToRelease);
        if (!success) revert TransferFailed();

        // Emit event
        emit TokensReleased(msg.sender, tokensToRelease);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculates the amount of tokens that have vested but not yet claimed
     * @dev Uses linear vesting formula: (totalAmount * elapsedTime / vestingDuration) - amountClaimed
     * @param _s Storage pointer to the vesting schedule
     * @param elapsedTime Seconds elapsed since vesting start
     * @return tokensToRelease Amount of tokens available to release
     */
    function _computeVestedAmount(
        VestingSchedule storage _s, 
        uint64 elapsedTime
    ) internal view returns (uint256 tokensToRelease) {
        // If vesting is complete, release all remaining tokens
        if (elapsedTime >= _s.vestingDuration) {
            unchecked { tokensToRelease = _s.totalAmount - _s.amountClaimed; }
        }
        // Otherwise, calculate proportional vested amount
        else {
            tokensToRelease = ((_s.totalAmount * elapsedTime) / _s.vestingDuration) - _s.amountClaimed;
        }
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Gets the vesting schedule for a beneficiary
     * @param _beneficiary Address of the beneficiary
     * @return VestingSchedule memory Vesting schedule for the beneficiary
     */
    function getSchedule(address _beneficiary) public view onlyAdmin returns (VestingSchedule memory) {
        return schedules[_beneficiary];
    }
}