// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

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

    function testStepping() public {
        uint256 price = 1e18;
        uint32 stepWidth = 10;
        uint256 startTime = 5;
        uint64 increasePerStep = 1e9;

        vm.warp(0);

        PriceLinear oracle = PriceLinear(
            priceLinearCloneFactory.createPriceLinear(
                bytes32(uint256(0)),
                trustedForwarder,
                companyAdmin,
                increasePerStep,
                stepWidth,
                uint64(startTime),
                stepWidth,
                false,
                true
            )
        );

        assertEq(oracle.getPrice(price), price, "Price changed before start time");

        vm.warp(1 + startTime);
        assertEq(oracle.getPrice(price), price, "Price changed at 1");

        vm.warp(9 + startTime);
        assertEq(oracle.getPrice(price), price, "Price changed at 9");

        vm.warp(startTime + stepWidth);
        assertEq(oracle.getPrice(price), price + increasePerStep, "Price should have increased by 1 step");
        console.log("Price: %s", oracle.getPrice(price));
        console.log("Increase per step: %s", increasePerStep);

        vm.warp(startTime + stepWidth + 5);
        assertEq(oracle.getPrice(price), price + increasePerStep, "Price should have increased by 1 step");
        console.log("Price: %s", oracle.getPrice(price));
        console.log("Increase per step: %s", increasePerStep);

        vm.warp(startTime + 2 * stepWidth);
        assertEq(oracle.getPrice(price), price + 2 * increasePerStep, "Price should have increased by 2 steps");
    }

    function testDecrease() public {
        uint256 price = 1e18;
        uint32 stepWidth = 10;
        uint256 startTime = 5;
        uint64 decreasePerStep = 1e9;

        vm.warp(0);

        PriceLinear oracle = PriceLinear(
            priceLinearCloneFactory.createPriceLinear(
                bytes32(uint256(0)),
                trustedForwarder,
                companyAdmin,
                decreasePerStep,
                stepWidth,
                uint64(startTime),
                stepWidth,
                false,
                false
            )
        );

        assertEq(oracle.getPrice(price), price, "Price changed before start time");

        vm.warp(1 + startTime);
        assertEq(oracle.getPrice(price), price, "Price changed at 1");

        vm.warp(9 + startTime);
        assertEq(oracle.getPrice(price), price, "Price changed at 9");

        vm.warp(startTime + stepWidth);
        assertEq(oracle.getPrice(price), price - decreasePerStep, "Price should have decreased by 1 step");
        console.log("Price: %s", oracle.getPrice(price));
        console.log("Increase per step: %s", decreasePerStep);

        vm.warp(startTime + stepWidth + 5);
        assertEq(oracle.getPrice(price), price - decreasePerStep, "Price should have decreased by 1 step");
        console.log("Price: %s", oracle.getPrice(price));
        console.log("Increase per step: %s", decreasePerStep);

        vm.warp(startTime + 2 * stepWidth);
        assertEq(oracle.getPrice(price), price - 2 * decreasePerStep, "Price should have decreased by 2 steps");
    }

    function testBlockBased() public {
        uint256 price = 1e18;
        uint32 stepWidth = 10;
        // must use fixed start block because of yul interference with the forge system
        uint256 startBlock = 100 + 5;
        uint64 decreasePerStep = 1e9;

        //vm.roll(0);
        console.log("Current block: %s", block.number);

        PriceLinear oracle = PriceLinear(
            priceLinearCloneFactory.createPriceLinear(
                bytes32(uint256(0)),
                trustedForwarder,
                companyAdmin,
                decreasePerStep,
                stepWidth,
                uint64(startBlock),
                stepWidth,
                true,
                false
            )
        );

        assertEq(oracle.getPrice(price), price, "Price changed before start time");

        vm.roll(1 + startBlock);
        assertEq(oracle.getPrice(price), price, "Price changed at 1");
        console.log("Current block: %s", block.number);

        vm.roll(9 + startBlock);
        assertEq(oracle.getPrice(price), price, "Price changed at 9");
        console.log("Current block: %s", block.number);

        vm.roll(startBlock + stepWidth);
        assertEq(oracle.getPrice(price), price - decreasePerStep, "Price should have decreased by 1 step");
        console.log("Price: %s", oracle.getPrice(price));
        console.log("Increase per step: %s", decreasePerStep);
        console.log("Block number: ", block.number);

        vm.roll(startBlock + stepWidth + 5);
        assertEq(oracle.getPrice(price), price - decreasePerStep, "Price should have decreased by 1 step");
        console.log("Price: %s", oracle.getPrice(price));
        console.log("Increase per step: %s", decreasePerStep);
        console.log("Block number: ", block.number);

        vm.roll(startBlock + 2 * stepWidth + 1);
        assertEq(oracle.getPrice(price), price - 2 * decreasePerStep, "Price should have decreased by 2 steps");
    }
}
