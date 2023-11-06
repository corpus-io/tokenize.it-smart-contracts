// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Token.sol";
import "./CloneFactory.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TokenProxyFactory is CloneFactory {
    constructor(address _implementation) CloneFactory(_implementation) {}

    function createTokenProxy(
        bytes32 _rawSalt,
        address _trustedForwarder,
        IFeeSettingsV2 _feeSettings,
        address _admin,
        AllowList _allowList,
        uint256 _requirements,
        string memory _name,
        string memory _symbol
    ) external returns (address) {
        bytes32 salt = keccak256(
            abi.encodePacked(
                _rawSalt,
                _trustedForwarder,
                _feeSettings,
                _admin,
                _allowList,
                _requirements,
                _name,
                _symbol
            )
        );
        bytes memory noArguments;
        ERC1967Proxy proxy = new ERC1967Proxy(implementation, noArguments);
        // Create2.deploy(
        //     0,
        //     salt,
        //     abi.encodePacked(
        //         type(ERC1967Proxy).creationCode
        //         //abi.encode(implementation, abi.encode(_feeSettings, _admin, _allowList, _requirements, _name, _symbol))
        //     )
        // );
        //Clones.cloneDeterministic(implementation, salt);
        Token cloneToken = Token(address(proxy));
        require(cloneToken.isTrustedForwarder(_trustedForwarder), "TokenCloneFactory: Unexpected trustedForwarder");
        cloneToken.initialize(_feeSettings, _admin, _allowList, _requirements, _name, _symbol);
        emit NewClone(address(proxy));
        return address(proxy);
    }

    function predictCloneAddress(
        bytes32 _rawSalt,
        address _trustedForwarder,
        IFeeSettingsV1 _feeSettings,
        address _admin,
        AllowList _allowList,
        uint256 _requirements,
        string memory _name,
        string memory _symbol
    ) external view returns (address) {
        bytes32 salt = keccak256(
            abi.encodePacked(
                _rawSalt,
                _trustedForwarder,
                _feeSettings,
                _admin,
                _allowList,
                _requirements,
                _name,
                _symbol
            )
        );
        return Clones.predictDeterministicAddress(implementation, salt);
    }
}
