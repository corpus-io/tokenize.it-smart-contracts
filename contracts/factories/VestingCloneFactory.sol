// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "../Vesting.sol";
import "./CloneFactory.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract VestingCloneFactory is CloneFactory {
    constructor(address _implementation) CloneFactory(_implementation) {}

    function createVestingClone(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        address _token
    ) external returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(_rawSalt, _trustedForwarder, _owner, _token));
        address clone = Clones.cloneDeterministic(implementation, salt);
        Vesting vesting = Vesting(clone);
        require(vesting.isTrustedForwarder(_trustedForwarder), "VestingCloneFactory: Unexpected trustedForwarder");
        vesting.initialize(_owner, _token);
        emit NewClone(clone);
        return clone;
    }

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
        bytes32 salt = keccak256(abi.encodePacked(_rawSalt, _trustedForwarder, _owner, _token));
        return Clones.predictDeterministicAddress(implementation, salt);
    }
}
