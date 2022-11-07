// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/CorpusToken.sol";
import "../contracts/ContinuousFundraising.sol";
import "./FakePaymentToken.sol";
import "./MaliciousPaymentToken.sol";
import "./fixtures/USDC.sol";


contract MetaTxTest is Test {
    ContinuousFundraising raise;
    AllowList list;
    CorpusToken token;
    FakePaymentToken paymentToken;

    USDC usdc; 

    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant buyer = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant minterAdmin = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant minter = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant owner = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant receiver = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant paymentTokenProvider = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public trustedForwarder;


    uint8 public constant paymentTokenDecimals = 6;
    uint256 public constant paymentTokenAmount = 1000 * 10**paymentTokenDecimals;
    
    uint256 public constant price = 7 * 10**paymentTokenDecimals; // 7 payment tokens per token
    
    uint256 public constant maxAmountOfTokenToBeSold = 20 * 10**18; // 20 token
    uint256 public constant maxAmountPerBuyer = maxAmountOfTokenToBeSold / 2; // 10 token
    uint256 public constant minAmountPerBuyer = maxAmountOfTokenToBeSold / 200; // 0.1 token



    function setUp() public {
        list = new AllowList();
        token = new CorpusToken(admin, list, 0x0, "TESTTOKEN", "TEST");

        // use opengsn forwarder https://etherscan.io/address/0xAa3E82b4c4093b4bA13Cb5714382C99ADBf750cA
        trustedForwarder = 0xAa3E82b4c4093b4bA13Cb5714382C99ADBf750cA;

        usdc = USDC(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);


        // set up currency
        vm.prank(paymentTokenProvider);
        paymentToken = new FakePaymentToken(paymentTokenAmount, paymentTokenDecimals); // 1000 tokens with 6 decimals
        // transfer currency to buyer
        vm.prank(paymentTokenProvider);
        paymentToken.transfer(buyer, paymentTokenAmount);
        assertTrue(paymentToken.balanceOf(buyer) == paymentTokenAmount);

        vm.prank(owner);
        raise = new ContinuousFundraising(trustedForwarder, payable(receiver), minAmountPerBuyer, maxAmountPerBuyer, price, maxAmountOfTokenToBeSold, paymentToken, MintableERC20(address(token)));

        // allow raise contract to mint
        bytes32 roleMinterAdmin = token.MINTERADMIN_ROLE();

        vm.prank(admin);
        token.grantRole(roleMinterAdmin, minterAdmin);
        vm.prank(minterAdmin);
        token.setUpMinter(address(raise), maxAmountOfTokenToBeSold);

        // give raise contract allowance
        vm.prank(buyer);
        paymentToken.approve(address(raise), paymentTokenAmount);

        
    }

    function testUSDCBalance() public {
        uint balance1 = usdc.balanceOf(buyer);
        console.log("buyer's balance: ", balance1);
        uint balance2 = usdc.balanceOf(address(0x55FE002aefF02F77364de339a1292923A15844B8));
        console.log("circle's balance: ", balance2);
    }

}