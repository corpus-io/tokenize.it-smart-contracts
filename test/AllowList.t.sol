// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/AllowList.sol";

contract AllowListTest is Test {
    AllowList list;

    function setUp() public {
        list = new AllowList();
    }

    function testOwner() public {
        assertTrue(list.owner() == address(this));
    }

    function testFailNotOwner(address x) public {
        vm.prank(address(x));
        require(x != address(0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84));
        list.set(address(0), 1);
    }

    function testFailNotOwnerRemove(address x) public {
        vm.prank(address(x));
        require(x != address(0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84));
        list.remove(address(0));
    }

    function testSet() public {
        assertTrue(list.map(address(0)) == 0);
        list.set(address(0), 1);
        assertTrue(list.map(address(0)) == 1);
    }

    function testSet2() public {
        assertTrue(list.map(address(1)) == 0);
        list.set(address(1), 2);
        assertTrue(list.map(address(1)) == 2);
    }

    function testSetFuzzingAddress(address x) public {
        assertTrue(list.map(address(x)) == 0);
        list.set(address(x), 1);
        assertTrue(list.map(address(x)) == 1);
    }

    function testSetFuzzingValue(uint256 x) public {
        assertTrue(list.map(address(0)) == 0);
        list.set(address(0), x);
        assertTrue(list.map(address(0)) == x);
    }

    function testRemove(address x) public {
        if (x == address(0)) return;
        assertTrue(list.map(address(0)) == 0);
        list.set(address(0), 1);
        assertTrue(list.map(address(0)) == 1);

        assertTrue(list.map(x) == 0);
        list.set(x, 1);
        assertTrue(list.map(x) == 1);

        list.remove(address(0));
        assertTrue(list.map(address(0)) == 0);
        assertTrue(list.map(x) == 1);

        list.remove(x);
        assertTrue(list.map(address(0)) == 0);
        assertTrue(list.map(x) == 0);
    }
}
