// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "./PriceLinear.sol";
import "./CloneFactory.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract PriceLinearCloneFactory is CloneFactory {
    constructor(address _implementation) CloneFactory(_implementation) {}

    function createPriceLinear(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        uint64 _slopeEnumerator,
        uint64 _slopeDenominator,
        uint64 _startTimeOrBlockNumber,
        uint32 _stepDuration,
        bool _isBlockBased,
        bool _isRising
    ) external returns (address) {
        bytes32 salt = _generateSalt(
            _rawSalt,
            _trustedForwarder,
            _owner,
            _slopeEnumerator,
            _slopeDenominator,
            _startTimeOrBlockNumber,
            _stepDuration,
            _isBlockBased,
            _isRising
        );
        address clone = Clones.cloneDeterministic(implementation, salt);
        PriceLinear clonePriceOracle = PriceLinear(clone);
        require(
            clonePriceOracle.isTrustedForwarder(_trustedForwarder),
            "PriceLinearCloneFactory: Unexpected trustedForwarder"
        );
        clonePriceOracle.initialize(
            _owner,
            _slopeEnumerator,
            _slopeDenominator,
            _startTimeOrBlockNumber,
            _stepDuration,
            _isBlockBased,
            _isRising
        );
        emit NewClone(clone);
        return clone;
    }

    function predictCloneAddress(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        uint64 _slopeEnumerator,
        uint64 _slopeDenominator,
        uint64 _startTimeOrBlockNumber,
        uint32 _stepDuration,
        bool _isBlockBased,
        bool _isRising
    ) external view returns (address) {
        bytes32 salt = _generateSalt(
            _rawSalt,
            _trustedForwarder,
            _owner,
            _slopeEnumerator,
            _slopeDenominator,
            _startTimeOrBlockNumber,
            _stepDuration,
            _isBlockBased,
            _isRising
        );
        return Clones.predictDeterministicAddress(implementation, salt);
    }

    function _generateSalt(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        uint64 _slopeEnumerator,
        uint64 _slopeDenominator,
        uint64 _startTimeOrBlockNumber,
        uint32 _stepDuration,
        bool _isBlockBased,
        bool _isRising
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    _rawSalt,
                    _trustedForwarder,
                    _owner,
                    _slopeEnumerator,
                    _slopeDenominator,
                    _startTimeOrBlockNumber,
                    _stepDuration,
                    _isBlockBased,
                    _isRising
                )
            );
    }
}
