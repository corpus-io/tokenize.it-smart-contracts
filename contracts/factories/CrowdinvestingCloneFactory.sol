// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "../Crowdinvesting.sol";
import "./CloneFactory.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract CrowdinvestingCloneFactory is CloneFactory {
    constructor(address _implementation) CloneFactory(_implementation) {}

    function createCrowdinvestingClone(
        bytes32 _rawSalt,
        address _trustedForwarder,
        CrowdinvestingInitializerArguments memory _arguments
    ) external returns (address) {
        bytes32 salt = _generateSalt(_rawSalt, _trustedForwarder, _arguments);
        Crowdinvesting crowdinvesting = Crowdinvesting(Clones.cloneDeterministic(implementation, salt));
        require(
            crowdinvesting.isTrustedForwarder(_trustedForwarder),
            "CrowdinvestingCloneFactory: Unexpected trustedForwarder"
        );
        crowdinvesting.initialize(_arguments);
        emit NewClone(address(crowdinvesting));
        return address(crowdinvesting);
    }

    function predictCloneAddress(
        bytes32 _rawSalt,
        address _trustedForwarder,
        CrowdinvestingInitializerArguments memory _arguments
    ) external view returns (address) {
        bytes32 salt = _generateSalt(_rawSalt, _trustedForwarder, _arguments);
        return Clones.predictDeterministicAddress(implementation, salt);
    }

    function _generateSalt(
        bytes32 _rawSalt,
        address _trustedForwarder,
        CrowdinvestingInitializerArguments memory _arguments
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(_rawSalt, _trustedForwarder, _arguments));
    }
}
