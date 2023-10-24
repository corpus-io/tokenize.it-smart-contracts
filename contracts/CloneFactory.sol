// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import "@openzeppelin/contracts/proxy/Clones.sol";

abstract contract CloneFactory {
    event NewClone(address clone);

    /// The address of the implementation to clone
    address immutable implementation;

    constructor(address _implementation) {
        require(_implementation != address(0), "CloneFactory: implementation can not be zero");
        implementation = _implementation;
    }

    /**
     * @notice Predicts the address of a clone that will be created
     * @param salt The salt used to deterministically generate the clone address
     * @return The address of the clone that will be created
     * @dev This function does not check if the clone has already been created
     */
    function predictCloneAddress(bytes32 salt) public view returns (address) {
        return Clones.predictDeterministicAddress(implementation, salt);
    }
}
