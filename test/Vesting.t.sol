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

        vesting = Vesting(factory.createVestingClone(0, trustedForwarder, owner));
    }

    function testSwitchOwner(address _owner, address newOwner) public {
        vm.assume(_owner != address(0));
        vm.assume(_owner != trustedForwarder);
        vm.assume(newOwner != address(0));
        vm.assume(newOwner != _owner);
        vm.assume(_owner != address(this));
        Vesting vest = Vesting(factory.createVestingClone(0, trustedForwarder, _owner));
        assertEq(vest.owner(), _owner, "owner not set");

        vm.prank(_owner);
        vest.transferOwnership(newOwner);

        assertEq(vest.owner(), newOwner, "owner not changed");
    }

    function testOnlyOwnerCanCommit(address rando, bytes32 hash) public {
        Vesting vest = Vesting(factory.createVestingClone(0, trustedForwarder, address(this)));
        vm.assume(rando != address(0));
        vm.assume(rando != address(this));

        // rando cannot commit
        vm.prank(rando);
        vm.expectRevert("Caller is not a manager");
        vest.commit(hash);

        // owner can commit
        vest.commit(hash);
    }

    function testOnlyOwnerCanCreate(address _owner, address rando) public {
        vm.assume(rando != address(0));
        vm.assume(rando != address(this));
        vm.assume(_owner != address(0));
        vm.assume(_owner != address(this));
        vm.assume(_owner != rando);
        vm.assume(_owner != trustedForwarder);

        Vesting vest = Vesting(factory.createVestingClone(0, trustedForwarder, _owner));
        vm.assume(rando != address(0));
        vm.assume(rando != address(this));

        // rando cannot create
        vm.prank(rando);
        vm.expectRevert("Caller is not a manager");
        vest.createVesting(address(5), 100, address(7), 1, 20 days, 40 days, false);

        // owner can create
        vm.prank(_owner);
        vest.createVesting(address(5), 100, address(7), 1, 20 days, 40 days, false);
    }

    function testCreateMintableVest(address beneficiary, address rando) public {
        vm.assume(beneficiary != address(0));
        vm.assume(rando != address(0));
        vm.assume(rando != beneficiary);

        uint256 amount = 10 ** 18;

        vm.prank(owner);
        uint64 id = vesting.createVesting(address(token), amount, beneficiary, 0, 0, 100 days, true);

        assertEq(vesting.beneficiary(id), beneficiary);
        assertEq(vesting.allocation(id), amount);
        assertEq(vesting.released(id), 0);
        assertEq(vesting.start(id), 0);
        assertEq(vesting.cliff(id), 0);
        assertEq(vesting.duration(id), 100 days);
        assertEq(vesting.isMintable(id), true, "Vesting plan not mintable");

        assertEq(token.balanceOf(beneficiary), 0);

        vm.warp(block.timestamp + 10 days);

        // rando can not mint tokens
        vm.prank(rando);
        vm.expectRevert("Only beneficiary can release tokens");
        vesting.release(id);

        // vm.warp(block.timestamp + 70 days);

        // vm.prank(rando);
        // vesting.vest(id, type(uint256).max);
        // (usr, bgn, clf, fin, mgr, , tot, rxd) = vesting.awards(id);
        // assertEq(usr, beneficiary);
        // assertEq(uint256(bgn), block.timestamp - 80 days);
        // assertEq(uint256(fin), block.timestamp + 20 days);
        // assertEq(uint256(tot), 100 * amount);
        // assertEq(uint256(rxd), 80 * amount);
        // assertEq(token.balanceOf(beneficiary), 80 * amount);
    }

    // function testPauseBeforeCliffLocal(address _usr) public {
    //     vm.assume(_usr != address(0));

    //     ERC20MintableByAnyone gem = new ERC20MintableByAnyone("gem", "GEM");

    //     DssVestMintable mVest = new DssVestMintable(address(forwarder), address(gem), 10 ** 18);

    //     uint256 id = mVest.create(_usr, total, startOfTime, duration, eta, address(0));

    //     vm.warp(startOfTime + 1);

    //     uint256 newId = mVest.pause(id, pauseStart, pauseEnd);

    //     // make sure old id is yanked by setting tot to 0 because it is inside cliff still
    //     (address usr, uint48 bgn, uint48 clf, uint48 fin, , , uint128 tot, ) = mVest.awards(id);
    //     assertEq(usr, _usr, "user is not the same");
    //     assertEq(uint256(bgn), startOfTime, "start is wrong");
    //     assertEq(uint256(fin), pauseStart, "finish is wrong");
    //     assertEq(uint256(tot), 0, "total is wrong");

    //     // make sure new id has proper values
    //     (usr, bgn, clf, fin, , , tot, ) = mVest.awards(newId);
    //     assertEq(usr, _usr, "new user is not the same");
    //     assertEq(uint256(bgn), pauseEnd - 3, "new start is wrong"); // because 3 days of cliff had already passed
    //     assertEq(uint256(clf), pauseEnd + 7, "new cliff is wrong"); // because 7 days of cliff remain
    //     assertEq(uint256(tot), total, "new total is wrong");
    //     assertEq(uint256(fin), pauseEnd + 97, "new end is wrong"); // because pause started after 3 days

    //     // go to end of vestings and claim all. It must match the total
    //     vm.warp(pauseEnd + 100);
    //     vm.startPrank(_usr);
    //     mVest.vest(newId, type(uint256).max);
    //     mVest.vest(id, type(uint256).max);

    //     assertEq(gem.balanceOf(_usr), total, "balance is wrong");
    // }

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
