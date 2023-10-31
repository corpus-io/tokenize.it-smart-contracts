// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/PriceLinearCloneFactory.sol";

contract PublicFundraisingTest is Test {
    PriceLinearCloneFactory priceLinearCloneFactory;

    address public constant companyAdmin = address(1);
    address public trustedForwarder = address(2);

    function setUp() public {
        // set up price oracle factory
        PriceLinear priceLinearLogicContract = new PriceLinear(trustedForwarder);
        priceLinearCloneFactory = new PriceLinearCloneFactory(address(priceLinearLogicContract));
    }

    function testPriceRises(uint256 price, uint256 someTime) public {
        uint256 startTime = 3;
        uint256 plannedChange = 42e9;
        vm.assume(price < type(uint256).max - plannedChange);
        vm.assume(someTime < type(uint256).max - startTime);
        vm.warp(0);

        PriceLinear oracle = PriceLinear(
            priceLinearCloneFactory.createPriceLinear(
                bytes32(uint256(0)),
                trustedForwarder,
                companyAdmin,
                1,
                1,
                uint64(startTime),
                1,
                false,
                true
            )
        );

        vm.warp(1);
        assertEq(oracle.getPrice(price), price, "Price changed before start time");

        vm.warp(startTime);
        assertEq(oracle.getPrice(price), price, "Price changed already at start time");

        vm.warp(startTime + 1);
        assertEq(oracle.getPrice(price), price + 1, "Price should have increased by 1");

        vm.warp(startTime + plannedChange);
        assertEq(oracle.getPrice(price), price + plannedChange, "Price should have increased by 42e9");

        vm.warp(startTime + someTime);
        if (type(uint256).max - (startTime + someTime) > price) {
            assertEq(oracle.getPrice(price), someTime + price, "Price should have increased by someTime");
        } else {
            assertEq(oracle.getPrice(price), type(uint256).max, "Price should have increased to max");
        }
    }
}
