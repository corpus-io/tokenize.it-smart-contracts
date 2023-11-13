// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../contracts/VestingCloneFactory.sol";
import "./resources/ERC20MintableByAnyone.sol";

contract VestingCloneFactoryTest is Test {
    Vesting implementation;
    VestingCloneFactory factory;

    address owner = address(7);

    ERC20MintableByAnyone token = new ERC20MintableByAnyone("test token", "TST");

    Vesting vesting;

    address trustedForwarder = address(1);

    function setUp() public {
        implementation = new Vesting(trustedForwarder);
        vm.warp(implementation.TIME_HORIZON());

        factory = new VestingCloneFactory(address(implementation));

        vesting = Vesting(factory.createVestingClone(0, trustedForwarder, owner, address(token)));
    }

    function testSwitchOwner(address _owner, address newOwner) public {
        vm.assume(_owner != address(0));
        vm.assume(_owner != trustedForwarder);
        vm.assume(newOwner != address(0));
        vm.assume(newOwner != _owner);
        vm.assume(_owner != address(this));
        Vesting vest = Vesting(factory.createVestingClone(0, trustedForwarder, _owner, address(token)));
        assertEq(vest.owner(), _owner, "owner not set");

        vm.prank(_owner);
        vest.transferOwnership(newOwner);

        assertEq(vest.owner(), newOwner, "owner not changed");
    }

    function testOnlyOwnerCanCommit(address rando, bytes32 hash) public {
        Vesting vest = Vesting(factory.createVestingClone(0, trustedForwarder, address(this), address(token)));
        vm.assume(rando != address(0));
        vm.assume(rando != address(this));

        // rando cannot commit
        vm.prank(rando);
        vm.expectRevert("Caller is not a manager");
        vest.commit(hash);

        // owner can commit
        vest.commit(hash);
    }

    function testOnlyOwnerCanCreate(address _owner, address _rando, address _token) public {
        vm.assume(_rando != address(0));
        vm.assume(_rando != address(this));
        vm.assume(_owner != address(0));
        vm.assume(_owner != address(this));
        vm.assume(_owner != _rando);
        vm.assume(_owner != trustedForwarder);
        vm.assume(_token != address(0));

        Vesting vest = Vesting(factory.createVestingClone(0, trustedForwarder, _owner, _token));
        vm.assume(_rando != address(0));
        vm.assume(_rando != address(this));

        // rando cannot create
        vm.prank(_rando);
        vm.expectRevert("Caller is not a manager");
        vest.createVesting(100, address(7), 1, 20 days, 40 days, false);

        // owner can create
        vm.prank(_owner);
        vest.createVesting(100, address(7), 1, 20 days, 40 days, false);
    }

    function testCreateMintableVest(address beneficiary, address rando) public {
        vm.assume(beneficiary != address(0));
        vm.assume(rando != address(0));
        vm.assume(rando != beneficiary);
        vm.assume(beneficiary != trustedForwarder);

        uint256 amount = 10 ** 18;

        vm.startPrank(owner);
        uint64 id = vesting.createVesting(amount, beneficiary, implementation.TIME_HORIZON(), 0, 100 days, true);
        vm.stopPrank();

        assertEq(vesting.beneficiary(id), beneficiary);
        assertEq(vesting.allocation(id), amount);
        assertEq(vesting.released(id), 0);
        assertEq(vesting.start(id), implementation.TIME_HORIZON());
        assertEq(vesting.cliff(id), 0);
        assertEq(vesting.duration(id), 100 days);
        assertEq(vesting.isMintable(id), true, "Vesting plan not mintable");

        assertEq(token.balanceOf(beneficiary), 0);

        // rando can not release tokens
        vm.warp(block.timestamp + 10 days);
        vm.prank(rando);
        vm.expectRevert("Only beneficiary can release tokens");
        vesting.release(id);

        // beneficiary can release tokens
        vm.warp(block.timestamp + 70 days);
        vm.prank(beneficiary);
        vesting.release(id);

        assertEq(vesting.released(id), 8e17, "released amount is wrong");
        assertEq(token.balanceOf(beneficiary), 8e17, "beneficiary balance is wrong");
    }

    function testPauseBeforeCliff(address _usr) public {
        vm.assume(_usr != address(0));

        uint256 amount = 70e18;
        uint64 start = implementation.TIME_HORIZON() + 2 * 365 days;
        uint64 duration = 2 * 365 days;
        uint64 cliff = 1 * 365 days;
        uint64 pauseStart = start + 90 days;
        uint64 pauseEnd = start + 1 * 365 days;

        vm.prank(owner);
        uint64 id = vesting.createVesting(amount, _usr, start, cliff, duration, false);
        token.mint(address(vesting), amount);

        assertEq(id, 0, "ids don't start at 0");

        // log vestings total amount
        console.log("total amount", vesting.allocation(id));
        console.log("ids", vesting.ids());

        vm.warp(start + 20 days);

        vm.startPrank(owner);
        uint64 newId = vesting.pauseVesting(id, pauseStart, pauseEnd);
        vm.stopPrank();
        assertEq(newId, 1, "ids don't increase by 1");

        console.log("total amount", vesting.allocation(id));
        // allocation new id
        console.log("total amount new id", vesting.allocation(newId));
        console.log("ids", vesting.ids());

        // make sure old vesting is deleted
        assertEq(vesting.allocation(id), 0, "old total is wrong");
        assertEq(vesting.released(id), 0, "old released is wrong");
        assertEq(vesting.beneficiary(id), address(0), "old beneficiary is not deleted");
        assertEq(vesting.start(id), 0, "old start is wrong");
        assertEq(vesting.cliff(id), 0, "old cliff is wrong");
        assertEq(vesting.duration(id), 0, "old duration is wrong");
        assertEq(vesting.isMintable(id), false, "old mintable is wrong");

        // make sure new id has proper values
        assertEq(vesting.allocation(newId), amount, "total is wrong");
        assertEq(vesting.released(newId), 0, "released is wrong");
        assertEq(vesting.beneficiary(newId), _usr, "beneficiary is not deleted");
        assertEq(vesting.start(newId), pauseEnd, "start is wrong");
        assertEq(vesting.cliff(newId), cliff - 90 days, "cliff is wrong");
        assertEq(vesting.duration(newId), duration - 90 days, "duration is wrong");
        assertEq(vesting.isMintable(newId), false, "mintable is wrong");

        // go to end of vestings and claim all. It must match the total
        vm.warp(pauseEnd + duration);
        vm.startPrank(_usr);
        vesting.release(newId);

        assertEq(token.balanceOf(_usr), amount, "balance is wrong");

        vm.stopPrank();
    }

    // function testPauseAfterCliffLocal(address _usr, uint256 pauseAfter, uint256 pauseDuration) public {
    //     vm.assume(_usr != address(0));
    //     pauseAfter = (pauseAfter % 90) + 10; // range from 10 to 99
    //     pauseDuration = (pauseDuration % (10 * 365 days)) + 1;

    //     ERC20MintableByAnyone gem = new ERC20MintableByAnyone("gem", "GEM");

    //     DssVestMintable mVest = new DssVestMintable(address(forwarder), address(gem), 10 ** 18);

    //     mVest.create(_usr, total, startOfTime, duration, eta, address(0)); // first id is 1

    //     vm.warp(startOfTime + 3);

    //     mVest.pause(1, startOfTime + pauseAfter, startOfTime + pauseAfter + pauseDuration); // new id is 2

    //     // make sure old id is yanked by setting tot to 0 because it is inside cliff still
    //     (address usr, uint48 bgn, uint48 clf, uint48 fin, , , uint128 tot, ) = mVest.awards(1);
    //     assertEq(usr, _usr, "user is not the same");
    //     assertEq(uint256(bgn), startOfTime, "start is wrong");
    //     assertEq(uint256(fin), startOfTime + pauseAfter, "finish is wrong");
    //     assertTrue(uint256(tot) < total, "total is too much");
    //     assertTrue(uint256(tot) != 0, "total is 0");

    //     // make sure new id has proper values
    //     uint128 newTot;
    //     (usr, bgn, clf, fin, , , newTot, ) = mVest.awards(2);
    //     assertEq(usr, _usr, "new user is not the same");
    //     assertEq(uint256(bgn), startOfTime + pauseAfter + pauseDuration, "new start is wrong"); // because 3 days of cliff had already passed
    //     assertEq(uint256(clf), bgn, "new cliff is wrong"); // because 7 days of cliff remain
    //     assertEq(uint256(newTot), total - tot, "new total is wrong");
    //     assertEq(uint256(fin), startOfTime + pauseDuration + duration, "new end is wrong"); // because pause started after 3 days

    //     // go to end of vestings and claim all. It must match the total
    //     vm.warp(startOfTime + pauseAfter + pauseDuration + 1000 days);
    //     vm.startPrank(_usr);
    //     mVest.vest(2, type(uint256).max);
    //     mVest.vest(1, type(uint256).max);

    //     assertEq(gem.balanceOf(_usr), total, "balance is wrong");
    // }
}
