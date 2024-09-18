// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20MintableByAnyone is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract EscrowTest is Test {
    error TimelockInsufficientDelay(uint256 delay, uint256 minDelay);

    ERC20MintableByAnyone token;
    TimelockController timelock;

    uint256 public roofPK = 1;
    uint256 public platformColdPK = 2;
    uint256 public emitterPK = 3;

    address public roofAccount = vm.addr(roofPK);
    address public platformColdAccount = vm.addr(platformColdPK);
    address public emitterAccount = vm.addr(emitterPK);
    address public platformHotAccount = address(this);

    // we re-use these variables for multiple operations
    address target;
    uint256 value = 0; // no value
    bytes payload = abi.encodeWithSignature("approve(address,uint256)", platformColdAccount, type(uint256).max);
    bytes32 predecessor = 0x0; // no predecessor
    bytes32 salt = 0x0; // no salt
    uint256 delay = 1;

    function setUp() public {
        vm.warp(1); // otherwise, weird stuff happens

        // create the erc20 token
        token = new ERC20MintableByAnyone("test_token", "TT");
        target = address(token);

        // create the time lock controller. emitter is proposer and executor, platform is admin
        address[] memory roleHolders = new address[](2);
        roleHolders[0] = emitterAccount;
        roleHolders[1] = platformHotAccount;
        timelock = new TimelockController(
            0 seconds,
            roleHolders,
            roleHolders,
            platformHotAccount // the executing hot wallet is admin for now
        );

        // get id
        bytes32 id2 = timelock.hashOperation(target, value, payload, predecessor, salt);

        // propose operation #1
        assertEq(timelock.isOperation(id2), false, "operation should not exist");
        timelock.schedule(target, value, payload, predecessor, salt, delay);
        assertEq(timelock.isOperation(id2), true, "operation should exist");
        assertEq(timelock.isOperationPending(id2), true, "operation should be pending");

        // increase time by one second
        vm.warp(2);

        // execute operation
        assertEq(timelock.isOperationReady(id2), true, "operation should be ready");
        timelock.execute(target, value, payload, predecessor, salt);
        assertEq(timelock.isOperationDone(id2), true, "operation should be done");

        // check that the allowance was set
        assertEq(
            token.allowance(address(timelock), platformColdAccount),
            type(uint256).max,
            "allowance for platformColdAccount should be max"
        );

        //propose and execute second operation
        payload = abi.encodeWithSignature("approve(address,uint256)", roofAccount, type(uint256).max);
        timelock.schedule(target, value, payload, predecessor, salt, delay);
        vm.warp(3);
        timelock.execute(target, value, payload, predecessor, salt);
        assertEq(
            token.allowance(address(timelock), roofAccount),
            type(uint256).max,
            "allowance for roofAccount should be max"
        );

        console.log("updating delay next");

        // update timelock delay to 2 months. This requires a new operation.
        payload = abi.encodeWithSignature("updateDelay(uint256)", 2 * 30 days);
        timelock.schedule(
            address(timelock), // notice how timelok calls itself here
            value,
            payload,
            predecessor,
            salt,
            delay
        );
        vm.warp(4);
        timelock.execute(address(timelock), value, payload, predecessor, salt);
        assertEq(timelock.getMinDelay(), 2 * 30 days, "timelock delay should be 2 months");

        console.log("revoking roles next");

        // remove platform as admin, executor and proposer
        timelock.revokeRole(timelock.PROPOSER_ROLE(), platformHotAccount);
        timelock.revokeRole(timelock.CANCELLER_ROLE(), platformHotAccount);
        timelock.revokeRole(timelock.EXECUTOR_ROLE(), platformHotAccount);
        timelock.revokeRole(timelock.TIMELOCK_ADMIN_ROLE(), platformHotAccount);

        // check that platform no longer holds roles
        assertEq(
            timelock.hasRole(timelock.TIMELOCK_ADMIN_ROLE(), platformHotAccount),
            false,
            "platform should not be admin"
        );
        assertEq(
            timelock.hasRole(timelock.PROPOSER_ROLE(), platformHotAccount),
            false,
            "platform should not be proposer"
        );
        assertEq(
            timelock.hasRole(timelock.EXECUTOR_ROLE(), platformHotAccount),
            false,
            "platform should not be executor"
        );
        assertEq(
            timelock.hasRole(timelock.CANCELLER_ROLE(), platformHotAccount),
            false,
            "platform should not be canceller"
        );

        // mint some tokens to the timelock
        token.mint(address(timelock), 1000);
    }

    function test_platformCanTransfer() public {
        assertEq(token.balanceOf(platformColdAccount), 0, "platformColdAccount should have 0 tokens");
        vm.prank(platformColdAccount);
        token.transferFrom(address(timelock), platformColdAccount, 100);
        assertEq(token.balanceOf(platformColdAccount), 100, "platformColdAccount should have 100 tokens");
    }

    function test_roofCanTransfer() public {
        assertEq(token.balanceOf(roofAccount), 0, "roofAccount should have 0 tokens");
        vm.prank(roofAccount);
        token.transferFrom(address(timelock), roofAccount, 100);
        assertEq(token.balanceOf(roofAccount), 100, "roofAccount should have 100 tokens");
    }

    function test_RandoCanNotTransfer(address rando) public {
        vm.assume(rando != roofAccount && rando != platformColdAccount && rando != address(timelock));
        assertEq(token.balanceOf(rando), 0, "rando should have 0 tokens");
        vm.prank(rando);
        vm.expectRevert();
        token.transferFrom(address(timelock), rando, 100);
        assertEq(token.balanceOf(rando), 0, "rando should still have 0 tokens");
    }

    function test_emitterCanNotTransferImmediately() public {
        assertEq(token.balanceOf(emitterAccount), 0, "emitterAccount should have 0 tokens");
        vm.prank(emitterAccount);
        vm.expectRevert();
        token.transferFrom(address(timelock), emitterAccount, 100);
        assertEq(token.balanceOf(emitterAccount), 0, "emitterAccount should still have 0 tokens");
    }

    function test_emitterCanTransferAfterDelay() public {
        assertEq(token.balanceOf(emitterAccount), 0, "emitterAccount should have 0 tokens");

        payload = abi.encodeWithSignature("transfer(address,uint256)", emitterAccount, 100);
        target = address(token);
        delay = 2 * 30 days;

        vm.prank(emitterAccount);
        timelock.schedule(target, value, payload, predecessor, salt, delay);
        vm.warp(2 * 30 days + 10); // we did some warping in setup, so we need to add 10 seconds

        vm.prank(emitterAccount);
        timelock.execute(target, value, payload, predecessor, salt);
        assertEq(token.balanceOf(emitterAccount), 100, "emitterAccount should have 100 tokens");
    }

    function test_emitterCanNotProposeShorterDelay() public {
        assertEq(token.balanceOf(emitterAccount), 0, "emitterAccount should have 0 tokens");

        payload = abi.encodeWithSignature("transfer(address,uint256)", emitterAccount, 100);
        target = address(token);
        delay = 2 * 29 days;

        vm.prank(emitterAccount);
        vm.expectRevert();
        timelock.schedule(target, value, payload, predecessor, salt, delay);
    }

    function test_emitterCanNotExecuteBeforeDelayHasPassed() public {
        assertEq(token.balanceOf(emitterAccount), 0, "emitterAccount should have 0 tokens");

        payload = abi.encodeWithSignature("transfer(address,uint256)", emitterAccount, 100);
        target = address(token);
        delay = 2 * 30 days;

        vm.prank(emitterAccount);
        timelock.schedule(target, value, payload, predecessor, salt, delay);
        vm.warp(2 * 30 days - 1);

        vm.prank(emitterAccount);
        vm.expectRevert(); // not extracting the precise error now
        timelock.execute(target, value, payload, predecessor, salt);
    }

    /**
     * BEHOLD! The emitter can approve itself for infinite allowance
     * -> this breaks the security model of the timelock in our application
     */
    function test_emitterCanApproveSelf() public {
        assertEq(token.allowance(address(timelock), emitterAccount), 0, "emitterAccount should have 0 allowance");

        payload = abi.encodeWithSignature("approve(address,uint256)", emitterAccount, type(uint256).max);
        target = address(token);
        delay = 2 * 30 days;

        vm.prank(emitterAccount);
        timelock.schedule(target, value, payload, predecessor, salt, delay);
        vm.warp(2 * 30 days + 10); // we did some warping in setup, so we need to add 10 seconds

        vm.prank(emitterAccount);
        timelock.execute(target, value, payload, predecessor, salt);
        assertEq(
            token.allowance(address(timelock), emitterAccount),
            type(uint256).max,
            "emitterAccount should have infinite allowance"
        );
    }
}
