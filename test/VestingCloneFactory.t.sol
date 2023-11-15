// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../contracts/VestingCloneFactory.sol";

contract VestingCloneFactoryTest is Test {
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

        bytes32 salt = keccak256(abi.encodePacked(_salt, _trustedForwarder, _owner, _token));
        address expected1 = _factory.predictCloneAddress(salt);
        address expected2 = _factory.predictCloneAddress(_salt, _trustedForwarder, _owner, _token);
        assertEq(expected1, expected2, "address prediction with salt and params not equal");

        address actual = _factory.createVestingClone(_salt, _trustedForwarder, _owner, _token);
        assertEq(expected1, actual, "address prediction failed");
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
