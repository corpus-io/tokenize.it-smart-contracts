// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "./PublicFundraising.sol";
import "./CloneFactory.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract PublicFundraisingCloneFactory is CloneFactory {
    constructor(address _implementation) CloneFactory(_implementation) {}

    function createPublicFundraisingClone(
        bytes32 _rawSalt,
        address _trustedForwarder,
        PublicFundraisingInitializerArguments memory _arguments
    ) external returns (address) {
        bytes32 salt = _generateSalt(_rawSalt, _trustedForwarder, _arguments);
        PublicFundraising publicFundraising = PublicFundraising(Clones.cloneDeterministic(implementation, salt));
        require(
            publicFundraising.isTrustedForwarder(_trustedForwarder),
            "PublicFundraisingCloneFactory: Unexpected trustedForwarder"
        );
        publicFundraising.initialize(_arguments);
        emit NewClone(address(publicFundraising));
        return address(publicFundraising);
    }

    function predictCloneAddress(
        bytes32 _rawSalt,
        address _trustedForwarder,
        PublicFundraisingInitializerArguments memory _arguments
    ) external view returns (address) {
        bytes32 salt = _generateSalt(_rawSalt, _trustedForwarder, _arguments);
        return Clones.predictDeterministicAddress(implementation, salt);
    }

    function _generateSalt(
        bytes32 _rawSalt,
        address _trustedForwarder,
        PublicFundraisingInitializerArguments memory _arguments
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(_rawSalt, _trustedForwarder, _arguments));
    }
}
