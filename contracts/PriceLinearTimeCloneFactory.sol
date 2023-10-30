// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./PriceLinearTime.sol";
import "./CloneFactory.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract TokenCloneFactory is CloneFactory {
    constructor(address _implementation) CloneFactory(_implementation) {}

    function createPriceLinearTime(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        uint64 _slopeEnumerator,
        uint64 _slopeDenominator,
        uint64 _startTime
    ) external returns (address) {
        bytes32 salt = keccak256(
            abi.encodePacked(_rawSalt, _trustedForwarder, _owner, _slopeEnumerator, _slopeDenominator, _startTime)
        );
        address clone = Clones.cloneDeterministic(implementation, salt);
        PriceLinearTime clonePriceOracle = PriceLinearTime(clone);
        require(
            clonePriceOracle.isTrustedForwarder(_trustedForwarder),
            "PriceLinearTimeCloneFactory: Unexpected trustedForwarder"
        );
        clonePriceOracle.initialize(_owner, _slopeEnumerator, _slopeDenominator, _startTime);
        emit NewClone(clone);
        return clone;
    }

    function predictCloneAddress(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        uint64 _slopeEnumerator,
        uint64 _slopeDenominator,
        uint64 _startTime
    ) external view returns (address) {
        bytes32 salt = keccak256(
            abi.encodePacked(_rawSalt, _trustedForwarder, _owner, _slopeEnumerator, _slopeDenominator, _startTime)
        );
        return Clones.predictDeterministicAddress(implementation, salt);
    }
}
