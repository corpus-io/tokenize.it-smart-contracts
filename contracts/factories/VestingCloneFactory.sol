// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.23;

import "../Vesting.sol";
import "./CloneFactory.sol";

/**
 * @title VestingCloneFactory
 * @author malteish
 * @notice Create clones of a Vesting contract with deterministic addresses
 */
contract VestingCloneFactory is CloneFactory {
    constructor(address _implementation) CloneFactory(_implementation) {}

    /**
     * Create and initialize a clone
     * @param _rawSalt value that influences the address of the clone, but not the initialization
     * @param _trustedForwarder the trusted forwarder (ERC2771) can not be changed, but is checked for security
     * @param _owner address that will own the new clone
     * @param _token address of the token to be vested
     * @return address of the clone that was created
     */
    function createVestingClone(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        address _token
    ) public returns (address) {
        bytes32 salt = keccak256(abi.encode(_rawSalt, _trustedForwarder, _owner, _token));
        address clone = Clones.cloneDeterministic(implementation, salt);
        Vesting vesting = Vesting(clone);
        require(vesting.isTrustedForwarder(_trustedForwarder), "VestingCloneFactory: Unexpected trustedForwarder");
        vesting.initialize(_owner, _token);
        emit NewClone(clone);
        return clone;
    }

    /**
     * Create a new vesting clone with a lockup plan. The contract ownership can be renounced in the same transaction,
     * leaving the contract without an owner and thus without any way to change the vesting plan or add other plans.
     * @dev This function creates a transferrable vesting plan.
     * @param _rawSalt value that influences the address of the clone, but not the initialization
     * @param _trustedForwarder the trusted forwarder (ERC2771) can not be changed, but is checked for security
     * @param _owner future owner of the vesting contract. If 0, the contract will not have an owner.
     * @param _token token to vest
     * @param _allocation amount of tokens to vest
     * @param _beneficiary address receiving the tokens
     * @param _start start date of the vesting
     * @param _cliff cliff duration
     * @param _duration total duration
     */
    function createVestingCloneWithLockupPlan(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        address _token,
        uint256 _allocation,
        address _beneficiary,
        uint64 _start,
        uint64 _cliff,
        uint64 _duration
    ) external returns (address) {
        // deploy the vesting contract
        Vesting vesting = Vesting(createVestingClone(_rawSalt, _trustedForwarder, address(this), _token));

        // create the vesting plan
        vesting.createVesting(_allocation, _beneficiary, _start, _cliff, _duration, false); // this plan is not mintable

        // remove the manager role from the vesting contract
        vesting.removeManager(address(this));

        // transfer ownership of the vesting contract
        if (_owner == address(0)) {
            // if the owner is 0, the vesting contract will not have an owner. So no one can interfere with the vesting.
            vesting.renounceOwnership();
        } else {
            vesting.transferOwnership(_owner);
        }

        return address(vesting);
    }

    /**
     * Calculate the address a clone will have using the given parameters
     * @param _rawSalt value that influences the address of the clone, but not the initialization
     * @param _trustedForwarder the trusted forwarder (ERC2771) can not be changed, but is checked for security
     * @param _owner owner of the clone
     * @param _token token to vest
     */
    function predictCloneAddress(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        address _token
    ) external view returns (address) {
        require(
            Vesting(implementation).isTrustedForwarder(_trustedForwarder),
            "VestingCloneFactory: Unexpected trustedForwarder"
        );
        bytes32 salt = keccak256(abi.encode(_rawSalt, _trustedForwarder, _owner, _token));
        return Clones.predictDeterministicAddress(implementation, salt);
    }
}
