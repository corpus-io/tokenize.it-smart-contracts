// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.23;

import "../FeeSettings.sol";
import "./CloneFactory.sol";

/**
 * @title FeeSettingsCloneFactory
 * @author malteish
 * @notice Create clones of a FeeSettings contract with deterministic addresses
 */
contract FeeSettingsCloneFactory is CloneFactory {
    constructor(address _implementation) CloneFactory(_implementation) {}

    /**
     * Create a clone

     */
    function createFeeSettingsClone(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        Fees memory _fees,
        address _tokenFeeCollector,
        address _crowdinvestingFeeCollector,
        address _privateOfferFeeCollector
    ) external returns (address) {
        bytes32 salt = _generateSalt(
            _rawSalt,
            _trustedForwarder,
            _owner,
            _fees,
            _tokenFeeCollector,
            _crowdinvestingFeeCollector,
            _privateOfferFeeCollector
        );
        address clone = Clones.cloneDeterministic(implementation, salt);
        FeeSettings cloneFeeSettings = FeeSettings(clone);
        require(
            cloneFeeSettings.isTrustedForwarder(_trustedForwarder),
            "FeeSettingsCloneFactory: Unexpected trustedForwarder"
        );
        cloneFeeSettings.initialize(
            _owner,
            _fees,
            _tokenFeeCollector,
            _crowdinvestingFeeCollector,
            _privateOfferFeeCollector
        );
        emit NewClone(clone);
        return clone;
    }

    /**
     * Return the address a clone would have if it was created with these parameters.
     * @param _rawSalt this value influences the address of the clone, but not the initialization
     * @param _trustedForwarder the trusted forwarder (ERC2771) can not be changed, but is checked for security
     * @param _owner address that will own the new clone
     */
    function predictCloneAddress(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        Fees memory _fees,
        address _tokenFeeCollector,
        address _crowdinvestingFeeCollector,
        address _privateOfferFeeCollector
    ) external view returns (address) {
        bytes32 salt = _generateSalt(
            _rawSalt,
            _trustedForwarder,
            _owner,
            _fees,
            _tokenFeeCollector,
            _crowdinvestingFeeCollector,
            _privateOfferFeeCollector
        );
        return Clones.predictDeterministicAddress(implementation, salt);
    }

    /**
     * Generate a single salt from all input parameters
   
     */
    function _generateSalt(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        Fees memory _fees,
        address _tokenFeeCollector,
        address _crowdinvestingFeeCollector,
        address _privateOfferFeeCollector
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _rawSalt,
                    _trustedForwarder,
                    _owner,
                    _fees,
                    _tokenFeeCollector,
                    _crowdinvestingFeeCollector,
                    _privateOfferFeeCollector
                )
            );
    }
}
