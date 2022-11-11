// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../lib/forge-std/src/Test.sol";
import "../../contracts/Token.sol";

/*
    fake currency to test the main contract with
*/
contract FakePaymentToken is ERC20 {
    uint8 decimalPlaces;

    constructor(uint256 _initialSupply, uint8 _decimals)
        ERC20("FakePaymentToken", "FPT")
    {
        decimalPlaces = _decimals;
        _mint(msg.sender, _initialSupply);
    }

    /// @dev price definition and deal() function rely on proper handling of decimalPlaces. Therefore we need to test if decimalPlaces other than 18 work fine, too.
    function decimals() public view override returns (uint8) {
        return decimalPlaces;
    }
}
