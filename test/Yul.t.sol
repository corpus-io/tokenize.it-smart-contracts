// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";

contract YulTest is Test {
    function setUp() public {}

    function testYul() public {
        uint256 time = block.timestamp;
        assertTrue(time == 1, "time is not 1 at the beginning");
        console.log("stored time before: ", time);
        // problem: using yul, this warp changes the contents of the "time" variable
        vm.warp(2 hours);
        console.log("stored time after: ", time);

        // this test does not fail for some reason
        assertTrue(time == 1, "time is not 1 after warp");
        assertTrue(time == 7200, "time is not 7200 after warp");
    }
}
