// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.23;

import "../TokenSwap.sol";
import "./CloneFactory.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

/**
 * @title TokenSwapCloneFactory
 * @author malteish
 * @notice Use this contract to create deterministic clones of TokenSwap contracts
 */
contract TokenSwapCloneFactory is CloneFactory {
    constructor(address _implementation) CloneFactory(_implementation) {}

    /**
     * Create a new clone and return its address. All parameters change the address of the clone.
     * @param _rawSalt influences the address of the clone, but not the initialization
     * @param _trustedForwarder can not be changed, but is checked for security
     * @param _arguments struct with all the initialization parameters
     */
    function createTokenSwapClone(
        bytes32 _rawSalt,
        address _trustedForwarder,
        TokenSwapInitializerArguments memory _arguments
    ) external returns (address) {
        bytes32 salt = _getSalt(_rawSalt, _trustedForwarder, _arguments);
        TokenSwap tokenSwap = TokenSwap(Clones.cloneDeterministic(implementation, salt));
        require(
            tokenSwap.isTrustedForwarder(_trustedForwarder),
            "TokenSwapCloneFactory: Unexpected trustedForwarder"
        );
        tokenSwap.initialize(_arguments);
        emit NewClone(address(tokenSwap));
        return address(tokenSwap);
    }

    /**
     * Return the address a clone would have if it was created with these parameters.
     * @param _rawSalt influences the address of the clone, but not the initialization
     * @param _trustedForwarder can not be changed, but is checked for security
     * @param _arguments struct with all the initialization parameters
     */
    function predictCloneAddress(
        bytes32 _rawSalt,
        address _trustedForwarder,
        TokenSwapInitializerArguments memory _arguments
    ) external view returns (address) {
        bytes32 salt = _getSalt(_rawSalt, _trustedForwarder, _arguments);
        return Clones.predictDeterministicAddress(implementation, salt);
    }

    /**
     * @notice generates a salt from all input parameters
     * @param _rawSalt The salt used to deterministically generate the clone address
     * @param _trustedForwarder The trustedForwarder that will be used to initialize the clone
     * @param _arguments The arguments that will be used to initialize the clone
     * @return salt to be used for clone generation
     * @dev This function does not check if the clone has already been created
     */
    function _getSalt(
        bytes32 _rawSalt,
        address _trustedForwarder,
        TokenSwapInitializerArguments memory _arguments
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(_rawSalt, _trustedForwarder, _arguments));
    }
}
