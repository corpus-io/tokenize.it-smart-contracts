// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "../common/Errors.sol";

/**
 * @title Factory
 * @author malteish
 * @notice inherit from this contract to create a factory for a specific contract
 */

abstract contract Factory {
    /// @notice Reverted when the implementation address passed to the constructor is zero.
    error ZeroImplementationAddress();

    /// The address of the implementation contract
    address public immutable implementation;

    constructor(address _implementation) {
        require(_implementation != address(0), ZeroImplementationAddress());
        implementation = _implementation;
    }
}
