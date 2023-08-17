// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./Token.sol";
import "./CloneFactory.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract TokenCloneFactory is CloneFactory {
    constructor(address _implementation) CloneFactory(_implementation) {}

    function createTokenClone(
        bytes32 salt,
        IFeeSettingsV1 _feeSettings,
        address _admin,
        AllowList _allowList,
        uint256 _requirements,
        string memory _name,
        string memory _symbol
    ) external returns (address) {
        address clone = Clones.cloneDeterministic(implementation, salt);
        Token(clone).initialize(_feeSettings, _admin, _allowList, _requirements, _name, _symbol);
        emit NewClone(clone);
        return clone;
    }
}
