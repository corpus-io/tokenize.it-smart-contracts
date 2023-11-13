// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "./Vesting.sol";
import "./CloneFactory.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract VestingCloneFactory is CloneFactory {
    constructor(address _implementation) CloneFactory(_implementation) {}

    function createVestingClone(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner
    ) external returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(_rawSalt, _trustedForwarder, _owner));
        address clone = Clones.cloneDeterministic(implementation, salt);
        VestingWalletUpgradeable vesting = VestingWalletUpgradeable(clone);
        require(vesting.isTrustedForwarder(_trustedForwarder), "VestingCloneFactory: Unexpected trustedForwarder");
        vesting.initialize(_owner);
        emit NewClone(clone);
        return clone;
    }

    function predictCloneAddress(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner
    ) external view returns (address) {
        require(
            VestingWalletUpgradeable(implementation).isTrustedForwarder(_trustedForwarder),
            "VestingCloneFactory: Unexpected trustedForwarder"
        );
        bytes32 salt = keccak256(abi.encodePacked(_rawSalt, _trustedForwarder, _owner));
        return Clones.predictDeterministicAddress(implementation, salt);
    }
}
