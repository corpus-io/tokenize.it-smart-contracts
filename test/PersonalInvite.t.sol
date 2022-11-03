// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/CorpusToken.sol";
import "../contracts/PersonalInvite.sol";
import "./FakePaymentToken.sol";



contract PersonalInviteTest is Test {
    AllowList list;
    CorpusToken token;
    CorpusToken currency; // todo: add different ERC20 token as currency!
    PersonalInvite invite;

    uint256 MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

    address public constant turstedForwarder = 0x84a0856b038eaAd1cC7E297cF34A7e72685A8693;
    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant buyer = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant minterAdmin = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant minter = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant owner = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant receiver = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant paymentTokenProvider = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant trustedForwarder = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;


    uint256 public constant price = 10000000;

    function setUp() public {
        list = new AllowList();
        token = new CorpusToken(turstedForwarder, admin, list, 0x0, "TESTTOKEN", "TEST");
        currency = new CorpusToken(turstedForwarder, admin, list, 0x0, "CURRENCY", "CUR");
        vm.prank(owner);

        
        invite = new PersonalInvite(trustedForwarder, payable(buyer), payable(receiver), 1, 1000000000000000, price, block.timestamp + 1 days, currency, MintableERC20(address(token)));

        // allow invite contract to mint
        bytes32 roleMinterAdmin = token.MINTERADMIN_ROLE();

        vm.prank(admin);
        token.grantRole(roleMinterAdmin, minterAdmin);
        vm.prank(minterAdmin);
        token.setUpMinter(address(invite), 1000000000000000);

        // mint currency for buyer

        vm.prank(admin);
        currency.grantRole(roleMinterAdmin, minterAdmin);
        vm.prank(minterAdmin);
        currency.setUpMinter(minter, 10000000000);
        assertTrue(currency.mintingAllowance(minter) == 10000000000);

        vm.prank(minter);
        currency.mint(buyer, 10000000000);
        assertTrue(currency.balanceOf(buyer) == 10000000000);

        // give invite contract allowance
        vm.prank(buyer);
        currency.approve(address(invite), 10000000000);
    }

    function testConstructor() public {
        PersonalInvite inviteLocal;
        inviteLocal = new PersonalInvite(trustedForwarder, payable(buyer), payable(receiver), 1, 1000, 10, block.timestamp + 1 days, currency, MintableERC20(address(token)));
        assertTrue(inviteLocal.owner() == address(this));
        assertTrue(inviteLocal.buyer() == buyer);
        assertTrue(inviteLocal.receiver() == receiver);
        assertTrue(inviteLocal.minAmount() ==1);
        assertTrue(inviteLocal.maxAmount() == 1000);
        assertTrue(inviteLocal.tokenPrice() == 10);
        assertTrue(inviteLocal.expiration() ==  block.timestamp + 1 days);
        assertTrue(inviteLocal.currency() == currency);
        assertTrue(inviteLocal.token() == MintableERC20(address(token)));
    }

    function testFailDealHappyCase2() public {
        assertTrue(currency.balanceOf(buyer) == 10000000000);
        vm.prank(buyer);
        invite.deal(100);
        assertTrue(currency.balanceOf(buyer) == 10000000000 - (100 * 10000000) / (10**token.decimals()));
        assertTrue(token.balanceOf(buyer) == 100);
        assertTrue(currency.balanceOf(receiver) == (100 * 10000000) / (10**token.decimals()));
    }

    function testDealHappyCase2() public {
        assertTrue(currency.balanceOf(buyer) == 10000000000);
        vm.prank(buyer);
        invite.deal(100000000000000);
        assertTrue(currency.balanceOf(buyer) == 10000000000 - (100000000000000 * 10000000) / (10**token.decimals()));
        assertTrue(token.balanceOf(buyer) == 100000000000000);
        assertTrue(currency.balanceOf(receiver) == (100000000000000 * 10000000) / (10**token.decimals()));
    }

    // todo: make sure a valid test case is found
    function testDealHappyCaseX(uint256 tokenSaleBits) public {
        // limit tokenSaleBits to to values [minAmount, maxAmount]
        vm.assume(tokenSaleBits >= invite.minAmount());
        vm.assume(tokenSaleBits <= invite.maxAmount());
        if ((tokenSaleBits * invite.tokenPrice()) % (10**token.decimals()) == 0) {
            // test cases without rest must be successful
            uint256 buyerStartCurrencyBalance = currency.balanceOf(buyer);
            // uint256 tokenSaleBits = 2.7 * 10**14;
            uint256 currencyCost = (tokenSaleBits * price) / (10**token.decimals());
            uint256 expectedBuyerCurrencyBalance =  buyerStartCurrencyBalance - currencyCost;

            assertTrue(currency.balanceOf(buyer) == buyerStartCurrencyBalance); // buyer owns 10**10 currency, so 10**10 * 10**currency.decimals() currency bits (bit = smallest subunit of token)
            vm.prank(buyer);
            invite.deal(tokenSaleBits); // buyer brings in their amount of payment currency in bits

            assertTrue(currency.balanceOf(buyer) == expectedBuyerCurrencyBalance);
            assertTrue(token.balanceOf(buyer) == tokenSaleBits);
            assertTrue(currency.balanceOf(receiver) == currencyCost);
        }
        else {
            // test cases with rest must fail
            vm.prank(buyer);
            vm.expectRevert('Amount * tokenprice needs to be a multiple of 10**token.decimals()');
            invite.deal(tokenSaleBits);
        }
    }

    /*
    set up with FakePaymentToken which has variable decimals to make sure that doesn't break anything
    */
    function testDealHappyCaseVaryDecimals() public {

        uint8 maxDecimals = 25;
        FakePaymentToken paymentToken; 


        for (uint8 paymentTokenDecimals=1; paymentTokenDecimals<maxDecimals; paymentTokenDecimals++) {

            //uint8 paymentTokenDecimals = 10;

            /*
            paymentToken: 1 FPT = 10**paymentTokenDecimals FPTbits (bit = smallest subunit of token)
            corpusToken: 1 CT = 10**18 CTbits
            price definition: 30FPT buy 1CT, but must be expressed in FPTbits/CT
            price = 30 * 10**paymentTokenDecimals
            */
            uint256 _price = 30 * 10**paymentTokenDecimals;
            uint256 maxMintAmount = 2**256 - 1;
            uint256 _paymentTokenAmount = 1000 * 10**paymentTokenDecimals;

            list = new AllowList();
            token = new CorpusToken(turstedForwarder, admin, list, 0x0, "TESTTOKEN", "TEST");
            vm.prank(paymentTokenProvider);
            paymentToken = new FakePaymentToken(_paymentTokenAmount, paymentTokenDecimals);
            vm.prank(owner);

            

            invite = new PersonalInvite(trustedForwarder, payable(buyer), payable(receiver), 1, maxMintAmount, _price, block.timestamp + 1 days, paymentToken, MintableERC20(address(token)));

            // allow invite contract to mint
            bytes32 roleMinterAdmin = token.MINTERADMIN_ROLE();

            vm.prank(admin);
            token.grantRole(roleMinterAdmin, minterAdmin);
            vm.prank(minterAdmin);
            token.setUpMinter(address(invite), maxMintAmount);

            // mint paymentToken for buyer
            vm.prank(paymentTokenProvider);
            paymentToken.transfer(buyer, _paymentTokenAmount);
            assertTrue(paymentToken.balanceOf(buyer) == _paymentTokenAmount);

            // give invite contract allowance
            vm.prank(buyer);
            paymentToken.approve(address(invite), _paymentTokenAmount);

            // run actual test
        
            // buyer has 1k FPT
            assertTrue(paymentToken.balanceOf(buyer) == _paymentTokenAmount);
            // they should be able to buy 33 CT for 999 FPT
            vm.prank(buyer);
            invite.deal(33 * 10**18);
            // buyer should have 10 FPT left
            assertTrue(paymentToken.balanceOf(buyer) == 10 * 10**paymentTokenDecimals);
            // buyer should have the 33 CT they bought
            assertTrue(token.balanceOf(buyer) == 33 * 10**18);
            // receiver should have the 990 FPT that were paid
            assertTrue(paymentToken.balanceOf(receiver) == 990 * 10**paymentTokenDecimals);
        }
    }

    function testFailOverflow() public {
        list = new AllowList();
        token = new CorpusToken(turstedForwarder, admin, list, 0x0, "TESTTOKEN", "TEST");
        currency = new CorpusToken(turstedForwarder, admin, list, 0x0, "CURRENCY", "CUR");
        vm.prank(owner);
        invite = new PersonalInvite(trustedForwarder, payable(buyer), payable(receiver), 1, MAX_INT, 100, block.timestamp + 1 days, currency, MintableERC20(address(token)));

        // allow invite contract to mint
        bytes32 roleMinterAdmin = token.MINTERADMIN_ROLE();

        vm.prank(admin);
        token.grantRole(roleMinterAdmin, minterAdmin);
        vm.prank(minterAdmin);
        token.setUpMinter(address(invite), MAX_INT);

        // mint currency for buyer

        vm.prank(admin);
        currency.grantRole(roleMinterAdmin, minterAdmin);
        vm.prank(minterAdmin);
        currency.setUpMinter(minter, MAX_INT);
        

        vm.prank(minter);
        currency.mint(buyer, MAX_INT);

        // give invite contract allowance
        vm.prank(buyer);
        currency.approve(address(invite), MAX_INT);
        vm.prank(buyer);
        invite.deal(MAX_INT);
    }

    function testEzCodeUseCase() public {
        // ["0x9be15eeadcE10d16aee7eF765f55c5BEDb410204","0x6aEe7ebe278bBd044Ae837cA82E84b210620Cad1","10000000000000000000","200000000000000000000",2,1654695694774,"0x07865c6E87B9F70255377e024ace6630C1Eaa37F","0x512681E4ecd449069282101FA3e482827528B062"]
        list = new AllowList();
        token = new CorpusToken(turstedForwarder, admin, list, 0x0, "TESTTOKEN", "TEST");
        currency = new CorpusToken(turstedForwarder, admin, list, 0x0, "CURRENCY", "CUR");
        vm.prank(owner);
        invite = new PersonalInvite(trustedForwarder, payable(buyer), payable(receiver), 10000000000000000000, 200000000000000000000, 2, block.timestamp + 1 days, currency, MintableERC20(address(token)));

        // allow invite contract to mint
        bytes32 roleMinterAdmin = token.MINTERADMIN_ROLE();

        vm.prank(admin);
        token.grantRole(roleMinterAdmin, minterAdmin);
        vm.prank(minterAdmin);
        token.setUpMinter(address(invite), 200000000000000000000);

        // mint currency for buyer
        vm.prank(admin);
        currency.grantRole(roleMinterAdmin, minterAdmin);
        vm.prank(minterAdmin);
        currency.setUpMinter(minter, 200000000000000000000);
        

        vm.prank(minter);
        currency.mint(buyer, 200000000000000000000);

        // give invite contract allowance
        vm.prank(buyer);
        currency.approve(address(invite), 200000000000000000000);
        vm.prank(buyer);
        invite.deal(10000000000000000000);
    }


    function testEzCodeUseCase2() public {
  //  ["0x9be15eeadcE10d16aee7eF765f55c5BEDb410204","0x6aEe7ebe278bBd044Ae837cA82E84b210620Cad1","10000000000000000000","200000000000000000000",2e12,1654940279453,"0x07865c6E87B9F70255377e024ace6630C1Eaa37F","0x3fe4799d41cb26e6bc1aa113e31c24ac492ec72b"]
        list = new AllowList();
        token = new CorpusToken(turstedForwarder, admin, list, 0x0, "TESTTOKEN", "TEST");
        currency = new CorpusToken(turstedForwarder, admin, list, 0x0, "CURRENCY", "CUR");
        vm.prank(owner);
        invite = new PersonalInvite(trustedForwarder, payable(buyer), payable(receiver), 10000000000000000000, 200000000000000000000, 2000000000000, block.timestamp + 1 days, currency, MintableERC20(address(token)));

        // allow invite contract to mint
        bytes32 roleMinterAdmin = token.MINTERADMIN_ROLE();

        vm.prank(admin);
        token.grantRole(roleMinterAdmin, minterAdmin);
        vm.prank(minterAdmin);
        token.setUpMinter(address(invite), 200000000000000000000);

        // mint currency for buyer

        vm.prank(admin);
        currency.grantRole(roleMinterAdmin, minterAdmin);
        vm.prank(minterAdmin);
        currency.setUpMinter(minter, 200000000000000000000 * 2000000000000);
        

        vm.prank(minter);
        currency.mint(buyer, 200000000000000000000 * 2000000000000);

        // give invite contract allowance
        vm.prank(buyer);
        currency.approve(address(invite), 200000000000000000000 * 2000000000000);
        vm.prank(buyer);
        invite.deal(10000000000000000000);
    }

    

    function testRevoke() public {
        vm.prank(owner);
        invite.revoke();
    }

    // TODO: add tests for all requirements and edge cases
}