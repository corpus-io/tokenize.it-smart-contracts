// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./ContinuousFundraising.sol";
import "./CloneFactory.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract ContinuousFundraisingCloneFactory is CloneFactory {
    constructor(address _implementation) CloneFactory(_implementation) {}

    function createContinuousFundraisingClone(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        address _currencyReceiver,
        uint256 _minAmountPerBuyer,
        uint256 _maxAmountPerBuyer,
        uint256 _tokenPrice,
        uint256 _maxAmountOfTokenToBeSold,
        IERC20 _currency,
        Token _token
    ) external returns (address) {
        bytes32 salt = keccak256(
            abi.encodePacked(
                _rawSalt,
                _trustedForwarder,
                _owner,
                _currencyReceiver,
                _minAmountPerBuyer,
                _maxAmountPerBuyer,
                _tokenPrice,
                _maxAmountOfTokenToBeSold,
                _currency,
                _token
            )
        );
        address clone = Clones.cloneDeterministic(implementation, salt);
        ContinuousFundraising continuousFundraising = ContinuousFundraising(clone);
        require(
            continuousFundraising.isTrustedForwarder(_trustedForwarder),
            "TokenCloneFactory: Unexpected trustedForwarder"
        );
        continuousFundraising.initialize(
            _owner,
            _currencyReceiver,
            _minAmountPerBuyer,
            _maxAmountPerBuyer,
            _tokenPrice,
            _maxAmountOfTokenToBeSold,
            _currency,
            _token
        );
        emit NewClone(clone);
        return clone;
    }

    function predictCloneAddress(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        address _currencyReceiver,
        uint256 _minAmountPerBuyer,
        uint256 _maxAmountPerBuyer,
        uint256 _tokenPrice,
        uint256 _maxAmountOfTokenToBeSold,
        IERC20 _currency,
        Token _token
    ) external view returns (address) {
        bytes32 salt = keccak256(
            abi.encodePacked(
                _rawSalt,
                _trustedForwarder,
                _owner,
                _currencyReceiver,
                _minAmountPerBuyer,
                _maxAmountPerBuyer,
                _tokenPrice,
                _maxAmountOfTokenToBeSold,
                _currency,
                _token
            )
        );
        return Clones.predictDeterministicAddress(implementation, salt);
    }
}
