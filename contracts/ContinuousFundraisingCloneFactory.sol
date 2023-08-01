// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./ContinuousFundraising.sol";
import "./CloneFactory.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract ContinuousFundraisingCloneFactory is CloneFactory {
    constructor(address _implementation) CloneFactory(_implementation) {}

    function createContinuousFundraisingClone(
        bytes32 salt,
        address _owner,
        address _currencyReceiver,
        uint256 _minAmountPerBuyer,
        uint256 _maxAmountPerBuyer,
        uint256 _tokenPrice,
        uint256 _maxAmountOfTokenToBeSold,
        IERC20 _currency,
        Token _token
    ) external returns (address) {
        require(_owner != address(0), "owner can not be zero address");
        address clone = Clones.cloneDeterministic(implementation, salt);
        ContinuousFundraising(clone).initialize(
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
}
