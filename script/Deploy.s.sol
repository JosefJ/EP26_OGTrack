// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {OGAuthSignup} from "../src/OGAuthSignup.sol";

contract Deploy is Script {
    function run() external {
        bytes32 rootHash       = 0x5038ecf2e77e42cd3f8290e61388bb297250ae25fb11e64f94472ab4a9d57a57;
        uint256 depositWei     = 0.01 ether;
        uint256 signupSlots    = 100;

        vm.startBroadcast();
        OGAuthSignup signup = new OGAuthSignup(rootHash, depositWei, signupSlots);
        console.log("Deployed OGAuthSignup at:", address(signup));
        vm.stopBroadcast();
    }
}
