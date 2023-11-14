// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../contracts/VestingCloneFactory.sol";
import "./resources/ERC20MintableByAnyone.sol";

contract VestingBlindTest is Test {
    event Commit(bytes32);
    event Revoke(bytes32);
    event Reveal(bytes32, uint64 id);

    Vesting implementation;
    VestingCloneFactory factory;

    address owner = address(7);

    ERC20MintableByAnyone token = new ERC20MintableByAnyone("test token", "TST");

    Vesting vesting;

    address trustedForwarder = address(1);
    address platformAdmin = address(2);

    function setUp() public {
        implementation = new Vesting(trustedForwarder);
        vm.warp(implementation.TIME_HORIZON());

        factory = new VestingCloneFactory(address(implementation));

        vesting = Vesting(factory.createVestingClone(0, trustedForwarder, owner, address(token)));
    }

    function testCommit(bytes32 hash) public {
        vm.assume(hash != bytes32(0));
        assertTrue(vesting.commitments(hash) == 0, "commitment already exists");
        vm.prank(owner);
        vesting.commit(hash);
        assertTrue(vesting.commitments(hash) == type(uint64).max, "commitment does not exist");
    }

    function testCommitNoManager(address noOwner, bytes32 hash) public {
        vm.assume(noOwner != address(0));
        vm.assume(vesting.managers(noOwner) == false);
        vm.assume(hash != bytes32(0));
        vm.expectRevert("Caller is not a manager");
        vm.prank(noOwner);
        vesting.commit(hash);
    }

    function testRevokeNow(bytes32 hash) public {
        vm.assume(hash != bytes32(0));
        vm.prank(owner);
        vesting.commit(hash);
        assertTrue(vesting.commitments(hash) == type(uint64).max, "commitment does not exist");
        vm.prank(owner);
        vesting.revoke(hash, uint64(block.timestamp));
        assertTrue(vesting.commitments(hash) == block.timestamp, "revocation not correct");
    }

    function testRevokeLater(bytes32 hash, uint64 end) public {
        vm.assume(hash != bytes32(0));
        vm.assume(end > block.timestamp);
        vm.prank(owner);
        vesting.commit(hash);
        assertTrue(vesting.commitments(hash) > 0, "commitment does not exist");
        vm.prank(owner);
        vesting.revoke(hash, end);
        assertTrue(vesting.commitments(hash) == end, "revocation not correct");
    }

    function testRevokeNoOwner(address noOwner, bytes32 hash) public {
        vm.assume(noOwner != address(0));
        vm.assume(vesting.managers(noOwner) == false);
        vm.assume(hash != bytes32(0));
        vm.prank(owner);
        vesting.commit(hash);

        assertTrue(vesting.commitments(hash) == type(uint64).max, "commitment does not exist");
        vm.prank(noOwner);
        vm.expectRevert("Caller is not a manager");
        vesting.revoke(hash, uint64(block.timestamp));
        assertEq(vesting.commitments(hash), type(uint64).max, "commitment has been revoked");
    }

    function testReveal(
        address _beneficiary,
        uint256 _allocation,
        uint64 _start,
        uint64 _duration,
        uint64 _cliff,
        bytes32 _salt,
        bool _isMintable,
        address _rando
    ) public {
        vm.assume(checkLimits(_allocation, _beneficiary, _start, _cliff, _duration, vesting, block.timestamp));
        vm.assume(_rando != address(0));
        bytes32 hash = keccak256(
            abi.encodePacked(_allocation, _beneficiary, _start, _cliff, _duration, _isMintable, _salt)
        );

        // commit
        assertTrue(vesting.commitments(hash) == 0, "commitment already exists");
        vm.expectEmit(true, true, true, true, address(vesting));
        emit Commit(hash);
        vm.prank(owner);
        vesting.commit(hash);
        assertTrue(vesting.commitments(hash) > 0, "commitment does not exist");

        // reveal
        vm.expectEmit(true, true, true, true, address(vesting));
        emit Reveal(hash, 0);
        vm.prank(_rando);
        uint64 id = vesting.reveal(hash, _allocation, _beneficiary, _start, _cliff, _duration, _isMintable, _salt);
        assertEq(id, 0, "id is not 0");

        checkVestingPlanDetails(id, _beneficiary, _allocation, _start, _duration, _cliff, _isMintable, vesting);

        // make sure the commitment is deleted
        assertTrue(vesting.commitments(hash) == 0, "commitment still exists");

        // make sure a second creation fails
        vm.expectRevert("commitment-not-found");
        vm.prank(_rando);
        vesting.reveal(hash, _allocation, _beneficiary, _start, _cliff, _duration, _isMintable, _salt);
    }

    // function testClaimAfterRevoke() public {
    //     address _beneficiary = address(1);
    //     uint128 commitmentTot = 100;
    //     uint128 realTot = 75;
    //     uint64 _start = 40 * 365 days;
    //     uint64 _duration = 2 * 365 days;
    //     uint64 _cliff = 1 * 365 days;
    //     address _mgr = address(0);
    //     bytes32 _salt = 0;

    //     vm.warp(_start - 1 days);
    //     vm.assume(checkLimits(_beneficiary, commitmentTot, _start, _duration, _cliff, DssVest(vesting), block.timestamp));
    //     bytes32 hash = keccak256(
    //         abi.encodePacked(_beneficiary, uint256(commitmentTot), uint256(_start), uint256(_duration), uint256(_cliff), _mgr, _salt)
    //     );

    //     // commit
    //     assertTrue(vesting.commitments(hash) == false, "commitment already exists");
    //     vm.expectEmit(true, true, true, true, address(vesting));
    //     emit Commit(hash);
    //     vm.prank(owner);
    //     vesting.commit(hash);
    //     assertTrue(vesting.commitments(hash) > 0, "commitment does not exist");

    //     // warp to 1.5 years into the vesting period and revoke
    //     vm.warp(_start + _cliff + _duration / 4);
    //     vm.prank(owner);
    //     vesting.revoke(hash, block.timestamp);
    //     assertTrue(vesting.commitments(hash) == block.timestamp, "revocation not correct");

    //     // warp till end of vesting and claim
    //     vm.warp(_start + _cliff + _duration + 1);
    //     vm.expectEmit(true, true, true, true, address(vesting));
    //     emit Claim(hash, 1);
    //     uint256 id = vesting.reveal(hash, _beneficiary, commitmentTot, _start, _duration, _cliff, _mgr, _salt);
    //     assertEq(id, 1, "id is not 0");

    //     checkVestingPlanDetails(id, _beneficiary, realTot, _start, 1.5 * 365 days, _cliff, _mgr, 0);

    //     // make sure the commitment is deleted
    //     assertTrue(vesting.commitments(hash) == false, "commitment still exists");

    //     // make sure a second creation fails
    //     vm.expectRevert("DssVest/commitment-not-found");
    //     vesting.reveal(hash, _beneficiary, commitmentTot, _start, _duration, _cliff, _mgr, _salt);

    //     // vest everything
    //     vm.prank(_beneficiary);
    //     vesting.vest(id);
    //     assertEq(realTot, gem.balanceOf(_beneficiary), "balance is not equal to total");
    // }

    // function testRevokeBeforeCliff(
    //     address _beneficiary,
    //     uint128 _allocation,
    //     uint64 _start,
    //     uint24 _duration24,
    //     uint24 _cliff24,
    //     address _mgr,
    //     bytes32 _salt,
    //     uint24 revokeAfter24
    // ) public {
    //     uint64 _duration = _duration24;
    //     uint64 _cliff = _cliff24;
    //     uint64 revokeAfter = revokeAfter24;
    //     vm.assume(revokeAfter < _cliff);
    //     vm.assume(checkLimits(_beneficiary, _allocation, _start, _cliff, _duration, DssVest(vesting), block.timestamp));
    //     bytes32 hash = keccak256(
    //         abi.encodePacked(_beneficiary, uint256(_allocation), uint256(_start), uint256(_duration), uint256(_cliff), _mgr, _salt)
    //     );

    //     // commit
    //     assertTrue(vesting.commitments(hash) == false, "commitment already exists");
    //     vm.expectEmit(true, true, true, true, address(vesting));
    //     emit Commit(hash);
    //     vm.prank(owner);
    //     vesting.commit(hash);
    //     assertTrue(vesting.commitments(hash) > 0, "commitment does not exist");

    //     // revoke
    //     uint256 end = _start + revokeAfter;
    //     vm.warp(end);
    //     vm.expectEmit(true, true, true, true, address(vesting));
    //     emit Revoke(hash, end);
    //     vm.prank(owner);
    //     vesting.revoke(hash, end);

    //     // claim
    //     vm.expectRevert("DssVest/commitment-revoked-before-cliff");
    //     vesting.reveal(hash, _beneficiary, _allocation, _start, _duration, _cliff, _mgr, _salt);

    //     // make sure nothing changed
    //     assertTrue(vesting.commitments(hash) > 0, "commitment does not exist");
    //     assertTrue(vesting.commitments(hash) == end, "revocation not correct");
    //     assertTrue(vesting.ids() == 0, "a vesting plan has been created");
    // }

    // function testRevokeBeforeEnd(uint64 _duration, uint64 _cliff, uint64 revokeAfter) public {
    //     uint128 _allocation = 8127847e18;
    //     uint64 _start = 60 * 365 days;
    //     bytes32 _salt = 0;

    //     vm.assume(revokeAfter < type(uint24).max && revokeAfter > 0);
    //     vm.assume(_cliff < type(uint24).max);
    //     vm.assume(_duration < type(uint24).max && _duration > 0);
    //     vm.assume(_duration > revokeAfter);
    //     vm.assume(_cliff < revokeAfter);
    //     vm.assume(_allocation > 0);
    //     vm.assume(type(uint256).max / _allocation > revokeAfter); // prevent overflow
    //     vm.assume(checkLimits(usr, _allocation, _start, _duration, _cliff, DssVest(vesting), block.timestamp));
    //     bytes32 hash = keccak256(
    //         abi.encodePacked(usr, uint256(_allocation), uint256(_start), uint256(_duration), uint256(_cliff), owner, _salt)
    //     );

    //     // commit
    //     assertTrue(vesting.commitments(hash) == false, "commitment already exists");
    //     vm.expectEmit(true, true, true, true, address(vesting));
    //     emit Commit(hash);
    //     vm.prank(owner);
    //     vesting.commit(hash);
    //     assertTrue(vesting.commitments(hash) > 0, "commitment does not exist");

    //     // revoke
    //     vm.warp(_start);
    //     uint256 end = _start + revokeAfter;
    //     vm.prank(owner);
    //     vm.expectEmit(true, true, true, true, address(vesting));
    //     emit Revoke(hash, end);
    //     vesting.revoke(hash, end);

    //     // claim
    //     vm.warp(uint256(_start) + uint256(_duration) + 1);

    //     uint256 newTot = (_allocation * uint256(revokeAfter)) / uint256(_duration);
    //     if (newTot == 0) {
    //         console.log("newTot is 0");
    //         vm.prank(usr);
    //         vm.expectRevert("DssVest/no-vest-total-amount");
    //         vesting.claimAndVest(hash, usr, _allocation, _start, _duration, _cliff, owner, _salt);
    //         // assure no vesting plan has been created
    //         assertTrue(vesting.ids() == 0, "a vesting plan has been created");
    //     } else {
    //         console.log("newTot is not 0");
    //         vm.prank(usr);
    //         vesting.claimAndVest(hash, usr, _allocation, _start, _duration, _cliff, owner, _salt);
    //         // check correct execution
    //         assertTrue(vesting.commitments(hash) == false, "commitment still exists");
    //         assertTrue(vesting.commitments(hash) == _start + revokeAfter, "revocation not correct");
    //         assertTrue(vesting.ids() == 1, "no vesting plan has been created");
    //         assertTrue(vesting.accrued(1) == newTot, "accrued is not new total");
    //         assertTrue(vesting.unpaid(1) == 0, "unpaid is not 0");
    //         assertTrue(gem.balanceOf(usr) == newTot, "balance is not equal to new total");
    //     }
    // }

    // function testRevokeAfterEnd(uint64 _duration, uint64 _cliff, uint64 revokeAfter) public {
    //     uint128 _allocation = 8127847e18;
    //     uint64 _start = 60 * 365 days;
    //     bytes32 _salt = 0;

    //     vm.assume(revokeAfter < type(uint24).max && revokeAfter > 0);
    //     vm.assume(_cliff < type(uint24).max);
    //     vm.assume(_duration < type(uint24).max && _duration > 0);
    //     vm.assume(_duration < revokeAfter); // this means that the vesting plan is already over at the time it is revoked
    //     vm.assume(_allocation > 0);
    //     vm.assume(type(uint256).max / _allocation > revokeAfter); // prevent overflow
    //     vm.assume(checkLimits(usr, _allocation, _start, _duration, _cliff, DssVest(vesting), block.timestamp));
    //     bytes32 hash = keccak256(
    //         abi.encodePacked(usr, uint256(_allocation), uint256(_start), uint256(_duration), uint256(_cliff), owner, _salt)
    //     );

    //     // commit
    //     assertTrue(vesting.commitments(hash) == false, "commitment already exists");
    //     vm.expectEmit(true, true, true, true, address(vesting));
    //     emit Commit(hash);
    //     vm.prank(owner);
    //     vesting.commit(hash);
    //     assertTrue(vesting.commitments(hash) > 0, "commitment does not exist");

    //     // revoke
    //     vm.warp(_start);
    //     uint256 end = _start + revokeAfter;
    //     vm.prank(owner);
    //     vm.expectEmit(true, true, true, true, address(vesting));
    //     emit Revoke(hash, end);
    //     vesting.revoke(hash, end);

    //     // claim
    //     vm.warp(uint256(_start) + uint256(_duration) + 1);

    //     vm.prank(usr);
    //     vesting.claimAndVest(hash, usr, _allocation, _start, _duration, _cliff, owner, _salt);
    //     // check correct execution
    //     assertTrue(vesting.commitments(hash) == false, "commitment still exists");
    //     assertTrue(vesting.commitments(hash) == _start + revokeAfter, "revocation not correct");
    //     assertTrue(vesting.ids() == 1, "no vesting plan has been created");
    //     assertTrue(vesting.accrued(1) == _allocation, "accrued is not original total amount");
    //     assertTrue(vesting.unpaid(1) == 0, "unpaid is not 0");
    //     assertTrue(gem.balanceOf(usr) == _allocation, "balance is not equal to total");
    // }

    // function testRevokeAndYankBehaveEqual(uint64 _duration, uint64 _cliff, uint128 _allocation, uint64 revokeAfter) public {
    //     // uint128 _allocation = 8127847e18;
    //     uint64 _start = 60 * 365 days;
    //     bytes32 _salt = 0;

    //     vm.assume(revokeAfter < type(uint24).max && revokeAfter > 0);
    //     vm.assume(_cliff < type(uint24).max);
    //     vm.assume(_duration < type(uint24).max && _duration > 0);
    //     vm.assume(_allocation > 0);
    //     vm.assume(type(uint256).max / _allocation > revokeAfter); // prevent overflow
    //     vm.assume(checkLimits(usr, _allocation, _start, _duration, _cliff, DssVest(vesting), block.timestamp));
    //     bytes32 hash = keccak256(
    //         abi.encodePacked(usrCommit, uint256(_allocation), uint256(_start), uint256(_duration), uint256(_cliff), owner, _salt)
    //     );

    //     // commit to a vesting plan
    //     assertTrue(vesting.commitments(hash) == false, "commitment already exists");
    //     vm.prank(owner);
    //     vesting.commit(hash);
    //     assertTrue(vesting.commitments(hash) > 0, "commitment does not exist");

    //     // create a vesting plan with the same parameters but a different receiver
    //     vm.prank(owner);
    //     uint256 planId = vesting.create(usrCreate, _allocation, _start, _duration, _cliff, owner);

    //     // revoke the commitment
    //     vm.warp(_start);
    //     uint256 end = _start + revokeAfter;
    //     vm.prank(owner);
    //     vm.expectEmit(true, true, true, true, address(vesting));
    //     emit Revoke(hash, end);
    //     vesting.revoke(hash, end);

    //     // yank the vesting plan
    //     vm.prank(owner);
    //     vesting.yank(planId, end);

    //     // fast forowner to the end of the vesting period
    //     vm.warp(uint256(_start) + uint256(_duration) + 1);

    //     vm.prank(usrCreate);
    //     vesting.vest(planId);
    //     console.log("usrCreate balance: ", gem.balanceOf(usrCreate));

    //     if (gem.balanceOf(usrCreate) == 0) {
    //         console.log("User gets no tokens, so claim must fail");
    //         vm.prank(usrCommit);
    //         vm.expectRevert(); // "DssVest/no-vest-total-amount" or "DssVest/commitment-revoked-before-cliff"
    //         vesting.claimAndVest(hash, usrCommit, _allocation, _start, _duration, _cliff, owner, _salt);
    //         // assure no vesting plan has been created
    //         assertTrue(vesting.ids() == planId, "a vesting plan has been created");
    //     } else {
    //         console.log("User gets tokens");
    //         vm.prank(usrCommit);
    //         vesting.claimAndVest(hash, usrCommit, _allocation, _start, _duration, _cliff, owner, _salt);

    //         console.log("usrCommit balance: ", gem.balanceOf(usrCommit));
    //         // check correct execution
    //         assertTrue(vesting.commitments(hash) == false, "commitment still exists");
    //         assertTrue(vesting.commitments(hash) == _start + revokeAfter, "revocation not correct");
    //         assertTrue(vesting.ids() == planId + 1, "no vesting plan has been created");
    //         assertTrue(vesting.accrued(1) == gem.balanceOf(usrCreate), "accrued is not new total");
    //         assertTrue(vesting.unpaid(1) == 0, "unpaid is not 0");
    //         assertTrue(gem.balanceOf(usrCommit) == gem.balanceOf(usrCreate), "balance is not equal to new total");
    //     }
    // }

    // function testClaimWithModifiedData(address _beneficiary, address _beneficiary2, uint128 _allocation, uint128 _allocation2, bytes32 _salt) public {
    //     vm.assume(_beneficiary != address(0));
    //     vm.assume(_beneficiary2 != address(0));
    //     vm.assume(_beneficiary2 != _beneficiary);
    //     vm.assume(_allocation2 != 0 && _allocation != 0 && _allocation2 != _allocation);

    //     uint64 _start = uint64(block.timestamp + 400 days);
    //     uint64 _duration = 600 days;
    //     uint64 _cliff = 200 days;
    //     address _mgr = address(6);

    //     bytes32 hash = keccak256(
    //         abi.encodePacked(_beneficiary, uint256(_allocation), uint256(_start), uint256(_duration), uint256(_cliff), _mgr, _salt)
    //     );

    //     // commit
    //     assertTrue(vesting.commitments(hash) == false, "commitment already exists");
    //     vm.prank(owner);
    //     vesting.commit(hash);
    //     assertTrue(vesting.commitments(hash) > 0, "commitment does not exist");

    //     // claim
    //     vm.expectRevert("DssVest/invalid-hash");
    //     vesting.reveal(hash, _beneficiary2, _allocation, _start, _duration, _cliff, _mgr, _salt);

    //     vm.expectRevert("DssVest/invalid-hash");
    //     vesting.reveal(hash, _beneficiary, _allocation2, _start, _duration, _cliff, _mgr, _salt);
    // }

    // function testClaimAndVest(
    //     address _beneficiary,
    //     uint128 _allocation,
    //     uint64 _start,
    //     uint64 _duration,
    //     uint64 _cliff,
    //     address _mgr,
    //     bytes32 _salt,
    //     address _rando
    // ) public {
    //     vm.assume(checkLimits(_beneficiary, _allocation, _start, _cliff, _duration, DssVest(vesting), block.timestamp));
    //     vm.assume(_rando != address(0) && _rando != _beneficiary && _rando != address(forownerer));
    //     bytes32 hash = keccak256(
    //         abi.encodePacked(_beneficiary, uint256(_allocation), uint256(_start), uint256(_duration), uint256(_cliff), _mgr, _salt)
    //     );

    //     // commit
    //     assertTrue(vesting.commitments(hash) == false, "commitment already exists");
    //     vm.expectEmit(true, true, true, true, address(vesting));
    //     emit Commit(hash);
    //     vm.prank(owner);
    //     vesting.commit(hash);
    //     assertTrue(vesting.commitments(hash) > 0, "commitment does not exist");

    //     // ensure state is as expected before claiming
    //     assertTrue(gem.balanceOf(_beneficiary) == 0, "balance is not 0");
    //     assertTrue(vesting.ids() == 0, "id is not 0");
    //     assertEq(vesting.commitments(hash), true, "commitment does not exist");

    //     // 3rd parties can not claim and vest because vests are restricted by default
    //     vm.prank(_rando);
    //     vm.expectRevert("DssVest/only-user-can-claim");
    //     vesting.claimAndVest(hash, _beneficiary, _allocation, _start, _duration, _cliff, _mgr, _salt);

    //     // claim
    //     vm.prank(_beneficiary);
    //     uint256 id = vesting.claimAndVest(hash, _beneficiary, _allocation, _start, _duration, _cliff, _mgr, _salt);

    //     // ensure state changed as expected during claim
    //     assertEq(id, 1, "id is not 1");
    //     assertEq(vesting.unpaid(id), 0, "unpaid is not 0");
    //     assertEq(vesting.commitments(hash), false, "commitment not deleted");
    //     // before or after cliff is important
    //     if (block.timestamp > _start + _cliff) {
    //         console.log("After cliff");
    //         assertEq(vesting.accrued(id), gem.balanceOf(_beneficiary), "accrued is not equal to paid");
    //         checkVestingPlanDetails(id, _beneficiary, _allocation, _start, _duration, _cliff, _mgr, vesting.accrued(id));
    //     } else {
    //         console.log("Before cliff");
    //         checkVestingPlanDetails(id, _beneficiary, _allocation, _start, _duration, _cliff, _mgr, 0);
    //         assertEq(0, gem.balanceOf(_beneficiary), "payout before cliff");
    //     }

    //     // claiming again must fail
    //     vm.expectRevert("DssVest/commitment-not-found");
    //     vm.prank(_beneficiary);
    //     vesting.claimAndVest(hash, _beneficiary, _allocation, _start, _duration, _cliff, _mgr, _salt);

    //     // warp time till end of vesting and vest everything
    //     vm.warp(_start + _duration + 1);
    //     vm.prank(_beneficiary);
    //     vesting.vest(id);
    //     assertEq(vesting.unpaid(id), 0, "unpaid is not 0");
    //     assertEq(vesting.accrued(id), _allocation, "accrued is not equal to total");
    //     assertEq(gem.balanceOf(_beneficiary), _allocation, "balance is not equal to total");
    // }

    function checkLimits(
        uint256 _allocation,
        address _beneficiary,
        uint64 _start,
        uint64 _cliff,
        uint64 _duration,
        Vesting _vesting,
        uint256 _timestamp
    ) public view returns (bool valid) {
        valid =
            _beneficiary != address(0) &&
            _beneficiary != address(trustedForwarder) &&
            _allocation != 0 &&
            _start > _timestamp - _vesting.TIME_HORIZON() + 1 days &&
            _start < _timestamp + _vesting.TIME_HORIZON() - 1 days &&
            _cliff < _vesting.TIME_HORIZON() &&
            _duration < _cliff &&
            _duration > 0;
    }

    function checkVestingPlanDetails(
        uint64 _id,
        address _beneficiary,
        uint256 _allocation,
        uint64 _start,
        uint64 _duration,
        uint64 _cliff,
        bool _isMintable,
        Vesting _vesting
    ) public {
        assertEq(_vesting.beneficiary(_id), _beneficiary, "wrong beneficiary");
        assertEq(_vesting.allocation(_id), _allocation, "wrong allocation");
        assertEq(_vesting.start(_id), _start, "wrong start");
        assertEq(_vesting.cliff(_id), _cliff, "wrong cliff");
        assertEq(_vesting.duration(_id), _duration, "wrong duration");
        assertEq(_vesting.isMintable(_id), _isMintable, "wrong mintable");
    }
}
