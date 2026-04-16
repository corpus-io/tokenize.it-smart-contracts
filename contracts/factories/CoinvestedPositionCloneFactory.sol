// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.23;

import "@openzeppelin/contracts/proxy/Clones.sol";

import "../CoinvestedPosition.sol";
import "./CloneFactory.sol";

/**
 * @title CoinvestedPositionCloneFactory
 * @author malteish
 * @notice Use this contract to create deterministic clones of CoinvestedPosition contracts
 */
contract CoinvestedPositionCloneFactory is CloneFactory {
    constructor(address _implementation) CloneFactory(_implementation) {}

    /**
     * @notice Create a new CoinvestedPosition clone and initialize it.
     * @param _rawSalt influences the address of the clone, but not the initialization
     * @param _trustedForwarder can not be changed, but is checked for security
     * @param _arguments struct with all the initialization parameters
     */
    function createCoinvestedPositionClone(
        bytes32 _rawSalt,
        address _trustedForwarder,
        CoinvestedPositionInitializerArguments memory _arguments
    ) external returns (address) {
        bytes32 salt = _getSalt(_rawSalt, _trustedForwarder, _arguments);
        CoinvestedPosition clone = CoinvestedPosition(Clones.cloneDeterministic(implementation, salt));
        require(
            clone.isTrustedForwarder(_trustedForwarder),
            "CoinvestedPositionCloneFactory: Unexpected trustedForwarder"
        );
        clone.initialize(_arguments);
        emit NewClone(address(clone));
        return address(clone);
    }

    /**
     * @notice Return the address a clone would have if it was created with these parameters.
     * @param _rawSalt influences the address of the clone, but not the initialization
     * @param _trustedForwarder can not be changed, but is checked for security
     * @param _arguments struct with all the initialization parameters
     */
    function predictCloneAddress(
        bytes32 _rawSalt,
        address _trustedForwarder,
        CoinvestedPositionInitializerArguments memory _arguments
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
     */
    function _getSalt(
        bytes32 _rawSalt,
        address _trustedForwarder,
        CoinvestedPositionInitializerArguments memory _arguments
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(_rawSalt, _trustedForwarder, _arguments));
    }
}
