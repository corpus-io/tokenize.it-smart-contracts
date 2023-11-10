// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.22;

import "../lib/forge-std/src/Test.sol";
import "../contracts/AllowList.sol";

contract AllowListTest is Test {
    event Set(address indexed key, uint256 value);

    AllowList list;
    address owner;

    function setUp() public {
        list = new AllowList();
        owner = address(this);
    }

    function testOwner() public {
        assertTrue(list.owner() == owner);
    }

    function testFailNotOwner(address x) public {
        vm.assume(x != owner);
        vm.prank(address(x));
        list.set(address(0), 1);
    }

    function testFailNotOwnerRemove(address x) public {
        vm.assume(x != owner);
        vm.prank(address(x));
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

    function testSetEvent(address x, uint256 attributes) public {
        assertTrue(list.map(address(x)) == 0);

        vm.expectEmit(true, true, true, true, address(list));
        emit Set(address(x), attributes);
        list.set(address(x), attributes);

        vm.expectEmit(true, true, true, true, address(list));
        emit Set(address(x), 0);
        list.remove(address(x));
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
