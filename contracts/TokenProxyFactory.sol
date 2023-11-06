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
        bytes32 salt = getSalt(
            _rawSalt,
            _trustedForwarder,
            _feeSettings,
            _admin,
            _allowList,
            _requirements,
            _name,
            _symbol
        );
        //bytes memory noArguments;
        // ERC1967Proxy proxy = new ERC1967Proxy(implementation, noArguments);
        address proxyAddress = Create2.deploy(0, salt, getBytecode());
        ERC1967Proxy proxy = ERC1967Proxy(payable(proxyAddress));
        //Clones.cloneDeterministic(implementation, salt);
        Token cloneToken = Token(address(proxy));
        require(cloneToken.isTrustedForwarder(_trustedForwarder), "TokenCloneFactory: Unexpected trustedForwarder");
        cloneToken.initialize(_feeSettings, _admin, _allowList, _requirements, _name, _symbol);
        emit NewClone(address(proxy));
        return address(proxy);
    }

    function predictProxyAddress(
        bytes32 _rawSalt,
        address _trustedForwarder,
        IFeeSettingsV2 _feeSettings,
        address _admin,
        AllowList _allowList,
        uint256 _requirements,
        string memory _name,
        string memory _symbol
    ) external view returns (address) {
        bytes32 salt = getSalt(
            _rawSalt,
            _trustedForwarder,
            _feeSettings,
            _admin,
            _allowList,
            _requirements,
            _name,
            _symbol
        );
        return Create2.computeAddress(salt, keccak256(getBytecode()));
    }

    /**
     * @dev Generates the bytecode of the contract to be deployed, using the parameters.
     * @return bytecode of the contract to be deployed.
     */
    function getBytecode() private view returns (bytes memory) {
        return
            abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(implementation, new bytes(0))
                //abi.encode(_feeSettings, _admin, _allowList, _requirements, _name, _symbol))
            );
    }

    function getSalt(
        bytes32 _rawSalt,
        address _trustedForwarder,
        IFeeSettingsV2 _feeSettings,
        address _admin,
        AllowList _allowList,
        uint256 _requirements,
        string memory _name,
        string memory _symbol
    ) public pure returns (bytes32) {
        return
            keccak256(
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
    }
}
