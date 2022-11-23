// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../lib/forge-std/src/Test.sol";

library Price {
    /**
        @dev To avoid rounding errors, tokenprice needs to be multiple of 10**token.decimals(). This is checked for here. 
            With:
                _tokenAmount = a * [token_bits]
                tokenPrice = p * [currency_bits]/[token]
            The currency amount is calculated as: 
                currencyAmount = _tokenAmount * tokenPrice 
                = a * p * [currency_bits]/[token] * [token_bits]  with 1 [token] = (10**token.decimals) [token_bits]
                = a * p * [currency_bits] / (10**token.decimals)
         */
    function getCurrencyAmount(
        ERC20 _token,
        uint256 _tokenAmount,
        uint256 _price
    ) public view returns (uint256) {
        require(
            (_tokenAmount * _price) % (10 ** _token.decimals()) == 0,
            "Amount * tokenprice needs to be a multiple of 10**token.decimals()"
        );
        return (_tokenAmount * _price) / (10 ** _token.decimals());
    }

    function getPrice(
        ERC20 _token,
        uint256 _tokenAmount,
        uint256 _currencyAmount
    ) public view returns (uint256) {
        return (_currencyAmount * (10 ** _token.decimals())) / _tokenAmount;
    }
}

// contract PriceTest is Test {
//     Token token;

//     function setUp() public {

//     }

//     function testGetCurrencyAmount() public {
//         IERC20Metadata token = IERC20Metadata(address(0));
//         uint256 tokenAmount = 100;
//         uint256 price = 100;
//         uint256 expected = 10000;
//         uint256 actual = Price.getCurrencyAmount(token, tokenAmount, price);
//         assertEq(actual, expected);
//     }

// }
