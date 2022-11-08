// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/CorpusToken.sol";
import "../contracts/ContinuousFundraising.sol";
import "./FakePaymentToken.sol";
import "./MaliciousPaymentToken.sol";
import "@opengsn/contracts/src/forwarder/Forwarder.sol";


contract ContinuousFundraisingTest is Test {
    ContinuousFundraising raise;
    AllowList list;
    CorpusToken token;
    FakePaymentToken paymentToken;
    Forwarder trustedForwarder;


    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant buyer = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant minterAdmin = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant minter = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant owner = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant receiver = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant paymentTokenProvider = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant sender = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;



    uint8 public constant paymentTokenDecimals = 6;
    uint256 public constant paymentTokenAmount = 1000 * 10**paymentTokenDecimals;
    
    uint256 public constant price = 7 * 10**paymentTokenDecimals; // 7 payment tokens per token
    
    uint256 public constant maxAmountOfTokenToBeSold = 20 * 10**18; // 20 token
    uint256 public constant maxAmountPerBuyer = maxAmountOfTokenToBeSold / 2; // 10 token
    uint256 public constant minAmountPerBuyer = maxAmountOfTokenToBeSold / 200; // 0.1 token



    function setUp() public {
        list = new AllowList();
        token = new CorpusToken(admin, list, 0x0, "TESTTOKEN", "TEST");
        trustedForwarder = new Forwarder();

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

    function testBuyWithERC2771() public {
        uint256 tokenBuyAmount = 5 * 10**token.decimals();
        uint256 costInPaymentToken = tokenBuyAmount * price / 10**18;

        assert(costInPaymentToken == 35 * 10**paymentTokenDecimals); // 35 payment tokens, manually calculated

        uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(buyer);

        vm.prank(sender);

        // register domain separator
        string memory name = "ContinuousFundraising";
        uint version = 1; 
    
        trustedForwarder.registerDomainSeparator(name, version);

        uint256 chainId;
        /* solhint-disable-next-line no-inline-assembly */
        assembly { chainId := chainid() }

        bytes memory domainValue = abi.encode(
            keccak256(bytes(EIP712_DOMAIN_TYPE)),
            keccak256(bytes(name)),
            keccak256(bytes(version)),
            chainId,
            address(trustedForwarder));

        bytes32 domainHash = keccak256(domainValue); // we need this domain hash for our call to execute later


        // // https://github.com/foundry-rs/foundry/issues/3330
        // // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/ECDSA.sol
        // bytes32 digest = ECDSA.toTypedDataHash(domainSeparator, keccak256(payload));
        // (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, digest);

        // // register 

        // // encode buy call and sign it https://book.getfoundry.sh/cheatcodes/sign
        // bytes memory buyCallData = abi.encodeWithSignature("buy(uint256)", tokenBuyAmount);

        // address _buyer = vm.addr(1);
        // bytes32 hash = keccak256(buyCallData);
        // (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        // address signer = ecrecover(hash, v, r, s);
        // assertEq(alice, signer); // [PASS]

        // // send call through forwarder contract
        // raise.buy(tokenBuyAmount); // this test fails if 5 * 10**18 is replaced with 5 * 10**token.decimals() for this argument, even though they should be equal


        // assertTrue(paymentToken.balanceOf(buyer) == paymentTokenBalanceBefore - costInPaymentToken);
        // assertTrue(token.balanceOf(buyer) == tokenBuyAmount);
        // assertTrue(paymentToken.balanceOf(receiver) == costInPaymentToken);
        // assertTrue(raise.tokensSold() == tokenBuyAmount);
        // assertTrue(raise.tokensBought(buyer) == tokenBuyAmount);
    }

    // function testBuyTooMuch() public {
    //     uint256 tokenBuyAmount = 5 * 10**token.decimals();
    //     uint256 costInPaymentToken = tokenBuyAmount * price / 10**18;

    //     assert(costInPaymentToken == 35 * 10**paymentTokenDecimals); // 35 payment tokens, manually calculated

    //     uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(buyer);

    //     vm.prank(buyer);
    //     vm.expectRevert('Total amount of bought tokens needs to be lower than or equal to maxAmount');
    //     raise.buy(maxAmountPerBuyer + 10**18); //+ 10**token.decimals());
    //     assertTrue(paymentToken.balanceOf(buyer) == paymentTokenBalanceBefore);
    //     assertTrue(token.balanceOf(buyer) == 0);
    //     assertTrue(paymentToken.balanceOf(receiver) == 0);
    //     assertTrue(raise.tokensSold() == 0);
    //     assertTrue(raise.tokensBought(buyer) == 0);
    // }

    // function testMultiplePeopleBuyTooMuch() public {
    //     address person1 = vm.addr(1);
    //     address person2 = vm.addr(2); 

    //     uint availableBalance = paymentToken.balanceOf(buyer);  

    //     vm.prank(buyer);
    //     paymentToken.transfer(person1, availableBalance / 2);
    //     vm.prank(buyer);
    //     paymentToken.transfer(person2, 10**6);

    //     vm.prank(person1);
    //     paymentToken.approve(address(raise), paymentTokenAmount);

    //     vm.prank(person2);
    //     paymentToken.approve(address(raise), paymentTokenAmount);

    //     vm.prank(buyer);
    //     raise.buy(maxAmountOfTokenToBeSold / 2);
    //     vm.prank(person1);
    //     raise.buy(maxAmountOfTokenToBeSold / 2);
    //     vm.prank(person2);
    //     vm.expectRevert('Not enough tokens to sell left');
    //     raise.buy(10**18);
        
    // }

    // function testExceedMintingAllowance() public {
    //     // reduce minting allowance of fundraising contract, so the revert happens in CorpusToken
    //     vm.prank(minterAdmin);
    //     token.setUpMinter(address(raise), 0);
    //     vm.prank(minterAdmin);
    //     token.setUpMinter(address(raise), maxAmountPerBuyer/2);
        
    //     vm.prank(buyer);
    //     vm.expectRevert('MintingAllowance too low');
    //     raise.buy(maxAmountPerBuyer); //+ 10**token.decimals());
    //     assertTrue(token.balanceOf(buyer) == 0);
    //     assertTrue(paymentToken.balanceOf(receiver) == 0);
    //     assertTrue(raise.tokensSold() == 0);
    //     assertTrue(raise.tokensBought(buyer) == 0);
    // }
    
    // function testBuyTooLittle() public {
    //     uint256 tokenBuyAmount = 5 * 10**token.decimals();
    //     uint256 costInPaymentToken = tokenBuyAmount * price / 10**18;

    //     assert(costInPaymentToken == 35 * 10**paymentTokenDecimals); // 35 payment tokens, manually calculated

    //     uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(buyer);

    //     vm.prank(buyer);
    //     vm.expectRevert("Buyer needs to buy at least minAmount");
    //     raise.buy(minAmountPerBuyer / 2);
    //     assertTrue(paymentToken.balanceOf(buyer) == paymentTokenBalanceBefore);
    //     assertTrue(token.balanceOf(buyer) == 0);
    //     assertTrue(paymentToken.balanceOf(receiver) == 0);
    //     assertTrue(raise.tokensSold() == 0);
    //     assertTrue(raise.tokensBought(buyer) == 0);
    // }

    // function testBuySmallAmountAfterInitialInvestment() public {
    //     uint256 tokenBuyAmount = minAmountPerBuyer;
    //     uint256 costInPaymentTokenForMinAmount = tokenBuyAmount * price / 10**18;
    //     uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(buyer);

    //     vm.prank(buyer);
    //     raise.buy(minAmountPerBuyer);

    //     // buy less than minAmount -> should be okay because minAmount has already been bought.
    //     vm.prank(buyer);
    //     raise.buy(minAmountPerBuyer / 2);

    //     assertTrue(paymentToken.balanceOf(buyer) == paymentTokenBalanceBefore - costInPaymentTokenForMinAmount * 3 / 2);
    //     assertTrue(token.balanceOf(buyer) == minAmountPerBuyer * 3 / 2);
    //     assertTrue(paymentToken.balanceOf(receiver) == costInPaymentTokenForMinAmount * 3 / 2);
    //     assertTrue(raise.tokensSold() == minAmountPerBuyer * 3 / 2);
    //     assertTrue(raise.tokensBought(buyer) == raise.tokensSold());
    // }

    // function testAmountWithRest() public {
    //     uint256 tokenBuyAmount = 5 * 10**token.decimals();
    //     uint256 costInPaymentToken = tokenBuyAmount * price / 10**18;

    //     assert(costInPaymentToken == 35 * 10**paymentTokenDecimals); // 35 payment tokens, manually calculated

    //     uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(buyer);

    //     vm.prank(buyer);
    //     vm.expectRevert('Amount * tokenprice needs to be a multiple of 10**token.decimals()');
    //     raise.buy(maxAmountPerBuyer + 1);
    //     assertTrue(paymentToken.balanceOf(buyer) == paymentTokenBalanceBefore);
    //     assertTrue(token.balanceOf(buyer) == 0);
    //     assertTrue(paymentToken.balanceOf(receiver) == 0);
    //     assertTrue(raise.tokensSold() == 0);
    //     assertTrue(raise.tokensBought(buyer) == 0);
    // }

    // /*
    //     try to buy more than allowed
    // */
    // function testFailOverflow() public {
    //     vm.prank(buyer);
    //     raise.buy(maxAmountPerBuyer + 1);
    // }

    // /*
    //     try to buy less than allowed
    // */      
    // function testFailUnderflow() public {
    //     vm.prank(buyer);
    //     raise.buy(minAmountPerBuyer - 1);
    // }

    // /*
    //     try to buy while paused
    // */
    // function testFailPaused() public {
    //     vm.prank(owner);
    //     raise.pause();
    //     vm.prank(buyer);
    //     raise.buy(minAmountPerBuyer);
    // }

    // /*
    //     try to update currencyReceiver not paused
    // */
    // function testFailUpdateCurrencyReceiverNotPaused() public {
    //     vm.prank(owner);
    //     raise.setCurrencyReceiver(payable(address(buyer)));
    // }

    // /*
    //     try to update currencyReceiver while paused
    // */
    // function testUpdateCurrencyReceiverPaused() public {
    //     assertTrue(raise.currencyReceiver() == receiver);
    //     vm.prank(owner);
    //     raise.pause();
    //     vm.prank(owner);
    //     raise.setCurrencyReceiver(payable(address(buyer)));
    //     assertTrue(raise.currencyReceiver() == address(buyer));
    // }

    // /* 
    //     try to update minAmountPerBuyer not paused
    // */
    // function testFailUpdateMinAmountPerBuyerNotPaused() public {
    //     vm.prank(owner);
    //     raise.setMinAmountPerBuyer(100);
    // }

    // /* 
    //     try to update minAmountPerBuyer while paused
    // */
    // function testUpdateMinAmountPerBuyerPaused() public {
    //     assertTrue(raise.minAmountPerBuyer() == minAmountPerBuyer);
    //     vm.prank(owner);
    //     raise.pause();
    //     vm.prank(owner);
    //     raise.setMinAmountPerBuyer(300);
    //     assertTrue(raise.minAmountPerBuyer() == 300);
    // }

    // /* 
    //     try to update maxAmountPerBuyer not paused
    // */
    // function testFailUpdateMaxAmountPerBuyerNotPaused() public {
    //     vm.prank(owner);
    //     raise.setMaxAmountPerBuyer(100);
    // }

    // /* 
    //     try to update maxAmountPerBuyer while paused
    // */
    // function testUpdateMaxAmountPerBuyerPaused() public {
    //     assertTrue(raise.maxAmountPerBuyer() == maxAmountPerBuyer);
    //     vm.prank(owner);
    //     raise.pause();
    //     vm.prank(owner);
    //     raise.setMaxAmountPerBuyer(minAmountPerBuyer);
    //     assertTrue(raise.maxAmountPerBuyer() == minAmountPerBuyer);
    // }

    // /*
    //     try to update currency and price while not paused
    // */
    // function testFailUpdateCurrencyAndPriceNotPaused() public {
    //     FakePaymentToken newPaymentToken = new FakePaymentToken(700, 3);
    //     vm.prank(owner);
    //     raise.setCurrencyAndTokenPrice(newPaymentToken, 100);
    // }

    // /*
    //     try to update currency and price while paused
    // */
    // function testUpdateCurrencyAndPricePaused() public {
    //     assertTrue(raise.tokenPrice() == price);
    //     assertTrue(raise.currency() == paymentToken);

    //     FakePaymentToken newPaymentToken = new FakePaymentToken(700, 3);

    //     vm.prank(owner);
    //     raise.pause();
    //     vm.prank(owner);
    //     raise.setCurrencyAndTokenPrice(newPaymentToken, 700);
    //     assertTrue(raise.tokenPrice() == 700);
    //     assertTrue(raise.currency() == newPaymentToken);
    // }

    // /*
    //     try to update maxAmountOfTokenToBeSold while not paused
    // */
    // function testFailUpdateMaxAmountOfTokenToBeSoldNotPaused() public {
    //     vm.prank(owner);
    //     raise.setMaxAmountOfTokenToBeSold(123 * 10**18);
    // }

    // /*
    //     try to update maxAmountOfTokenToBeSold while paused
    // */
    // function testUpdateMaxAmountOfTokenToBeSoldPaused() public {
    //     assertTrue(raise.maxAmountOfTokenToBeSold() == maxAmountOfTokenToBeSold);
    //     vm.prank(owner);
    //     raise.pause();
    //     vm.prank(owner);
    //     raise.setMaxAmountOfTokenToBeSold(minAmountPerBuyer);
    //     assertTrue(raise.maxAmountOfTokenToBeSold() == minAmountPerBuyer);
    // }

    // /*
    //     try to unpause immediately after pausing
    // */
    // function testFailUnpauseImmediatelyAfterPausing() public {
    //     vm.prank(owner);
    //     raise.pause();
    //     assertTrue(raise.paused());
    //     assertTrue(raise.lastPause() > 0);
    //     vm.prank(owner);
    //     raise.unpause();
    // }

    // /*
    //     try to unpause after delay has passed
    // */
    // function testFailUnpauseAfterDelay() public {
    //     uint256 time = block.timestamp;
    //     vm.warp(time);
    //     vm.prank(owner);
    //     raise.pause();
    //     assertTrue(raise.paused());
    //     assertTrue(raise.lastPause() == time);
    //     vm.warp(time + raise.delay());
    //     vm.prank(owner);
    //     raise.unpause();
    // }

    // /*
    //     try to unpause after more than 1 day has passed
    // */
    // function testUnpauseAfterDelayAnd1Sec() public {
    //     uint256 time = block.timestamp;
    //     vm.warp(time);
    //     vm.prank(owner);
    //     raise.pause();
    //     assertTrue(raise.paused());
    //     assertTrue(raise.lastPause() == time);
    //     vm.warp(time + raise.delay() + 1 seconds);
    //     vm.prank(owner);
    //     raise.unpause();
    // }

    // /*
    //     try to unpause too soon after setMaxAmountOfTokenToBeSold
    // */
    // function testFailUnpauseTooSoonAfterSetMaxAmountOfTokenToBeSold() public {
    //     uint256 time = block.timestamp;
    //     vm.warp(time);
    //     vm.prank(owner);
    //     raise.pause();
    //     assertTrue(raise.paused());
    //     assertTrue(raise.lastPause() == time);
    //     vm.warp(time + 2 hours);
    //     vm.prank(owner);
    //     raise.setMaxAmountOfTokenToBeSold(700); 
    //     assertTrue(raise.lastPause() == time + 2 hours);       
    //     vm.warp(time + raise.delay() + 1 seconds);
    //     vm.prank(owner);
    //     raise.unpause(); // must fail because of the parameter update
    // }

    // /*
    //     try to unpause after setMaxAmountOfTokenToBeSold
    // */
    // function testUnpauseAfterSetMaxAmountOfTokenToBeSold() public {
    //     uint256 time = block.timestamp;
    //     vm.warp(time);
    //     vm.prank(owner);
    //     raise.pause();
    //     assertTrue(raise.paused());
    //     assertTrue(raise.lastPause() == time);
    //     vm.warp(time + 2 hours);
    //     vm.prank(owner);
    //     raise.setMaxAmountOfTokenToBeSold(700); 
    //     assertTrue(raise.lastPause() == time + 2 hours);       
    //     vm.warp(time + raise.delay() + 2 hours + 1 seconds);
    //     vm.prank(owner);
    //     raise.unpause();
    // }

    // /*
    //     try to unpause too soon after setCurrencyReceiver
    // */  
    // function testFailUnpauseTooSoonAfterSetCurrencyReceiver() public {
    //     uint256 time = block.timestamp;
    //     vm.warp(time);
    //     vm.prank(owner);
    //     raise.pause();
    //     assertTrue(raise.paused());
    //     assertTrue(raise.lastPause() == time);
    //     vm.warp(time + 2 hours);
    //     vm.prank(owner);
    //     raise.setCurrencyReceiver(payable(address(buyer))); 
    //     assertTrue(raise.lastPause() == time + 2 hours);       
    //     vm.warp(time + raise.delay() + 1 hours);
    //     vm.prank(owner);
    //     raise.unpause(); // must fail because of the parameter update
    // }

    // /*
    //     try to unpause after setCurrencyReceiver
    // */
    // function testUnpauseAfterSetCurrencyReceiver() public {
    //     uint256 time = block.timestamp;
    //     vm.warp(time);
    //     vm.prank(owner);
    //     raise.pause();
    //     assertTrue(raise.paused());
    //     assertTrue(raise.lastPause() == time);
    //     vm.warp(time + 2 hours);
    //     vm.prank(owner);
    //     raise.setCurrencyReceiver(paymentTokenProvider); 
    //     assertTrue(raise.lastPause() == time + 2 hours);       
    //     vm.warp(time + raise.delay() + 2 hours + 1 seconds);
    //     vm.prank(owner);
    //     raise.unpause();
    // }

    // /*
    //     try to unpause too soon after setMinAmountPerBuyer
    // */
    // function testFailUnpauseTooSoonAfterSetMinAmountPerBuyer() public {
    //     uint256 time = block.timestamp;
    //     vm.warp(time);
    //     vm.prank(owner);
    //     raise.pause();
    //     assertTrue(raise.paused());
    //     assertTrue(raise.lastPause() == time);
    //     vm.warp(time + 2 hours);
    //     vm.prank(owner);
    //     raise.setMinAmountPerBuyer(700); 
    //     assertTrue(raise.lastPause() == time + 2 hours);       
    //     vm.warp(time + raise.delay() + 1 hours);
    //     vm.prank(owner);
    //     raise.unpause(); // must fail because of the parameter update
    // }

    // /*
    //     try to unpause after setMinAmountPerBuyer
    // */
    // function testUnpauseAfterSetMinAmountPerBuyer() public {
    //     uint256 time = block.timestamp;
    //     vm.warp(time);
    //     vm.prank(owner);
    //     raise.pause();
    //     assertTrue(raise.paused());
    //     assertTrue(raise.lastPause() == time);
    //     vm.warp(time + 2 hours);
    //     vm.prank(owner);
    //     raise.setMinAmountPerBuyer(700); 
    //     assertTrue(raise.lastPause() == time + 2 hours);       
    //     vm.warp(time + raise.delay() + 2 hours + 1 seconds);
    //     vm.prank(owner);
    //     raise.unpause();
    // }

    // /*
    //     try to unpause too soon after setMaxAmountPerBuyer
    // */
    // function testFailUnpauseTooSoonAfterSetMaxAmountPerBuyer() public {
    //     uint256 time = block.timestamp;
    //     vm.warp(time);
    //     vm.prank(owner);
    //     raise.pause();
    //     assertTrue(raise.paused());
    //     assertTrue(raise.lastPause() == time);
    //     vm.warp(time + 2 hours);
    //     vm.prank(owner);
    //     raise.setMaxAmountPerBuyer(700);
    //     assertTrue(raise.lastPause() == time + 2 hours);        
    //     vm.warp(time + raise.delay() + 1 hours);
    //     vm.prank(owner);
    //     raise.unpause(); // must fail because of the parameter update
    // }

    // /*
    //     try to unpause after setMaxAmountPerBuyer
    // */
    // function testUnpauseAfterSetMaxAmountPerBuyer() public {
    //     uint256 time = block.timestamp;
    //     vm.warp(time);
    //     vm.prank(owner);
    //     raise.pause();
    //     assertTrue(raise.paused());
    //     assertTrue(raise.lastPause() == time);
    //     vm.warp(time + 2 hours);
    //     vm.prank(owner);
    //     raise.setMaxAmountPerBuyer(2 * minAmountPerBuyer);
    //     assertTrue(raise.lastPause() == time + 2 hours);        
    //     vm.warp(time + raise.delay() + 2 hours + 1 seconds);
    //     vm.prank(owner);
    //     raise.unpause();
    // }

    // /*
    //     try to unpause too soon after setCurrencyAndTokenPrice
    // */
    // function testFailUnpauseTooSoonAfterSetCurrencyAndTokenPrice() public {
    //     uint256 time = block.timestamp;
    //     vm.warp(time);
    //     vm.prank(owner);
    //     raise.pause();
    //     assertTrue(raise.paused());
    //     assertTrue(raise.lastPause() == time);
    //     vm.warp(time + 2 hours);
    //     vm.prank(owner);
    //     raise.setCurrencyAndTokenPrice(paymentToken, 700);  
    //     assertTrue(raise.lastPause() == time + 2 hours);       
    //     vm.warp(time + raise.delay() + 1 hours);
    //     vm.prank(owner);
    //     raise.unpause(); // must fail because of the parameter update
    // }

    // /*
    //     try to unpause after setCurrencyAndTokenPrice
    // */
    // function testUnpauseAfterSetCurrencyAndTokenPrice() public {
    //     uint256 time = block.timestamp;
    //     vm.warp(time);
    //     vm.prank(owner);
    //     raise.pause();
    //     assertTrue(raise.paused());
    //     assertTrue(raise.lastPause() == time);
    //     vm.warp(time + 2 hours);
    //     vm.prank(owner);
    //     raise.setCurrencyAndTokenPrice(paymentToken, 700); 
    //     assertTrue(raise.lastPause() == time + 2 hours);       
    //     vm.warp(time + raise.delay() + 2 hours + 1 seconds);
    //     vm.prank(owner);
    //     raise.unpause();
    // }

}