// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "./resources/FakePaymentToken.sol";
import "@openzeppelin/contracts/finance/PaymentSplitter.sol";

contract paymentSplitterTest is Test {
    FakePaymentToken token;

    function setUp() public {
        token = new FakePaymentToken(1000e18, 18);
    }

    function testFixedSplit() public {
        address[] memory payees = new address[](2);
        payees[0] = address(0x1);
        payees[1] = address(0x2);
        uint256[] memory shares = new uint256[](2);
        shares[0] = 8; // 80%
        shares[1] = 2; // 20%
        PaymentSplitter splitter = new PaymentSplitter(payees, shares);

        // send 100 tokens to the splitter
        token.transfer(address(splitter), 100e18);

        // pull share for address 1
        assertEq(token.balanceOf(payees[0]), 0);
        splitter.release(token, payees[0]);
        assertEq(token.balanceOf(payees[0]), 80e18);

        // pull share for address 2
        assertEq(token.balanceOf(payees[1]), 0);
        splitter.release(token, payees[1]);
        assertEq(token.balanceOf(payees[1]), 20e18);
    }
}
