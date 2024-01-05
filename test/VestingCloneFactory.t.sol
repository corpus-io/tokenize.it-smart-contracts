// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../contracts/factories/VestingCloneFactory.sol";

contract VestingCloneFactoryTest is Test {
    event NewClone(address clone);
    Vesting implementation;
    VestingCloneFactory factory;

    address trustedForwarder = address(1);

    function setUp() public {
        implementation = new Vesting(trustedForwarder);

        factory = new VestingCloneFactory(address(implementation));
    }

    function testAddressPrediction(bytes32 _salt, address _trustedForwarder, address _owner, address _token) public {
        vm.assume(_trustedForwarder != address(0));
        vm.assume(_token != address(0));
        vm.assume(_owner != address(0));
        Vesting _implementation = new Vesting(_trustedForwarder);
        VestingCloneFactory _factory = new VestingCloneFactory(address(_implementation));

        bytes32 salt = keccak256(abi.encode(_salt, _trustedForwarder, _owner, _token));
        address expected1 = _factory.predictCloneAddress(salt);
        address expected2 = _factory.predictCloneAddress(_salt, _trustedForwarder, _owner, _token);
        assertEq(expected1, expected2, "address prediction with salt and params not equal");

        vm.expectEmit(true, true, true, true, address(_factory));
        emit NewClone(expected1);
        address actual = _factory.createVestingClone(_salt, _trustedForwarder, _owner, _token);
        assertEq(expected1, actual, "address prediction failed");
    }

    function testLockUpAddressPrediction(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        address _token,
        uint256 _allocation,
        address _beneficiary,
        uint64 _start,
        uint64 _cliff,
        uint64 _duration
    ) public {
        vm.assume(_owner != address(1));
        vm.assume(
            _trustedForwarder != address(0) &&
                _trustedForwarder != address(1) &&
                _trustedForwarder != address(this) &&
                _trustedForwarder != address(factory)
        );
        vm.assume(_token != address(0) && _token != address(1));
        vm.assume(_allocation != 0 && _allocation != 1);
        vm.assume(_beneficiary != address(0) && _beneficiary != address(1));
        vm.assume(_start != 0 && _start != 1);
        vm.assume(_cliff != 0 && _cliff != 1);
        vm.assume(_duration != 0 && _duration != 1);
        vm.assume(_rawSalt != bytes32("a"));
        Vesting _implementation = new Vesting(_trustedForwarder);
        VestingCloneFactory _factory = new VestingCloneFactory(address(_implementation));

        address expected = _factory.predictCloneAddressWithLockupPlan(
            _rawSalt,
            _trustedForwarder,
            _owner,
            _token,
            _allocation,
            _beneficiary,
            _start,
            _cliff,
            _duration
        );

        vm.expectEmit(true, true, true, true, address(_factory));
        emit NewClone(expected);
        address actual = _factory.createVestingCloneWithLockupPlan(
            _rawSalt,
            _trustedForwarder,
            _owner,
            _token,
            _allocation,
            _beneficiary,
            _start,
            _cliff,
            _duration
        );
        assertEq(expected, actual, "address prediction failed: expected != actual");

        // test changing the salt changes the address
        address changedAddress = _factory.predictCloneAddressWithLockupPlan(
            bytes32("a"),
            _trustedForwarder,
            _owner,
            _token,
            _allocation,
            _beneficiary,
            _start,
            _cliff,
            _duration
        );
        assertNotEq(actual, changedAddress, "address prediction failed: salt");

        // ensure changing the trustedForwarder reverts
        vm.expectRevert("VestingCloneFactory: Unexpected trustedForwarder");
        _factory.predictCloneAddressWithLockupPlan(
            _rawSalt,
            address(1),
            _owner,
            _token,
            _allocation,
            _beneficiary,
            _start,
            _cliff,
            _duration
        );

        // test changing the owner changes the address
        changedAddress = _factory.predictCloneAddressWithLockupPlan(
            _rawSalt,
            _trustedForwarder,
            address(1),
            _token,
            _allocation,
            _beneficiary,
            _start,
            _cliff,
            _duration
        );
        assertNotEq(actual, changedAddress, "address prediction failed: owner");

        // test changing the token changes the address
        changedAddress = _factory.predictCloneAddressWithLockupPlan(
            _rawSalt,
            _trustedForwarder,
            _owner,
            address(1),
            _allocation,
            _beneficiary,
            _start,
            _cliff,
            _duration
        );
        assertNotEq(actual, changedAddress, "address prediction failed: token");

        // test changing the allocation changes the address
        changedAddress = _factory.predictCloneAddressWithLockupPlan(
            _rawSalt,
            _trustedForwarder,
            _owner,
            _token,
            1,
            _beneficiary,
            _start,
            _cliff,
            _duration
        );
        assertNotEq(actual, changedAddress, "address prediction failed: allocation");

        // test changing the beneficiary changes the address
        changedAddress = _factory.predictCloneAddressWithLockupPlan(
            _rawSalt,
            _trustedForwarder,
            _owner,
            _token,
            _allocation,
            address(1),
            _start,
            _cliff,
            _duration
        );
        assertNotEq(actual, changedAddress, "address prediction failed: beneficiary");

        // test changing the start changes the address
        changedAddress = _factory.predictCloneAddressWithLockupPlan(
            _rawSalt,
            _trustedForwarder,
            _owner,
            _token,
            _allocation,
            _beneficiary,
            1,
            _cliff,
            _duration
        );
        assertNotEq(actual, changedAddress, "address prediction failed: start");

        // test changing the cliff changes the address
        changedAddress = _factory.predictCloneAddressWithLockupPlan(
            _rawSalt,
            _trustedForwarder,
            _owner,
            _token,
            _allocation,
            _beneficiary,
            _start,
            1,
            _duration
        );
        assertNotEq(actual, changedAddress, "address prediction failed: cliff");

        // test changing the duration changes the address
        changedAddress = _factory.predictCloneAddressWithLockupPlan(
            _rawSalt,
            _trustedForwarder,
            _owner,
            _token,
            _allocation,
            _beneficiary,
            _start,
            _cliff,
            1
        );
        assertNotEq(actual, changedAddress, "address prediction failed: duration");
    }

    function testWrongTrustedForwarderReverts(address _wrongTrustedForwarder) public {
        vm.assume(_wrongTrustedForwarder != address(0));
        vm.assume(_wrongTrustedForwarder != trustedForwarder);

        bytes32 _salt = keccak256(abi.encode(_wrongTrustedForwarder));
        address _owner = address(2);
        address _token = address(3);

        // test wrong trustedForwarder reverts
        vm.expectRevert("VestingCloneFactory: Unexpected trustedForwarder");
        factory.predictCloneAddress(_salt, _wrongTrustedForwarder, _owner, _token);

        vm.expectRevert("VestingCloneFactory: Unexpected trustedForwarder");
        factory.createVestingClone(_salt, _wrongTrustedForwarder, _owner, _token);
    }

    function testSecondDeploymentFails(bytes32 _salt, address _owner, address _token) public {
        vm.assume(_owner != address(0));
        vm.assume(_token != address(0));

        factory.createVestingClone(_salt, trustedForwarder, _owner, _token);

        vm.expectRevert("ERC1167: create2 failed");
        factory.createVestingClone(_salt, trustedForwarder, _owner, _token);
    }

    function testInitialization(bytes32 _salt, address _owner, address _token) public {
        vm.assume(_owner != address(0));
        vm.assume(_token != address(0));

        Vesting clone = Vesting(factory.createVestingClone(_salt, trustedForwarder, _owner, _token));

        // test constructor arguments are used
        assertEq(clone.owner(), _owner, "name not set");

        // check trustedForwarder is set
        assertTrue(clone.isTrustedForwarder(trustedForwarder), "trustedForwarder not set");

        // test contract can not be initialized again
        vm.expectRevert("Initializable: contract is already initialized");
        clone.initialize(_owner, _token);
    }
}
