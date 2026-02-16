// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "./Token.sol";



contract/Coinvestor is Ownable2StepUpgradeable {
    address[] public beneficiaries; // [0] is the conivestor, the others are the crry receivers
    uint64[] public percentage; // divided by uint64max
    uint public baseprice; // currency: EUR

    constructor(address[] _beneficiaries, uint[] _percentage, uint _baseprice, address _owner) Ownable2StepUpgradeable(_owner) {
        beneficiaries = _beneficiaries; // does that work as intended?
        percentage = _percentage;
        baseprice = _baseprice;
    }

    function withdraw(Token _token, TokenSwapCarry _tokenSwapCarry, uint amount) onlyOwner {

        // ensure that _tokenSwapCarry is actually a TokenSwapCarry contract

        bytes32 accountHash = 0x...; // this is the wrong value, we need the value for the TokenSwapCarry contract
        bytes32 codeHash;    
        assembly { codeHash := extcodehash(address(_token)) }
        require(codeHash == accountHash && codeHash != 0x0);

        _token.approve(_tokenSwapCarry, amount);
    }

    function withdrawToTokenAdmin(Token _token, address _admin) onlyOwner { // only used in case of an exit, or executing the put-option
        require(_token.hasRole(DEFAULT_ADMIN_ROLE, _admin));
        _token.transfer(_admin, _token.balanceOf(address(this))); 
    }
}
