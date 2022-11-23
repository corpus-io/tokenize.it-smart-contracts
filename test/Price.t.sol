// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../lib/forge-std/src/Test.sol";
import "../contracts/Price.sol";
import "./resources/FakePaymentToken.sol";

contract PriceTest is Test {
    //Token token;

    // function setUp() public {
    //     token = new FakePaymentToken(700*10**18, 18);
    // }

    function testGetCurrencyAmountNotDivisible() public {
        ERC20 token = new FakePaymentToken(700 * 10 ** 18, 18);
        uint256 tokenAmount = 100;
        uint256 price = 100;
        vm.expectRevert(
            "Amount * tokenprice needs to be a multiple of 10**token.decimals()"
        );
        Price.getCurrencyAmount(token, tokenAmount, price);
    }

    function testGetCurrencyAmountMatches(uint8 paymentTokenDecimals) public {
        vm.assume(paymentTokenDecimals > 0);
        vm.assume(paymentTokenDecimals < 30);
        ERC20 token = new FakePaymentToken(35600000000000, 18);

        // uint256 paymentTokenDecimals = 10;

        uint256 tokenAmount = 5 * 10 ** token.decimals();
        uint256 price = 7 * 10 ** paymentTokenDecimals;
        uint256 expectedCurrencyAmount = (tokenAmount * price) / 10 ** 18;

        uint256 actualCurrencyAmount = Price.getCurrencyAmount(
            token,
            tokenAmount,
            price
        );
        assertEq(
            actualCurrencyAmount,
            expectedCurrencyAmount,
            "Currency amount should match, but actualCurrencyAmount is not equal to expectedCurrencyAmount"
        );
    }

    function testGetPriceFuzz(
        uint8 paymentTokenDecimals,
        uint256 currencyAmount
    ) public {
        vm.assume(paymentTokenDecimals < 30);
        vm.assume(currencyAmount < UINT256_MAX / 10 ** 18);
        ERC20 token = new FakePaymentToken(35600000000000, 18);

        uint256 tokenAmount = 3 * 10 ** token.decimals();
        uint256 expectedPrice = (currencyAmount * 10 ** token.decimals()) /
            tokenAmount;

        uint256 actualPrice = Price.getPrice(
            token,
            tokenAmount,
            currencyAmount
        );
        assertEq(
            actualPrice,
            expectedPrice,
            "Price should match, but actualPrice is not equal to expectedPrice"
        );
    }

    /**
     * @notice This example is taken from the [documentation](../docs/Price.md)
     */
    function testGetPriceManualExample() public {
        ERC20 token = new FakePaymentToken(1, 18);

        uint256 paymentTokenDecimals = 6;

        uint256 tokenAmount = 3 * 10 ** token.decimals();
        uint256 currencyAmount = 600 * 10 ** paymentTokenDecimals;
        //uint256 expectedPrice = (currencyAmount * 10 ** 18) / tokenAmount;
        uint256 expectedPrice = 2 * 10 ** 8;

        uint256 actualPrice = Price.getPrice(
            token,
            tokenAmount,
            currencyAmount
        );
        assertEq(
            actualPrice,
            expectedPrice,
            "Price should match, but actualPrice is not equal to expectedPrice"
        );
    }
}
