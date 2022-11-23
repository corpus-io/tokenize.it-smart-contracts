// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../lib/forge-std/src/Test.sol";


library Price {
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