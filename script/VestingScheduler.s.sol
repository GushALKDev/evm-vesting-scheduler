// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {VestingScheduler} from "../src/VestingScheduler.sol";

/**
 * @title VestingSchedulerScript
 * @notice Deploy script for VestingScheduler contract
 * @dev Usage: forge script script/VestingScheduler.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract VestingSchedulerScript is Script {
    
    function run() external returns (VestingScheduler) {
        // Read token address from environment
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        
        vm.startBroadcast();
        
        VestingScheduler vesting = new VestingScheduler(tokenAddress);
        
        console.log("VestingScheduler deployed at:", address(vesting));
        console.log("Token:", tokenAddress);
        console.log("Admin:", vesting.ADMIN());
        
        vm.stopBroadcast();
        
        return vesting;
    }
}
