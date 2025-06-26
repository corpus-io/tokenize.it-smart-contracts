// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "../contracts/factories/AllowListCloneFactory.sol";

contract AllowListTest is Test {
    event Set(address indexed key, uint256 value);

    AllowList list;
    address trustedForwarder = address(1);
    address owner = address(2);
    AllowListCloneFactory factory;

    function setUp() public {
        AllowList allowListLogicContract = new AllowList(trustedForwarder);
        factory = new AllowListCloneFactory(address(allowListLogicContract));
        list = AllowList(factory.createAllowListClone("salt", trustedForwarder, owner));
    }

    function testLogicContractInit(address _trustedForwarder) public {
        vm.assume(_trustedForwarder != address(0));
        AllowList allowListLogicContract = new AllowList(_trustedForwarder);
        assertTrue(
            allowListLogicContract.isTrustedForwarder(_trustedForwarder),
            "AllowList: Unexpected trustedForwarder"
        );
    }

    function testOwner0Reverts() public {
        vm.expectRevert("owner can not be zero address");
        factory.createAllowListClone("salt", trustedForwarder, address(0));
    }

    function testOwner() public view {
        assertTrue(list.owner() == owner);
    }

    function testNotOwner(address x) public {
        vm.assume(x != owner);
        vm.prank(address(x));
        vm.expectRevert("Ownable: caller is not the owner");
        list.set(address(0), 1);
    }

    function testNotOwnerRemove(address x) public {
        vm.assume(x != owner);
        vm.prank(address(x));
        vm.expectRevert("Ownable: caller is not the owner");
        list.remove(address(0));
    }

    function testSet() public {
        assertTrue(list.map(address(0)) == 0);
        vm.prank(owner);
        list.set(address(0), 1);
        assertTrue(list.map(address(0)) == 1);
    }

    function testSet2() public {
        assertTrue(list.map(address(1)) == 0);
        vm.prank(owner);
        list.set(address(1), 2);
        assertTrue(list.map(address(1)) == 2);
    }

    function testSetEvent(address x, uint256 attributes) public {
        assertTrue(list.map(address(x)) == 0);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true, address(list));
        emit Set(address(x), attributes);
        list.set(address(x), attributes);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true, address(list));
        emit Set(address(x), 0);
        list.remove(address(x));
    }

    function testSetFuzzingAddress(address x) public {
        assertTrue(list.map(address(x)) == 0);
        vm.prank(owner);
        list.set(address(x), 1);
        assertTrue(list.map(address(x)) == 1);
    }

    function testSetFuzzingValue(uint256 x) public {
        assertTrue(list.map(address(0)) == 0);
        vm.prank(owner);
        list.set(address(0), x);
        assertTrue(list.map(address(0)) == x);
    }

    function testSetMultiple(address x, uint256 attributesX, address y, uint256 attributesY) public {
        vm.assume(x != address(0));
        vm.assume(y != address(0));
        vm.assume(x != y);
        assertTrue(list.map(address(x)) == 0, "x already on list");
        assertTrue(list.map(address(y)) == 0, "y already on list");
        address[] memory addresses = new address[](2);
        addresses[0] = address(x);
        addresses[1] = address(y);
        uint256[] memory attributes = new uint256[](2);
        attributes[0] = attributesX;
        attributes[1] = attributesY;
        vm.prank(owner);
        list.set(addresses, attributes);
        assertTrue(list.map(address(x)) == attributesX, "x not set");
        assertTrue(list.map(address(y)) == attributesY, "y not set");
    }

    // function testSetMultipleRandom(address[] memory addresses, uint256[] memory attributes) public {
    //     uint256 length = addresses.length < attributes.length ? addresses.length : attributes.length;
    //     vm.prank(owner);
    //     list.set(addresses[:length], attributes[:length]);
    //     // assertTrue(list.map(address(x)) == attributesX, "x not set");
    //     // assertTrue(list.map(address(y)) == attributesY, "y not set");
    // }

    function testSetMultipleWithUnequalArrays(address x, uint256 attributesX, address y) public {
        vm.assume(x != address(0));
        vm.assume(y != address(0));
        vm.assume(x != y);
        assertTrue(list.map(address(x)) == 0, "x already on list");
        assertTrue(list.map(address(y)) == 0, "y already on list");
        address[] memory addresses = new address[](2);
        addresses[0] = address(x);
        addresses[1] = address(y);
        uint256[] memory attributes = new uint256[](1);
        attributes[0] = attributesX;
        vm.prank(owner);
        vm.expectRevert("lengths do not match");
        list.set(addresses, attributes);
    }

    function testRandoCanNotSetMultiple(address x, uint256 attributesX, address y, uint256 attributesY) public {
        vm.assume(x != address(0));
        vm.assume(x != owner);
        vm.assume(y != address(0));
        vm.assume(x != y);
        address[] memory addresses = new address[](2);
        addresses[0] = address(x);
        addresses[1] = address(y);
        uint256[] memory attributes = new uint256[](2);
        attributes[0] = attributesX;
        attributes[1] = attributesY;
        vm.prank(x);
        vm.expectRevert("Ownable: caller is not the owner");
        list.set(addresses, attributes);
        assertTrue(list.map(address(x)) == 0, "x was set");
        assertTrue(list.map(address(y)) == 0, "y was set");
    }

    function testRemoveMultiple(address x, uint256 attributesX, address y, uint256 attributesY) public {
        vm.assume(x != address(0));
        vm.assume(y != address(0));
        vm.assume(x != y);
        address[] memory addresses = new address[](2);
        addresses[0] = address(x);
        addresses[1] = address(y);
        uint256[] memory attributes = new uint256[](2);
        attributes[0] = attributesX;
        attributes[1] = attributesY;
        vm.prank(owner);
        list.set(addresses, attributes);
        assertTrue(list.map(address(x)) == attributesX, "x not set");
        assertTrue(list.map(address(y)) == attributesY, "y not set");

        // now remove both
        vm.prank(owner);
        list.remove(addresses);
        assertTrue(list.map(address(x)) == 0, "x not removed");
        assertTrue(list.map(address(y)) == 0, "y not removed");
    }

    function testRandoCannotRemoveMultiple(address rando) public {
        vm.assume(rando != address(0));
        vm.assume(rando != owner);

        address[] memory addresses = new address[](2);
        addresses[0] = address(3);
        addresses[1] = address(5);

        vm.prank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        list.remove(addresses);
    }

    function testRemove(address x) public {
        if (x == address(0)) return;
        assertTrue(list.map(address(0)) == 0);
        vm.prank(owner);
        list.set(address(0), 1);
        assertTrue(list.map(address(0)) == 1);

        assertTrue(list.map(x) == 0);
        vm.prank(owner);
        list.set(x, 1);
        assertTrue(list.map(x) == 1);

        vm.prank(owner);
        list.remove(address(0));
        assertTrue(list.map(address(0)) == 0);
        assertTrue(list.map(x) == 1);

        vm.prank(owner);
        list.remove(x);
        assertTrue(list.map(address(0)) == 0);
        assertTrue(list.map(x) == 0);
    }

    function testTrustedCurrencyBit() public pure {
        assertTrue(
            TRUSTED_CURRENCY == 2 ** 255,
            "TRUSTED_CURRENCY has wrong value. Must stay constant or old contracts might break"
        );
    }
}
