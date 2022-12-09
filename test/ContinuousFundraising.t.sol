// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/Token.sol";
import "../contracts/ContinuousFundraising.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/MaliciousPaymentToken.sol";

contract ContinuousFundraisingTest is Test {
    ContinuousFundraising raise;
    AllowList list;
    FeeSettings feeSettings;

    Token token;
    FakePaymentToken paymentToken;

    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant buyer = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant mintAllower =
        0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant minter = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant owner = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant receiver =
        0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant paymentTokenProvider =
        0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant trustedForwarder =
        0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    uint8 public constant paymentTokenDecimals = 6;
    uint256 public constant paymentTokenAmount =
        1000 * 10 ** paymentTokenDecimals;

    uint256 public constant price = 7 * 10 ** paymentTokenDecimals; // 7 payment tokens per token

    uint256 public constant maxAmountOfTokenToBeSold = 20 * 10 ** 18; // 20 token
    uint256 public constant maxAmountPerBuyer = maxAmountOfTokenToBeSold / 2; // 10 token
    uint256 public constant minAmountPerBuyer = maxAmountOfTokenToBeSold / 200; // 0.1 token

    function setUp() public {
        list = new AllowList();
        Fees memory fees = Fees(100, 100, 100, 100);
        feeSettings = new FeeSettings(fees, admin);

        token = new Token(
            trustedForwarder,
            feeSettings,
            admin,
            list,
            0x0,
            "TESTTOKEN",
            "TEST"
        );

        // set up currency
        vm.prank(paymentTokenProvider);
        paymentToken = new FakePaymentToken(
            paymentTokenAmount,
            paymentTokenDecimals
        ); // 1000 tokens with 6 decimals
        // transfer currency to buyer
        vm.prank(paymentTokenProvider);
        paymentToken.transfer(buyer, paymentTokenAmount);
        assertTrue(paymentToken.balanceOf(buyer) == paymentTokenAmount);

        vm.prank(owner);
        raise = new ContinuousFundraising(
            trustedForwarder,
            payable(receiver),
            minAmountPerBuyer,
            maxAmountPerBuyer,
            price,
            maxAmountOfTokenToBeSold,
            paymentToken,
            token
        );

        // allow raise contract to mint
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(admin);
        token.grantRole(roleMintAllower, mintAllower);
        vm.prank(mintAllower);
        token.increaseMintingAllowance(
            address(raise),
            maxAmountOfTokenToBeSold
        );

        // give raise contract allowance
        vm.prank(buyer);
        paymentToken.approve(address(raise), paymentTokenAmount);
    }

    function testConstructorHappyCase() public {
        ContinuousFundraising _raise = new ContinuousFundraising(
            trustedForwarder,
            payable(receiver),
            minAmountPerBuyer,
            maxAmountPerBuyer,
            price,
            maxAmountOfTokenToBeSold,
            paymentToken,
            token
        );
        assertTrue(_raise.owner() == address(this));
        assertTrue(_raise.currencyReceiver() == receiver);
        assertTrue(_raise.minAmountPerBuyer() == minAmountPerBuyer);
        assertTrue(_raise.maxAmountPerBuyer() == maxAmountPerBuyer);
        assertTrue(_raise.tokenPrice() == price);
        assertTrue(_raise.currency() == paymentToken);
        assertTrue(_raise.token() == token);
    }

    function testConstructorWithAddress0() public {
        vm.expectRevert("trustedForwarder can not be zero address");
        new ContinuousFundraising(
            address(0),
            receiver,
            minAmountPerBuyer,
            maxAmountPerBuyer,
            price,
            maxAmountOfTokenToBeSold,
            paymentToken,
            token
        );

        vm.expectRevert("currencyReceiver can not be zero address");
        new ContinuousFundraising(
            trustedForwarder,
            address(0),
            minAmountPerBuyer,
            maxAmountPerBuyer,
            price,
            maxAmountOfTokenToBeSold,
            paymentToken,
            token
        );

        vm.expectRevert("currency can not be zero address");
        new ContinuousFundraising(
            trustedForwarder,
            receiver,
            minAmountPerBuyer,
            maxAmountPerBuyer,
            price,
            maxAmountOfTokenToBeSold,
            IERC20(address(0)),
            token
        );

        vm.expectRevert("token can not be zero address");
        new ContinuousFundraising(
            trustedForwarder,
            receiver,
            minAmountPerBuyer,
            maxAmountPerBuyer,
            price,
            maxAmountOfTokenToBeSold,
            paymentToken,
            Token(address(0))
        );
    }

    /*
    set up with MaliciousPaymentToken which tries to reenter the buy function
    */
    function testReentrancy() public {
        MaliciousPaymentToken _paymentToken;
        uint8 _paymentTokenDecimals = 18;

        /*
        _paymentToken: 1 FPT = 10**_paymentTokenDecimals FPTbits (bit = smallest subunit of token)
        Token: 1 CT = 10**18 CTbits
        price definition: 30FPT buy 1CT, but must be expressed in FPTbits/CT
        price = 30 * 10**_paymentTokenDecimals
        */

        uint256 _price = 7 * 10 ** _paymentTokenDecimals;
        uint256 _maxMintAmount = 1000 * 10 ** 18; // 2**256 - 1; // need maximum possible value because we are using a fake token with variable decimals
        uint256 _paymentTokenAmount = 100000 * 10 ** _paymentTokenDecimals;

        list = new AllowList();
        Token _token = new Token(
            trustedForwarder,
            feeSettings,
            admin,
            list,
            0x0,
            "TESTTOKEN",
            "TEST"
        );
        vm.prank(paymentTokenProvider);
        _paymentToken = new MaliciousPaymentToken(_paymentTokenAmount);
        vm.prank(owner);

        ContinuousFundraising _raise = new ContinuousFundraising(
            trustedForwarder,
            payable(receiver),
            1,
            _maxMintAmount / 100,
            _price,
            _maxMintAmount,
            _paymentToken,
            _token
        );

        // allow invite contract to mint
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(admin);
        _token.grantRole(roleMintAllower, mintAllower);
        vm.startPrank(mintAllower);
        _token.increaseMintingAllowance(
            address(_raise),
            _maxMintAmount - token.mintingAllowance(address(_raise))
        );
        vm.stopPrank();

        // mint _paymentToken for buyer
        vm.prank(paymentTokenProvider);
        _paymentToken.transfer(buyer, _paymentTokenAmount);
        assertTrue(_paymentToken.balanceOf(buyer) == _paymentTokenAmount);

        // set exploitTarget
        _paymentToken.setExploitTarget(
            address(_raise),
            3,
            _maxMintAmount / 200000
        );

        // give invite contract allowance
        vm.prank(buyer);
        _paymentToken.approve(address(_raise), _paymentTokenAmount);

        // store some state
        //uint buyerPaymentBalanceBefore = _paymentToken.balanceOf(buyer);

        // run actual test
        assertTrue(_paymentToken.balanceOf(buyer) == _paymentTokenAmount);
        uint256 buyAmount = _maxMintAmount / 100000;
        vm.prank(buyer);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        _raise.buy(buyAmount);

        // // tests to be run when exploit is successful
        // uint paymentTokensSpent = buyerPaymentBalanceBefore - _paymentToken.balanceOf(buyer);
        // console.log("buyer spent: ", buyerPaymentBalanceBefore - _paymentToken.balanceOf(buyer));
        // console.log("buyer tokens:", _token.balanceOf(buyer));
        // console.log("minted tokens:", _token.totalSupply());
        // uint pricePaidForBuyerTokens = paymentTokensSpent / _token.balanceOf(buyer) * 10**_paymentTokenDecimals;
        // uint pricePaidForAllTokens = _paymentToken.balanceOf(receiver) / _token.totalSupply() * 10**_paymentTokenDecimals;
        // console.log("total price paid: ", pricePaidForAllTokens);
        // console.log("price: ", _price);
        // // minted tokens must fit payment received and price
        // assertTrue(_token.totalSupply() == paymentTokensSpent / _price * 10**_paymentTokenDecimals);
        // assertTrue(pricePaidForAllTokens == _price);

        // // assert internal accounting is correct
        // console.log("tokens sold:", _raise.tokensSold());
        // // assertTrue(_raise.tokensSold() == _token.balanceOf(buyer));
        // // assertTrue(_raise.tokensBought(buyer) == _token.balanceOf(buyer));
    }

    function testBuyHappyCase() public {
        uint256 tokenBuyAmount = 5 * 10 ** token.decimals();
        uint256 costInPaymentToken = (tokenBuyAmount * price) / 10 ** 18;

        assert(costInPaymentToken == 35 * 10 ** paymentTokenDecimals); // 35 payment tokens, manually calculated

        uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(buyer);

        vm.prank(buyer);
        raise.buy(tokenBuyAmount); // this test fails if 5 * 10**18 is replaced with 5 * 10**token.decimals() for this argument, even though they should be equal
        assertTrue(
            paymentToken.balanceOf(buyer) ==
                paymentTokenBalanceBefore - costInPaymentToken
        );
        assertTrue(
            token.balanceOf(buyer) == tokenBuyAmount,
            "buyer has tokens"
        );
        assertTrue(
            paymentToken.balanceOf(receiver) ==
                costInPaymentToken -
                    costInPaymentToken /
                    token.feeSettings().continuousFundraisingFeeDenominator(),
            "receiver has payment tokens"
        );
        assertTrue(
            paymentToken.balanceOf(token.feeSettings().feeCollector()) ==
                costInPaymentToken /
                    token.feeSettings().continuousFundraisingFeeDenominator(),
            "fee collector has collected fee in payment tokens"
        );
        assertTrue(
            token.balanceOf(token.feeSettings().feeCollector()) ==
                tokenBuyAmount / token.feeSettings().tokenFeeDenominator(),
            "fee collector has collected fee in tokens"
        );
        assertTrue(
            raise.tokensSold() == tokenBuyAmount,
            "raise has sold tokens"
        );
        assertTrue(
            raise.tokensBought(buyer) == tokenBuyAmount,
            "raise has sold tokens to buyer"
        );
    }

    function testBuyTooMuch() public {
        uint256 tokenBuyAmount = 5 * 10 ** token.decimals();
        uint256 costInPaymentToken = (tokenBuyAmount * price) / 10 ** 18;

        assert(costInPaymentToken == 35 * 10 ** paymentTokenDecimals); // 35 payment tokens, manually calculated

        uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(buyer);

        vm.prank(buyer);
        vm.expectRevert(
            "Total amount of bought tokens needs to be lower than or equal to maxAmount"
        );
        raise.buy(maxAmountPerBuyer + 10 ** 18); //+ 10**token.decimals());
        assertTrue(paymentToken.balanceOf(buyer) == paymentTokenBalanceBefore);
        assertTrue(token.balanceOf(buyer) == 0);
        assertTrue(paymentToken.balanceOf(receiver) == 0);
        assertTrue(raise.tokensSold() == 0);
        assertTrue(raise.tokensBought(buyer) == 0);
    }

    function testMultiplePeopleBuyTooMuch() public {
        address person1 = vm.addr(1);
        address person2 = vm.addr(2);

        uint256 availableBalance = paymentToken.balanceOf(buyer);

        vm.prank(buyer);
        paymentToken.transfer(person1, availableBalance / 2);
        vm.prank(buyer);
        paymentToken.transfer(person2, 10 ** 6);

        vm.prank(person1);
        paymentToken.approve(address(raise), paymentTokenAmount);

        vm.prank(person2);
        paymentToken.approve(address(raise), paymentTokenAmount);

        vm.prank(buyer);
        raise.buy(maxAmountOfTokenToBeSold / 2);
        vm.prank(person1);
        raise.buy(maxAmountOfTokenToBeSold / 2);
        vm.prank(person2);
        vm.expectRevert("Not enough tokens to sell left");
        raise.buy(10 ** 18);
    }

    function testExceedMintingAllowance() public {
        // reduce minting allowance of fundraising contract, so the revert happens in Token
        vm.startPrank(mintAllower);
        token.decreaseMintingAllowance(
            address(raise),
            token.mintingAllowance(address(raise)) - (maxAmountPerBuyer / 2)
        );
        vm.stopPrank();

        vm.prank(buyer);
        vm.expectRevert("MintingAllowance too low");
        raise.buy(maxAmountPerBuyer); //+ 10**token.decimals());
        assertTrue(token.balanceOf(buyer) == 0);
        assertTrue(paymentToken.balanceOf(receiver) == 0);
        assertTrue(raise.tokensSold() == 0);
        assertTrue(raise.tokensBought(buyer) == 0);
    }

    function testBuyTooLittle() public {
        uint256 tokenBuyAmount = 5 * 10 ** token.decimals();
        uint256 costInPaymentToken = (tokenBuyAmount * price) / 10 ** 18;

        assert(costInPaymentToken == 35 * 10 ** paymentTokenDecimals); // 35 payment tokens, manually calculated

        uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(buyer);

        vm.prank(buyer);
        vm.expectRevert("Buyer needs to buy at least minAmount");
        raise.buy(minAmountPerBuyer / 2);
        assertTrue(paymentToken.balanceOf(buyer) == paymentTokenBalanceBefore);
        assertTrue(token.balanceOf(buyer) == 0);
        assertTrue(paymentToken.balanceOf(receiver) == 0);
        assertTrue(raise.tokensSold() == 0);
        assertTrue(raise.tokensBought(buyer) == 0);
    }

    function testBuySmallAmountAfterInitialInvestment() public {
        uint256 tokenBuyAmount = minAmountPerBuyer;
        uint256 costInPaymentTokenForMinAmount = (tokenBuyAmount * price) /
            10 ** 18;
        uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(buyer);

        vm.prank(buyer);
        raise.buy(minAmountPerBuyer);

        // buy less than minAmount -> should be okay because minAmount has already been bought.
        vm.prank(buyer);
        raise.buy(minAmountPerBuyer / 2);

        assertTrue(
            paymentToken.balanceOf(buyer) ==
                paymentTokenBalanceBefore -
                    (costInPaymentTokenForMinAmount * 3) /
                    2,
            "buyer has payment tokens"
        );
        assertTrue(
            token.balanceOf(buyer) == (minAmountPerBuyer * 3) / 2,
            "buyer has tokens"
        );
        uint256 tokenFee = (minAmountPerBuyer * 3) /
            2 /
            token.feeSettings().tokenFeeDenominator();
        uint256 paymentTokenFee = (costInPaymentTokenForMinAmount * 3) /
            2 /
            token.feeSettings().continuousFundraisingFeeDenominator();
        assertTrue(
            paymentToken.balanceOf(receiver) ==
                (costInPaymentTokenForMinAmount * 3) / 2 - paymentTokenFee,
            "receiver received payment tokens"
        );
        assertEq(
            token.balanceOf(token.feeSettings().feeCollector()),
            tokenFee,
            "fee collector has collected fee in tokens"
        );
        assertTrue(
            raise.tokensSold() == (minAmountPerBuyer * 3) / 2,
            "raise has sold tokens"
        );
        assertTrue(
            raise.tokensBought(buyer) == raise.tokensSold(),
            "raise has sold tokens to buyer"
        );
    }

    function ensureRealCostIsHigherEqualAdvertisedCost(
        uint256 tokenBuyAmount
    ) public {
        uint256 _price = 1; // price = 1 currency bit per full token (10**18 token bits)

        // set price that is finer than the resolution of the payment token
        vm.startPrank(owner);
        raise.pause();
        raise.setCurrencyAndTokenPrice(raise.currency(), _price);
        raise.setMinAmountPerBuyer(1); // min amount = 1 currency bit
        vm.warp(block.timestamp + 1 days + 1 seconds);
        raise.unpause();
        vm.stopPrank();

        // this is rounded down and resolves to 0 cost in payment token
        uint256 naiveCostInPaymentToken = (tokenBuyAmount * _price) / 10 ** 18;
        console.log("naiveCostInPaymentToken", naiveCostInPaymentToken);
        //assertTrue(naiveCostInPaymentToken == 0, "Naive cost is not 0"); // 35 payment tokens, manually calculated

        uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(buyer);

        vm.prank(buyer);
        raise.buy(tokenBuyAmount);

        console.log("paymentTokenBalanceBefore", paymentTokenBalanceBefore);
        console.log(
            "paymentToken.balanceOf(buyer)",
            paymentToken.balanceOf(buyer)
        );

        uint256 realCostInPaymentToken = paymentTokenBalanceBefore -
            paymentToken.balanceOf(buyer);
        uint256 realPrice = (realCostInPaymentToken * 10 ** 18) /
            token.balanceOf(buyer);
        console.log("realCostInPaymentToken", realCostInPaymentToken);
        console.log("token.balanceOf(buyer)", token.balanceOf(buyer));
        console.log("advertised price: ", raise.tokenPrice());
        console.log("real price: ", realPrice);
        assertTrue(
            token.balanceOf(buyer) == tokenBuyAmount,
            "buyer has not received tokens"
        );
        assertTrue(
            paymentToken.balanceOf(receiver) >= 1,
            "receiver has not received any payment"
        );
        assertTrue(
            realCostInPaymentToken >= 1,
            "real cost is 0, but should be at least 1"
        );
        assertTrue(
            realCostInPaymentToken - naiveCostInPaymentToken >= 0,
            "real cost is less than advertised cost"
        );
        assertTrue(
            realCostInPaymentToken - naiveCostInPaymentToken <= 1,
            "more than 1 currency bit was rounded!"
        );
        assertTrue(realPrice >= _price, "real price is less than advertised");
    }

    function testBuyAnyAmountRoundsUp(uint tokenBuyAmount) public {
        vm.assume(tokenBuyAmount < raise.maxAmountPerBuyer());
        vm.assume(tokenBuyAmount > 0);
        ensureRealCostIsHigherEqualAdvertisedCost(tokenBuyAmount);
    }

    function testBuy1BitRoundsUp() public {
        // this will result in the naive cost being 0
        ensureRealCostIsHigherEqualAdvertisedCost(1);
    }

    function testWithAllPossiblePricesAndAmounts(
        uint _tokenBuyAmount,
        uint _tokenPrice
    ) public {
        vm.assume(_tokenBuyAmount > 0);
        vm.assume(_tokenPrice > 0);
        /* 
        need to enforce: _tokenBuyAmount * _tokenPrice / 10 ** token.decimals() < UINT256_MAX
        otherwise the multiplication will overflow
        this is equivalent to both of these expressions, which don't overflow: 
        _tokenBuyAmount / 10 ** token.decimals() < UINT256_MAX / _tokenPrice
        _tokenPrice / 10 ** token.decimals() < UINT256_MAX / _tokenBuyAmount
        */
        vm.assume(
            _tokenBuyAmount / (10 ** token.decimals()) <
                UINT256_MAX / _tokenPrice - 1
        );
        vm.assume(
            _tokenPrice / (10 ** token.decimals()) <
                UINT256_MAX / _tokenBuyAmount - 1
        );

        // calculate amounts
        uint256 tokenDecimals = token.decimals();
        uint minCurrencyAmount;
        if (_tokenBuyAmount < UINT256_MAX / _tokenPrice) {
            // if the multiplication does not overflow, we can use 256 bit arithmetic
            minCurrencyAmount =
                (_tokenBuyAmount * _tokenPrice) /
                10 ** tokenDecimals;
        } else {
            // if the multiplication overflows, we have to use 512 bit arithmetic
            minCurrencyAmount = Math.mulDiv(
                _tokenBuyAmount,
                _tokenPrice,
                10 ** tokenDecimals
            );
        }
        console.log("minCurrencyAmount: %s", minCurrencyAmount);
        uint maxCurrencyAmount = minCurrencyAmount + 1;
        console.log("maxCurrencyAmount: %s", maxCurrencyAmount);

        // set up currency
        vm.startPrank(paymentTokenProvider);
        paymentToken = new FakePaymentToken(
            maxCurrencyAmount,
            paymentTokenDecimals
        ); // 1000 tokens with 6 decimals
        // transfer currency to buyer
        paymentToken.transfer(buyer, maxCurrencyAmount);
        vm.stopPrank();
        assertTrue(paymentToken.balanceOf(buyer) == maxCurrencyAmount);

        assertEq(paymentToken.balanceOf(receiver), 0);
        assertEq(paymentToken.balanceOf(token.feeSettings().feeCollector()), 0);

        vm.startPrank(owner);
        raise = new ContinuousFundraising(
            trustedForwarder,
            payable(receiver),
            _tokenBuyAmount,
            _tokenBuyAmount,
            _tokenPrice,
            _tokenBuyAmount,
            paymentToken,
            token
        );
        vm.stopPrank();

        vm.startPrank(mintAllower);
        token.increaseMintingAllowance(
            address(raise),
            _tokenBuyAmount - token.mintingAllowance(address(raise))
        );
        vm.stopPrank();

        vm.startPrank(buyer);
        paymentToken.approve(address(raise), maxCurrencyAmount);
        raise.buy(_tokenBuyAmount);
        vm.stopPrank();

        assertTrue(
            token.balanceOf(buyer) == _tokenBuyAmount,
            "buyer has not received tokens"
        );
        assertTrue(
            paymentToken.balanceOf(buyer) <= 1,
            "buyer did not pay expected amount"
        );
        assertTrue(
            paymentToken.balanceOf(receiver) +
                paymentToken.balanceOf(token.feeSettings().feeCollector()) >=
                minCurrencyAmount,
            "payment did not reach receiver or fee collector"
        );
        assertTrue(
            paymentToken.balanceOf(receiver) +
                paymentToken.balanceOf(token.feeSettings().feeCollector()) +
                paymentToken.balanceOf(buyer) ==
                maxCurrencyAmount,
            "currency does not add up"
        );
    }

    /*
        try to buy more than allowed
    */
    function testFailOverflow() public {
        vm.prank(buyer);
        raise.buy(maxAmountPerBuyer + 1);
    }

    /*
        try to buy less than allowed
    */
    function testFailUnderflow() public {
        vm.prank(buyer);
        raise.buy(minAmountPerBuyer - 1);
    }

    /*
        try to buy while paused
    */
    function testFailPaused() public {
        vm.prank(owner);
        raise.pause();
        vm.prank(buyer);
        raise.buy(minAmountPerBuyer);
    }

    /*
        try to update currencyReceiver not paused
    */
    function testFailUpdateCurrencyReceiverNotPaused() public {
        vm.prank(owner);
        raise.setCurrencyReceiver(payable(address(buyer)));
    }

    /*
        try to update currencyReceiver while paused
    */
    function testUpdateCurrencyReceiverPaused() public {
        assertTrue(raise.currencyReceiver() == receiver);
        vm.prank(owner);
        raise.pause();
        vm.prank(owner);
        raise.setCurrencyReceiver(payable(address(buyer)));
        assertTrue(raise.currencyReceiver() == address(buyer));

        vm.prank(owner);
        vm.expectRevert("receiver can not be zero address");
        raise.setCurrencyReceiver(address(0));
    }

    /* 
        try to update minAmountPerBuyer not paused
    */
    function testFailUpdateMinAmountPerBuyerNotPaused() public {
        vm.prank(owner);
        raise.setMinAmountPerBuyer(100);
    }

    /* 
        try to update minAmountPerBuyer while paused
    */
    function testUpdateMinAmountPerBuyerPaused() public {
        assertTrue(raise.minAmountPerBuyer() == minAmountPerBuyer);
        vm.prank(owner);
        raise.pause();
        vm.prank(owner);
        raise.setMinAmountPerBuyer(300);
        assertTrue(raise.minAmountPerBuyer() == 300);

        console.log("minAmount: ", raise.minAmountPerBuyer());
        console.log("maxAmount: ", raise.maxAmountPerBuyer());
        console.log("owner: ", raise.owner());
        console.log("_owner: ", owner);

        uint256 _maxAmountPerBuyer = raise.maxAmountPerBuyer();
        vm.expectRevert("_minAmount needs to be smaller or equal to maxAmount");
        vm.prank(owner);
        raise.setMinAmountPerBuyer(_maxAmountPerBuyer + 1); //raise.maxAmountPerBuyer() + 1);

        console.log("minAmount: ", raise.minAmountPerBuyer());
        console.log("maxAmount: ", raise.maxAmountPerBuyer());
    }

    /* 
        try to update maxAmountPerBuyer not paused
    */
    function testFailUpdateMaxAmountPerBuyerNotPaused() public {
        vm.prank(owner);
        raise.setMaxAmountPerBuyer(100);
    }

    /* 
        try to update maxAmountPerBuyer while paused
    */
    function testUpdateMaxAmountPerBuyerPaused() public {
        assertTrue(raise.maxAmountPerBuyer() == maxAmountPerBuyer);
        vm.prank(owner);
        raise.pause();
        vm.prank(owner);
        raise.setMaxAmountPerBuyer(minAmountPerBuyer);
        assertTrue(raise.maxAmountPerBuyer() == minAmountPerBuyer);
        uint256 _minAmountPerBuyer = raise.minAmountPerBuyer();
        vm.expectRevert("_maxAmount needs to be larger or equal to minAmount");
        vm.prank(owner);
        raise.setMaxAmountPerBuyer(_minAmountPerBuyer - 1);
    }

    /*
        try to update currency and price while not paused
    */
    function testFailUpdateCurrencyAndPriceNotPaused() public {
        FakePaymentToken newPaymentToken = new FakePaymentToken(700, 3);
        vm.prank(owner);
        raise.setCurrencyAndTokenPrice(newPaymentToken, 100);
    }

    /*
        try to update currency and price while paused
    */
    function testUpdateCurrencyAndPricePaused() public {
        assertTrue(raise.tokenPrice() == price);
        assertTrue(raise.currency() == paymentToken);

        FakePaymentToken newPaymentToken = new FakePaymentToken(700, 3);

        vm.prank(owner);
        raise.pause();
        vm.prank(owner);
        raise.setCurrencyAndTokenPrice(newPaymentToken, 700);
        assertTrue(raise.tokenPrice() == 700);
        assertTrue(raise.currency() == newPaymentToken);
        vm.prank(owner);
        vm.expectRevert("_tokenPrice needs to be a non-zero amount");
        raise.setCurrencyAndTokenPrice(paymentToken, 0);
    }

    /*
        try to update maxAmountOfTokenToBeSold while not paused
    */
    function testFailUpdateMaxAmountOfTokenToBeSoldNotPaused() public {
        vm.prank(owner);
        raise.setMaxAmountOfTokenToBeSold(123 * 10 ** 18);
    }

    /*
        try to update maxAmountOfTokenToBeSold while paused
    */
    function testUpdateMaxAmountOfTokenToBeSoldPaused() public {
        assertTrue(
            raise.maxAmountOfTokenToBeSold() == maxAmountOfTokenToBeSold
        );
        vm.prank(owner);
        raise.pause();
        vm.prank(owner);
        raise.setMaxAmountOfTokenToBeSold(minAmountPerBuyer);
        assertTrue(raise.maxAmountOfTokenToBeSold() == minAmountPerBuyer);
        vm.prank(owner);
        vm.expectRevert(
            "_maxAmountOfTokenToBeSold needs to be larger than zero"
        );
        raise.setMaxAmountOfTokenToBeSold(0);
    }

    /*
        try to unpause immediately after pausing
    */
    function testFailUnpauseImmediatelyAfterPausing() public {
        vm.prank(owner);
        raise.pause();
        assertTrue(raise.paused());
        assertTrue(raise.coolDownStart() > 0);
        vm.prank(owner);
        raise.unpause();
    }

    /*
        try to unpause after delay has passed
    */
    function testFailUnpauseAfterDelay() public {
        uint256 time = block.timestamp;
        vm.warp(time);
        vm.prank(owner);
        raise.pause();
        assertTrue(raise.paused());
        assertTrue(raise.coolDownStart() == time);
        vm.warp(time + raise.delay());
        vm.prank(owner);
        raise.unpause();
    }

    /*
        try to unpause after more than 1 day has passed
    */
    function testUnpauseAfterDelayAnd1Sec() public {
        uint256 time = block.timestamp;
        vm.warp(time);
        vm.prank(owner);
        raise.pause();
        assertTrue(raise.paused());
        assertTrue(raise.coolDownStart() == time);
        vm.warp(time + raise.delay() + 1 seconds);
        vm.prank(owner);
        raise.unpause();
    }

    /*
        try to unpause too soon after setMaxAmountOfTokenToBeSold
    */
    function testFailUnpauseTooSoonAfterSetMaxAmountOfTokenToBeSold() public {
        uint256 time = block.timestamp;
        vm.warp(time);
        vm.prank(owner);
        raise.pause();
        assertTrue(raise.paused());
        assertTrue(raise.coolDownStart() == time);
        vm.warp(time + 2 hours);
        vm.prank(owner);
        raise.setMaxAmountOfTokenToBeSold(700);
        assertTrue(raise.coolDownStart() == time + 2 hours);
        vm.warp(time + raise.delay() + 1 seconds);
        vm.prank(owner);
        raise.unpause(); // must fail because of the parameter update
    }

    /*
        try to unpause after setMaxAmountOfTokenToBeSold
    */
    function testUnpauseAfterSetMaxAmountOfTokenToBeSold() public {
        uint256 time = block.timestamp;
        vm.warp(time);
        vm.prank(owner);
        raise.pause();
        assertTrue(raise.paused());
        assertTrue(raise.coolDownStart() == time);
        vm.warp(time + 2 hours);
        vm.prank(owner);
        raise.setMaxAmountOfTokenToBeSold(700);
        assertTrue(raise.coolDownStart() == time + 2 hours);
        vm.warp(time + raise.delay() + 2 hours + 1 seconds);
        vm.prank(owner);
        raise.unpause();
    }

    /*
        try to unpause too soon after setCurrencyReceiver
    */
    function testFailUnpauseTooSoonAfterSetCurrencyReceiver() public {
        uint256 time = block.timestamp;
        vm.warp(time);
        vm.prank(owner);
        raise.pause();
        assertTrue(raise.paused());
        assertTrue(raise.coolDownStart() == time);
        vm.warp(time + 2 hours);
        vm.prank(owner);
        raise.setCurrencyReceiver(payable(address(buyer)));
        assertTrue(raise.coolDownStart() == time + 2 hours);
        vm.warp(time + raise.delay() + 1 hours);
        vm.prank(owner);
        raise.unpause(); // must fail because of the parameter update
    }

    /*
        try to unpause after setCurrencyReceiver
    */
    function testUnpauseAfterSetCurrencyReceiver() public {
        uint256 time = block.timestamp;
        vm.warp(time);
        vm.prank(owner);
        raise.pause();
        assertTrue(raise.paused());
        assertTrue(raise.coolDownStart() == time);
        vm.warp(time + 2 hours);
        vm.prank(owner);
        raise.setCurrencyReceiver(paymentTokenProvider);
        assertTrue(raise.coolDownStart() == time + 2 hours);
        vm.warp(time + raise.delay() + 2 hours + 1 seconds);
        vm.prank(owner);
        raise.unpause();
    }

    /*
        try to unpause too soon after setMinAmountPerBuyer
    */
    function testFailUnpauseTooSoonAfterSetMinAmountPerBuyer() public {
        uint256 time = block.timestamp;
        vm.warp(time);
        vm.prank(owner);
        raise.pause();
        assertTrue(raise.paused());
        assertTrue(raise.coolDownStart() == time);
        vm.warp(time + 2 hours);
        vm.prank(owner);
        raise.setMinAmountPerBuyer(700);
        assertTrue(raise.coolDownStart() == time + 2 hours);
        vm.warp(time + raise.delay() + 1 hours);
        vm.prank(owner);
        raise.unpause(); // must fail because of the parameter update
    }

    /*
        try to unpause after setMinAmountPerBuyer
    */
    function testUnpauseAfterSetMinAmountPerBuyer() public {
        uint256 time = block.timestamp;
        vm.warp(time);
        vm.prank(owner);
        raise.pause();
        assertTrue(raise.paused());
        assertTrue(raise.coolDownStart() == time);
        vm.warp(time + 2 hours);
        vm.prank(owner);
        raise.setMinAmountPerBuyer(700);
        assertTrue(raise.coolDownStart() == time + 2 hours);
        vm.warp(time + raise.delay() + 2 hours + 1 seconds);
        vm.prank(owner);
        raise.unpause();
    }

    /*
        try to unpause too soon after setMaxAmountPerBuyer
    */
    function testFailUnpauseTooSoonAfterSetMaxAmountPerBuyer() public {
        uint256 time = block.timestamp;
        vm.warp(time);
        vm.prank(owner);
        raise.pause();
        assertTrue(raise.paused());
        assertTrue(raise.coolDownStart() == time);
        vm.warp(time + 2 hours);
        vm.prank(owner);
        raise.setMaxAmountPerBuyer(700);
        assertTrue(raise.coolDownStart() == time + 2 hours);
        vm.warp(time + raise.delay() + 1 hours);
        vm.prank(owner);
        raise.unpause(); // must fail because of the parameter update
    }

    /*
        try to unpause after setMaxAmountPerBuyer
    */
    function testUnpauseAfterSetMaxAmountPerBuyer() public {
        uint256 time = block.timestamp;
        vm.warp(time);
        vm.prank(owner);
        raise.pause();
        assertTrue(raise.paused());
        assertTrue(raise.coolDownStart() == time);
        vm.warp(time + 2 hours);
        vm.prank(owner);
        raise.setMaxAmountPerBuyer(2 * minAmountPerBuyer);
        assertTrue(raise.coolDownStart() == time + 2 hours);
        vm.warp(time + raise.delay() + 2 hours + 1 seconds);
        vm.prank(owner);
        raise.unpause();
    }

    /*
        try to unpause too soon after setCurrencyAndTokenPrice
    */
    function testUnpauseTooSoonAfterSetCurrencyAndTokenPrice() public {
        uint256 time = block.timestamp;
        vm.warp(time);
        vm.prank(owner);
        raise.pause();
        assertTrue(raise.paused());
        assertTrue(raise.coolDownStart() == time);
        vm.warp(time + 2 hours);
        vm.prank(owner);
        raise.setCurrencyAndTokenPrice(paymentToken, 700);
        assertTrue(raise.coolDownStart() == time + 2 hours);
        vm.warp(time + raise.delay() + 1 hours);
        vm.prank(owner);
        vm.expectRevert(
            "There needs to be at minimum one day to change parameters"
        );
        raise.unpause(); // must fail because of the parameter update
    }

    /*
        try to unpause after setCurrencyAndTokenPrice
    */
    function testUnpauseAfterSetCurrencyAndTokenPrice() public {
        uint256 time = block.timestamp;
        vm.warp(time);
        vm.prank(owner);
        raise.pause();
        assertTrue(raise.paused());
        assertTrue(raise.coolDownStart() == time);
        vm.warp(time + 2 hours);
        vm.prank(owner);
        raise.setCurrencyAndTokenPrice(paymentToken, 700);
        assertTrue(raise.coolDownStart() == time + 2 hours);
        vm.warp(time + raise.delay() + 2 hours + 1 seconds);
        vm.prank(owner);
        raise.unpause();
    }
}
