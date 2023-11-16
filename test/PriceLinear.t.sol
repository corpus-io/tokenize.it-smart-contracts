// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../contracts/PriceLinearCloneFactory.sol";

contract PublicFundraisingTest is Test {
    PriceLinearCloneFactory priceLinearCloneFactory;
    PriceLinear oracle;

    address public constant companyAdmin = address(1);
    address public trustedForwarder = address(2);

    function setUp() public {
        // set up price oracle factory
        PriceLinear priceLinearLogicContract = new PriceLinear(trustedForwarder);
        priceLinearCloneFactory = new PriceLinearCloneFactory(address(priceLinearLogicContract));

        oracle = PriceLinear(
            priceLinearCloneFactory.createPriceLinear(
                bytes32(uint256(0)),
                trustedForwarder,
                companyAdmin,
                1,
                1,
                uint64(block.timestamp + 1),
                1,
                false
            )
        );
    }

    function testPriceRises(uint256 price, uint256 someTime) public {
        vm.warp(1 days);

        uint256 startTime = 3 + 1 days;
        uint256 plannedChange = 42e9;
        vm.assume(price < type(uint256).max - plannedChange);
        vm.assume(someTime < type(uint256).max - startTime);

        PriceLinear _oracle = PriceLinear(
            priceLinearCloneFactory.createPriceLinear(
                bytes32(uint256(0)),
                trustedForwarder,
                companyAdmin,
                1,
                1,
                uint64(startTime),
                1,
                false
            )
        );

        vm.warp(startTime - 1);
        assertEq(_oracle.getPrice(price), price, "Price changed before start time");

        vm.warp(startTime);
        assertEq(_oracle.getPrice(price), price, "Price changed already at start time");

        vm.warp(startTime + 1);
        assertEq(_oracle.getPrice(price), price + 1, "Price should have increased by 1");

        vm.warp(startTime + plannedChange);
        assertEq(_oracle.getPrice(price), price + plannedChange, "Price should have increased by 42e9");

        vm.warp(startTime + someTime);
        if (type(uint256).max - (startTime + someTime) > price) {
            assertEq(_oracle.getPrice(price), someTime + price, "Price should have increased by someTime");
        } else {
            assertEq(_oracle.getPrice(price), type(uint256).max, "Price should have increased to max");
        }
    }

    function testStepping() public {
        vm.warp(1 days);

        uint256 price = 1e18;
        uint32 stepWidth = 10;
        uint256 startTime = 5 + 1 days;
        int64 increasePerStep = 1e9;

        PriceLinear _oracle = PriceLinear(
            priceLinearCloneFactory.createPriceLinear(
                bytes32(uint256(0)),
                trustedForwarder,
                companyAdmin,
                increasePerStep,
                stepWidth,
                uint64(startTime),
                stepWidth,
                false
            )
        );

        assertEq(_oracle.getPrice(price), price, "Price changed before start time");

        vm.warp(1 + startTime);
        assertEq(_oracle.getPrice(price), price, "Price changed at 1");

        vm.warp(9 + startTime);
        assertEq(_oracle.getPrice(price), price, "Price changed at 9");

        vm.warp(startTime + stepWidth);
        assertEq(_oracle.getPrice(price), price + uint64(increasePerStep), "Price should have increased by 1 step");
        console.log("Price: %s", _oracle.getPrice(price));

        vm.warp(startTime + stepWidth + 5);
        assertEq(_oracle.getPrice(price), price + uint64(increasePerStep), "Price should have increased by 1 step");
        console.log("Price: %s", _oracle.getPrice(price));

        vm.warp(startTime + 2 * stepWidth);
        assertEq(
            _oracle.getPrice(price),
            price + 2 * uint64(increasePerStep),
            "Price should have increased by 2 steps"
        );
    }

    function testDecrease() public {
        vm.warp(1 days);

        uint256 price = 1e18;
        uint32 stepWidth = 10;
        uint256 startTime = 5 + 1 days;
        int64 changePerStep = -1e9; // change is negative

        PriceLinear _oracle = PriceLinear(
            priceLinearCloneFactory.createPriceLinear(
                bytes32(uint256(0)),
                trustedForwarder,
                companyAdmin,
                changePerStep,
                stepWidth,
                uint64(startTime),
                stepWidth,
                false
            )
        );

        assertEq(_oracle.getPrice(price), price, "Price changed before start time");

        vm.warp(1 + startTime);
        assertEq(_oracle.getPrice(price), price, "Price changed at 1");

        vm.warp(9 + startTime);
        assertEq(_oracle.getPrice(price), price, "Price changed at 9");

        vm.warp(startTime + stepWidth);
        assertEq(_oracle.getPrice(price), price - uint64(-changePerStep), "Price should have decreased by 1 step");
        console.log("Price: %s", _oracle.getPrice(price));
        console.log("Increase per step: ");
        console.logInt(changePerStep);

        vm.warp(startTime + stepWidth + 5);
        assertEq(_oracle.getPrice(price), price - uint64(-changePerStep), "Price should have decreased by 1 step");
        console.log("Price: %s", _oracle.getPrice(price));

        vm.warp(startTime + 2 * stepWidth);
        assertEq(_oracle.getPrice(price), price - 2 * uint64(-changePerStep), "Price should have decreased by 2 steps");
    }

    function testBlockBased() public {
        vm.warp(1 days);
        uint256 price = 1e18;
        uint32 stepWidth = 10;
        // must use fixed start block because of yul interference with the forge system
        uint256 startBlock = 100 + 5;
        int64 changePerStep = -1e9;

        console.log("Change per step: %s");
        console.logInt(changePerStep);

        //vm.roll(0);
        console.log("Current block: %s", block.number);

        PriceLinear _oracle = PriceLinear(
            priceLinearCloneFactory.createPriceLinear(
                bytes32(uint256(0)),
                trustedForwarder,
                companyAdmin,
                changePerStep,
                stepWidth,
                uint64(startBlock),
                stepWidth,
                true
            )
        );

        assertEq(_oracle.getPrice(price), price, "Price changed before start time");

        vm.roll(1 + startBlock);
        assertEq(_oracle.getPrice(price), price, "Price changed at 1");
        console.log("Current block: %s", block.number);

        vm.roll(9 + startBlock);
        assertEq(_oracle.getPrice(price), price, "Price changed at 9");
        console.log("Current block: %s", block.number);

        vm.roll(startBlock + stepWidth);
        assertEq(_oracle.getPrice(price), price - uint64(-changePerStep), "Price should have decreased by 1 step");
        console.log("Price: %s", _oracle.getPrice(price));
        console.log("Block number: ", block.number);

        vm.roll(startBlock + stepWidth + 5);
        assertEq(_oracle.getPrice(price), price - uint64(-changePerStep), "Price should have decreased by 1 step");
        console.log("Price: %s", _oracle.getPrice(price));
        console.log("Block number: ", block.number);

        vm.roll(startBlock + 2 * stepWidth + 1);
        assertEq(_oracle.getPrice(price), price - 2 * uint64(-changePerStep), "Price should have decreased by 2 steps");
    }

    function testUpdateParameters(
        int64 _slopeEnumerator,
        uint64 _slopeDenominator,
        uint64 _startTimeOrBlockNumber,
        uint32 _stepDuration,
        bool _isBlockBased
    ) public {
        vm.warp(1 days);

        vm.assume(_slopeEnumerator != 0);
        vm.assume(_slopeDenominator != 0);
        if (_isBlockBased) {
            vm.assume(_startTimeOrBlockNumber > block.number);
        } else {
            vm.assume(_startTimeOrBlockNumber > block.timestamp);
        }
        vm.assume(_stepDuration != 0);

        assertEq(oracle.coolDownStart(), 0, "coolDownStart should be 0");

        // update parameters
        vm.prank(companyAdmin);
        oracle.updateParameters(
            _slopeEnumerator,
            _slopeDenominator,
            _startTimeOrBlockNumber,
            _stepDuration,
            _isBlockBased
        );

        assertEq(oracle.coolDownStart(), block.timestamp, "coolDownStart should be block.timestamp");

        (
            int64 currentSlopeEnumerator,
            uint64 currentSlopeDenominator,
            uint64 currentStartTimeOrBlockNumber,
            uint32 currentStepDuration,
            bool currentIsBlockBased
        ) = oracle.parameters();

        assertEq(currentSlopeEnumerator, _slopeEnumerator, "slopeEnumerator should be _slopeEnumerator");
        assertEq(currentSlopeDenominator, _slopeDenominator, "slopeDenominator should be _slopeDenominator");
        assertEq(currentStartTimeOrBlockNumber, _startTimeOrBlockNumber, "start should be _startTimeOrBlockNumber");
        assertEq(currentStepDuration, _stepDuration, "stepDuration should be _stepDuration");
        assertEq(currentIsBlockBased, _isBlockBased, "isBlockBased should be _isBlockBased");
    }

    function testOnlyOwnerCanUpdateParameters(address rando) public {
        vm.assume(rando != companyAdmin);
        vm.assume(rando != address(0));
        vm.prank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        oracle.updateParameters(1, 1, 1, 1, false);
    }

    function testRevertsBeforeCoolDownEnd(uint32 testDelay) public {
        vm.warp(1 days);
        testDelay = testDelay % 1 hours; // test delay is less than 1 hour

        vm.prank(companyAdmin);
        oracle.updateParameters(1, 1, uint64(block.timestamp + 1), 1, false);

        vm.warp(block.timestamp + testDelay);
        vm.expectRevert("PriceLinear: cool down period not over yet");
        oracle.getPrice(7e18);

        vm.warp(block.timestamp + testDelay + 1 hours + 1); // this is definitely after the cool down period
        oracle.getPrice(7e18);
    }
}
