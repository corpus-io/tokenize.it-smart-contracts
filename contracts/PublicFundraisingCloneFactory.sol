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
        address _owner,
        address _currencyReceiver,
        uint256 _minAmountPerBuyer,
        uint256 _maxAmountPerBuyer,
        uint256 _tokenPrice,
        uint256 _maxAmountOfTokenToBeSold,
        IERC20 _currency,
        Token _token,
        uint256 _lastBuyDate
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
                _token,
                _lastBuyDate
            )
        );
        address clone = Clones.cloneDeterministic(implementation, salt);
        PublicFundraising publicFundraising = PublicFundraising(clone);
        require(
            publicFundraising.isTrustedForwarder(_trustedForwarder),
            "PublicFundraisingCloneFactory: Unexpected trustedForwarder"
        );
        publicFundraising.initialize(
            _owner,
            _currencyReceiver,
            _minAmountPerBuyer,
            _maxAmountPerBuyer,
            _tokenPrice,
            _maxAmountOfTokenToBeSold,
            _currency,
            _token,
            _lastBuyDate
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
        Token _token,
        uint256 _lastBuyDate
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
                _token,
                _lastBuyDate
            )
        );
        return Clones.predictDeterministicAddress(implementation, salt);
    }
}
