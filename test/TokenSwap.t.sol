// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";

import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/FeeSettings.sol";
import "../contracts/factories/TokenSwapCloneFactory.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/MaliciousPaymentToken.sol";
import "./resources/FakeCrowdinvestingAndToken.sol";
import "./resources/CloneCreators.sol";

contract TokenSwapTest is Test {
    event ReceiverChanged(address indexed);
    event MinAmountPerTransactionChanged(uint256);
    event TokenPriceAndCurrencyChanged(uint256, IERC20 indexed);
    event TokensBought(address indexed buyer, uint256 tokenAmount, uint256 currencyAmount);
    event TokensSold(address indexed seller, uint256 tokenAmount, uint256 currencyAmount);
    event HolderChanged(address);

    TokenSwapCloneFactory factory;
    TokenSwap tokenSwap;
    AllowList list;
    IFeeSettingsV2 feeSettings;

    address wrongFeeReceiver = address(5);

    TokenProxyFactory tokenCloneFactory;
    Token token;
    FakePaymentToken paymentToken;

    MaliciousPaymentToken maliciousPaymentToken;

    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant buyer = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant seller = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant owner = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant receiver = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant holder = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant paymentTokenProvider = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;
    address public constant trustedForwarder = 0xa109709ecfA91A80626ff3989D68F67F5b1dD12a;

    uint8 public constant paymentTokenDecimals = 6;
    uint256 public constant paymentTokenAmount = 1000 * 10 ** paymentTokenDecimals;
    uint256 public constant tokenAmount = 100 * 10 ** 18; // 100 tokens

    uint256 public constant price = 7 * 10 ** paymentTokenDecimals; // 7 payment tokens per token

    uint256 public constant minAmountPerTransaction = 10 ** 18; // 1 token minimum

    function setUp() public {
        vm.startPrank(paymentTokenProvider);
        // set up currency
        paymentToken = new FakePaymentToken(paymentTokenAmount * 10, paymentTokenDecimals);
        // transfer currency to buyer
        paymentToken.transfer(buyer, paymentTokenAmount);
        assertTrue(paymentToken.balanceOf(buyer) == paymentTokenAmount);
        // transfer currency to holder for sell orders
        paymentToken.transfer(holder, paymentTokenAmount * 2);
        vm.stopPrank();

        list = createAllowList(trustedForwarder, owner);
        vm.prank(owner);
        list.set(address(paymentToken), TRUSTED_CURRENCY);

        Fees memory fees = Fees(100, 100, 100, 100);
        feeSettings = createFeeSettings(
            trustedForwarder,
            address(this),
            fees,
            wrongFeeReceiver,
            admin,
            wrongFeeReceiver
        );

        // create token
        address tokenLogicContract = address(new Token(trustedForwarder));
        tokenCloneFactory = new TokenProxyFactory(tokenLogicContract);
        token = Token(
            tokenCloneFactory.createTokenProxy(0, trustedForwarder, feeSettings, admin, list, 0x0, "TESTTOKEN", "TEST")
        );

        // mint tokens to holder
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();
        vm.prank(admin);
        token.grantRole(roleMintAllower, admin);
        vm.prank(admin);
        token.mint(holder, tokenAmount);

        vm.prank(owner);
        factory = new TokenSwapCloneFactory(address(new TokenSwap(trustedForwarder)));
        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            owner,
            payable(receiver),
            minAmountPerTransaction,
            price,
            paymentToken,
            token,
            holder
        );
        tokenSwap = TokenSwap(factory.createTokenSwapClone(0, trustedForwarder, arguments));

        // give holder's tokens to the tokenSwap contract allowance
        vm.prank(holder);
        token.approve(address(tokenSwap), tokenAmount);

        // give buyer allowance to spend payment token
        vm.prank(buyer);
        paymentToken.approve(address(tokenSwap), paymentTokenAmount);

        // give holder allowance to spend payment token for sell transactions
        vm.prank(holder);
        paymentToken.approve(address(tokenSwap), paymentTokenAmount * 2);
    }

    // Helper function to create a copy of TokenSwapInitializerArguments
    function cloneTokenSwapInitializerArguments(
        TokenSwapInitializerArguments memory original
    ) internal pure returns (TokenSwapInitializerArguments memory) {
        return
            TokenSwapInitializerArguments(
                original.owner,
                original.receiver,
                original.minAmountPerTransaction,
                original.tokenPrice,
                original.currency,
                original.token,
                original.holder
            );
    }

    function testLogicContractCreation() public {
        TokenSwap _logic = new TokenSwap(address(1));

        console.log("address of logic contract: ", address(_logic));

        // try to initialize
        vm.expectRevert("Initializable: contract is already initialized");
        _logic.initialize(
            TokenSwapInitializerArguments(
                address(this),
                payable(receiver),
                minAmountPerTransaction,
                price,
                paymentToken,
                token,
                holder
            )
        );

        // owner and all settings are 0
        assertTrue(_logic.owner() == address(0), "owner is not 0");
        assertTrue(_logic.receiver() == address(0));
        assertTrue(_logic.minAmountPerTransaction() == 0);
        assertTrue(_logic.tokenPrice() == 0);
        assertTrue(address(_logic.currency()) == address(0));
        assertTrue(address(_logic.token()) == address(0));
        assertTrue(_logic.holder() == address(0));
    }

    function testConstructorHappyCase() public {
        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            address(this),
            payable(receiver),
            minAmountPerTransaction,
            price,
            paymentToken,
            token,
            holder
        );
        TokenSwap _tokenSwap = TokenSwap(factory.createTokenSwapClone(0, trustedForwarder, arguments));
        assertTrue(_tokenSwap.owner() == address(this));
        assertTrue(_tokenSwap.receiver() == receiver);
        assertTrue(_tokenSwap.minAmountPerTransaction() == minAmountPerTransaction);
        assertTrue(_tokenSwap.tokenPrice() == price);
        assertTrue(_tokenSwap.currency() == paymentToken);
        assertTrue(_tokenSwap.token() == token);
        assertTrue(_tokenSwap.holder() == holder);
    }

    function testConstructorWithBadArguments() public {
        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            address(this),
            payable(receiver),
            minAmountPerTransaction,
            price,
            paymentToken,
            token,
            holder
        );

        vm.expectRevert("TokenSwapCloneFactory: Unexpected trustedForwarder");
        TokenSwap(factory.createTokenSwapClone(0, address(0), arguments));

        // owner 0
        TokenSwapInitializerArguments memory tempArgs = cloneTokenSwapInitializerArguments(arguments);
        tempArgs.owner = address(0);
        vm.expectRevert("owner can not be zero address");
        factory.createTokenSwapClone(0, trustedForwarder, tempArgs);

        // receiver 0
        tempArgs = cloneTokenSwapInitializerArguments(arguments);
        tempArgs.receiver = address(0);
        vm.expectRevert("receiver can not be zero address");
        factory.createTokenSwapClone(0, trustedForwarder, tempArgs);

        // holder 0
        tempArgs = cloneTokenSwapInitializerArguments(arguments);
        tempArgs.holder = address(0);
        vm.expectRevert("holder can not be zero address");
        factory.createTokenSwapClone(0, trustedForwarder, tempArgs);

        // minAmountPerTransaction 0
        tempArgs = cloneTokenSwapInitializerArguments(arguments);
        tempArgs.minAmountPerTransaction = 0;
        vm.expectRevert("_minAmountPerTransaction needs to be larger than zero");
        factory.createTokenSwapClone(0, trustedForwarder, tempArgs);

        // price 0
        tempArgs = cloneTokenSwapInitializerArguments(arguments);
        tempArgs.tokenPrice = 0;
        vm.expectRevert("_tokenPrice needs to be a non-zero amount");
        factory.createTokenSwapClone(0, trustedForwarder, tempArgs);

        // currency 0
        tempArgs = cloneTokenSwapInitializerArguments(arguments);
        tempArgs.currency = IERC20(address(0));
        vm.expectRevert("currency can not be zero address");
        factory.createTokenSwapClone(0, trustedForwarder, tempArgs);

        // token 0
        tempArgs = cloneTokenSwapInitializerArguments(arguments);
        tempArgs.token = Token(address(0));
        vm.expectRevert("token can not be zero address");
        factory.createTokenSwapClone(0, trustedForwarder, tempArgs);
    }

    /*
    set up with MaliciousPaymentToken which tries to reenter the buy function
    */
    function testReentrancyOnBuy() public {
        uint8 _paymentTokenDecimals = 18;
        uint256 _price = 7 * 10 ** _paymentTokenDecimals;
        uint256 _tokenAmount = 1000 * 10 ** 18;
        uint256 _paymentTokenAmount = 100000 * 10 ** _paymentTokenDecimals;

        list = createAllowList(trustedForwarder, owner);
        Token _token = Token(
            tokenCloneFactory.createTokenProxy(
                0,
                trustedForwarder,
                feeSettings,
                admin,
                list,
                0x0,
                "REENTRANCYTOKEN",
                "TEST"
            )
        );

        // mint tokens to holder
        bytes32 roleMintAllower = _token.MINTALLOWER_ROLE();
        vm.prank(admin);
        _token.grantRole(roleMintAllower, admin);
        vm.prank(admin);
        _token.mint(holder, _tokenAmount);

        vm.prank(paymentTokenProvider);
        maliciousPaymentToken = new MaliciousPaymentToken(_paymentTokenAmount);
        vm.prank(owner);
        list.set(address(maliciousPaymentToken), TRUSTED_CURRENCY);

        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            address(this),
            payable(receiver),
            1,
            _price,
            maliciousPaymentToken,
            _token,
            holder
        );

        TokenSwap _tokenSwap = TokenSwap(factory.createTokenSwapClone(0, trustedForwarder, arguments));

        // give holder's tokens to the tokenSwap contract allowance
        vm.prank(holder);
        _token.approve(address(_tokenSwap), _tokenAmount);

        // mint _paymentToken for buyer
        vm.prank(paymentTokenProvider);
        maliciousPaymentToken.transfer(buyer, _paymentTokenAmount);
        assertTrue(maliciousPaymentToken.balanceOf(buyer) == _paymentTokenAmount);

        // set exploitTarget
        maliciousPaymentToken.setExploitTarget(address(_tokenSwap), 3, _tokenAmount / 200);

        // give tokenSwap contract allowance
        vm.prank(buyer);
        maliciousPaymentToken.approve(address(_tokenSwap), _paymentTokenAmount);

        // run actual test
        assertTrue(maliciousPaymentToken.balanceOf(buyer) == _paymentTokenAmount);
        uint256 buyAmount = _tokenAmount / 100;
        vm.prank(buyer);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        _tokenSwap.buy(buyAmount, type(uint256).max, buyer);
    }

    function testReentrancyOnSell() public {
        uint8 _paymentTokenDecimals = 18;
        uint256 _price = 7 * 10 ** _paymentTokenDecimals;
        uint256 _tokenAmount = 1000 * 10 ** 18;
        uint256 _paymentTokenAmount = 100000 * 10 ** _paymentTokenDecimals;

        list = createAllowList(trustedForwarder, owner);
        Token _token = Token(
            tokenCloneFactory.createTokenProxy(
                0,
                trustedForwarder,
                feeSettings,
                admin,
                list,
                0x0,
                "REENTRANCYTOKEN",
                "TEST"
            )
        );

        // mint tokens to seller
        bytes32 roleMintAllower = _token.MINTALLOWER_ROLE();
        vm.prank(admin);
        _token.grantRole(roleMintAllower, admin);
        vm.prank(admin);
        _token.mint(seller, _tokenAmount);

        vm.prank(paymentTokenProvider);
        maliciousPaymentToken = new MaliciousPaymentToken(_paymentTokenAmount);
        vm.prank(owner);
        list.set(address(maliciousPaymentToken), TRUSTED_CURRENCY);

        // transfer malicious payment token to holder
        vm.prank(paymentTokenProvider);
        maliciousPaymentToken.transfer(holder, _paymentTokenAmount);

        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            address(this),
            payable(receiver),
            1,
            _price,
            maliciousPaymentToken,
            _token,
            holder
        );

        TokenSwap _tokenSwap = TokenSwap(factory.createTokenSwapClone(0, trustedForwarder, arguments));

        // give holder allowance to spend payment token
        vm.prank(holder);
        maliciousPaymentToken.approve(address(_tokenSwap), _paymentTokenAmount);

        // set exploitTarget for sell (which transfers from holder to seller)
        maliciousPaymentToken.setExploitTarget(address(_tokenSwap), 3, _tokenAmount / 200);

        // give tokenSwap contract allowance from seller
        vm.prank(seller);
        _token.approve(address(_tokenSwap), _tokenAmount);

        // run actual test
        uint256 sellAmount = _tokenAmount / 100;
        vm.prank(seller);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        _tokenSwap.sell(sellAmount, 0, seller);
    }

    function testBuyHappyCase(uint256 tokenBuyAmount) public {
        vm.assume(tokenBuyAmount >= tokenSwap.minAmountPerTransaction());
        vm.assume(tokenBuyAmount <= tokenAmount);
        uint256 costInPaymentToken = Math.ceilDiv(tokenBuyAmount * tokenSwap.tokenPrice(), 10 ** 18);
        vm.assume(costInPaymentToken <= paymentToken.balanceOf(buyer));

        uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(buyer);
        uint256 holderTokenBalanceBefore = token.balanceOf(holder);

        FakeCrowdinvesting fakeCrowdinvesting = new FakeCrowdinvesting(address(token));

        vm.prank(buyer);
        vm.expectEmit(true, true, true, true, address(tokenSwap));
        emit TokensBought(buyer, tokenBuyAmount, costInPaymentToken);
        tokenSwap.buy(tokenBuyAmount, type(uint256).max, buyer);

        assertTrue(paymentToken.balanceOf(buyer) == paymentTokenBalanceBefore - costInPaymentToken, "buyer has paid");
        assertTrue(token.balanceOf(buyer) == tokenBuyAmount, "buyer has tokens");
        assertTrue(
            paymentToken.balanceOf(receiver) == costInPaymentToken - fakeCrowdinvesting.fee(costInPaymentToken),
            "receiver has payment tokens"
        );
        assertTrue(
            paymentToken.balanceOf(
                FeeSettings(address(token.feeSettings())).crowdinvestingFeeCollector(address(token))
            ) == fakeCrowdinvesting.fee(costInPaymentToken),
            "fee collector has collected fee in payment tokens"
        );
        assertTrue(token.balanceOf(holder) == holderTokenBalanceBefore - tokenBuyAmount, "holder has sent tokens");
    }

    function testSellHappyCase(uint256 tokenSellAmount) public {
        // First, buyer needs to buy some tokens to be able to sell them
        uint256 initialBuyAmount = tokenAmount / 2;
        vm.prank(buyer);
        tokenSwap.buy(initialBuyAmount, type(uint256).max, buyer);

        vm.assume(tokenSellAmount >= tokenSwap.minAmountPerTransaction());
        vm.assume(tokenSellAmount <= token.balanceOf(buyer));
        uint256 payoutInPaymentToken = (tokenSellAmount * tokenSwap.tokenPrice()) / (10 ** 18);

        uint256 holderPaymentTokenBalanceBefore = paymentToken.balanceOf(holder);
        uint256 buyerTokenBalanceBefore = token.balanceOf(buyer);
        uint256 receiverTokenBalanceBefore = token.balanceOf(receiver);

        FakeCrowdinvesting fakeCrowdinvesting = new FakeCrowdinvesting(address(token));
        uint256 expectedFee = fakeCrowdinvesting.fee(payoutInPaymentToken);
        uint256 expectedPayout = payoutInPaymentToken - expectedFee;

        // seller needs to approve tokenSwap to transfer their tokens
        vm.prank(buyer);
        token.approve(address(tokenSwap), tokenSellAmount);

        vm.prank(buyer);
        vm.expectEmit(true, true, true, true, address(tokenSwap));
        emit TokensSold(buyer, tokenSellAmount, payoutInPaymentToken);
        tokenSwap.sell(tokenSellAmount, 0, buyer);

        assertTrue(token.balanceOf(buyer) == buyerTokenBalanceBefore - tokenSellAmount, "buyer has sold tokens");
        assertTrue(paymentToken.balanceOf(buyer) >= expectedPayout, "buyer has received payment");
        assertTrue(token.balanceOf(receiver) == receiverTokenBalanceBefore + tokenSellAmount, "receiver has tokens");
        assertTrue(
            paymentToken.balanceOf(holder) == holderPaymentTokenBalanceBefore - payoutInPaymentToken,
            "holder has paid"
        );
    }

    function testBuyWithMaxCurrencyAmount(uint256 tokenBuyAmount, uint256 maxCurrencyAmount) public {
        vm.assume(tokenBuyAmount >= tokenSwap.minAmountPerTransaction());
        vm.assume(tokenBuyAmount <= tokenAmount);
        uint256 costInPaymentToken = Math.ceilDiv(tokenBuyAmount * tokenSwap.tokenPrice(), 10 ** 18);
        vm.assume(costInPaymentToken <= paymentToken.balanceOf(buyer));

        uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(buyer);

        FakeCrowdinvesting fakeCrowdinvesting = new FakeCrowdinvesting(address(token));

        if (maxCurrencyAmount >= costInPaymentToken) {
            vm.prank(buyer);
            vm.expectEmit(true, true, true, true, address(tokenSwap));
            emit TokensBought(buyer, tokenBuyAmount, costInPaymentToken);
            tokenSwap.buy(tokenBuyAmount, maxCurrencyAmount, buyer);
            assertTrue(
                paymentTokenBalanceBefore - paymentToken.balanceOf(buyer) <= maxCurrencyAmount,
                "buyer has paid too much!"
            );
            assertTrue(
                paymentToken.balanceOf(buyer) == paymentTokenBalanceBefore - costInPaymentToken,
                "buyer has paid"
            );
            assertTrue(token.balanceOf(buyer) == tokenBuyAmount, "buyer has tokens");
            assertTrue(
                paymentToken.balanceOf(receiver) == costInPaymentToken - fakeCrowdinvesting.fee(costInPaymentToken),
                "receiver has payment tokens"
            );
        } else {
            vm.prank(buyer);
            vm.expectRevert("Purchase more expensive than _maxCurrencyAmount");
            tokenSwap.buy(tokenBuyAmount, maxCurrencyAmount, buyer);
        }
    }

    function testSellWithMinCurrencyAmount(uint256 tokenSellAmount, uint256 minCurrencyAmount) public {
        // First, buyer needs to buy tokens
        vm.prank(buyer);
        tokenSwap.buy(tokenAmount / 2, type(uint256).max, buyer);

        vm.assume(tokenSellAmount >= tokenSwap.minAmountPerTransaction());
        vm.assume(tokenSellAmount <= token.balanceOf(buyer));
        uint256 payoutInPaymentToken = (tokenSellAmount * tokenSwap.tokenPrice()) / (10 ** 18);

        FakeCrowdinvesting fakeCrowdinvesting = new FakeCrowdinvesting(address(token));
        uint256 expectedPayout = payoutInPaymentToken - fakeCrowdinvesting.fee(payoutInPaymentToken);

        vm.prank(buyer);
        token.approve(address(tokenSwap), tokenSellAmount);

        if (minCurrencyAmount <= expectedPayout) {
            vm.prank(buyer);
            tokenSwap.sell(tokenSellAmount, minCurrencyAmount, buyer);
            assertTrue(paymentToken.balanceOf(buyer) >= minCurrencyAmount, "buyer did not receive minimum");
        } else {
            vm.prank(buyer);
            vm.expectRevert("Payout too low");
            tokenSwap.sell(tokenSellAmount, minCurrencyAmount, buyer);
        }
    }

    function testBuyAndTransferToDifferentAddress() public {
        address addressWithFunds = vm.addr(1);
        address addressForTokens = vm.addr(2);

        uint256 availableBalance = paymentToken.balanceOf(buyer);

        vm.prank(buyer);
        paymentToken.transfer(addressWithFunds, availableBalance / 2);

        vm.prank(addressWithFunds);
        paymentToken.approve(address(tokenSwap), paymentTokenAmount);

        // check state before
        assertTrue(paymentToken.balanceOf(addressWithFunds) == availableBalance / 2, "addressWithFunds has no funds");
        assertTrue(paymentToken.balanceOf(addressForTokens) == 0, "addressForTokens has funds");
        assertTrue(token.balanceOf(addressForTokens) == 0, "addressForTokens has tokens before buy");
        assertTrue(token.balanceOf(addressWithFunds) == 0, "addressWithFunds has tokens before buy");

        // execute buy, with addressForTokens as recipient
        vm.prank(addressWithFunds);
        tokenSwap.buy(tokenAmount / 2, type(uint256).max, addressForTokens);

        // check state after
        assertTrue(
            paymentToken.balanceOf(addressWithFunds) <=
                availableBalance / 2 - paymentToken.balanceOf(tokenSwap.receiver()),
            "addressWithFunds has funds after buy"
        );
        assertTrue(paymentToken.balanceOf(addressForTokens) == 0, "addressForTokens has funds after buy");
        assertTrue(
            token.balanceOf(addressForTokens) == tokenAmount / 2,
            "addressForTokens has wrong amount of tokens after buy"
        );
        assertTrue(token.balanceOf(addressWithFunds) == 0, "addressWithFunds has tokens after buy");
    }

    function testSellAndTransferCurrencyToDifferentAddress() public {
        address addressWithTokens = vm.addr(1);
        address addressForCurrency = vm.addr(2);

        // First, buy tokens for addressWithTokens
        uint256 buyAmount = tokenAmount / 2;
        vm.prank(buyer);
        tokenSwap.buy(buyAmount, type(uint256).max, addressWithTokens);

        // check state before sell
        assertTrue(token.balanceOf(addressWithTokens) == buyAmount, "addressWithTokens has no tokens");
        assertTrue(paymentToken.balanceOf(addressForCurrency) == 0, "addressForCurrency has currency before sell");

        // approve tokenSwap to transfer tokens
        vm.prank(addressWithTokens);
        token.approve(address(tokenSwap), buyAmount);

        // execute sell, with addressForCurrency as recipient for currency
        vm.prank(addressWithTokens);
        tokenSwap.sell(buyAmount, 0, addressForCurrency);

        // check state after
        assertTrue(token.balanceOf(addressWithTokens) == 0, "addressWithTokens still has tokens after sell");
        assertTrue(paymentToken.balanceOf(addressForCurrency) > 0, "addressForCurrency did not receive currency");
    }

    function testBuyTooLittle() public {
        uint256 tokenBuyAmount = minAmountPerTransaction / 2;

        vm.prank(buyer);
        vm.expectRevert("Transaction amount needs to be at least minAmount");
        tokenSwap.buy(tokenBuyAmount, type(uint256).max, buyer);
    }

    function testSellTooLittle() public {
        // First buy some tokens
        vm.prank(buyer);
        tokenSwap.buy(tokenAmount / 2, type(uint256).max, buyer);

        uint256 tokenSellAmount = minAmountPerTransaction / 2;

        vm.prank(buyer);
        token.approve(address(tokenSwap), tokenSellAmount);

        vm.prank(buyer);
        vm.expectRevert("Transaction amount needs to be at least minAmount");
        tokenSwap.sell(tokenSellAmount, 0, buyer);
    }

    function testBuyWhilePaused() public {
        vm.prank(owner);
        tokenSwap.pause();
        vm.prank(buyer);
        vm.expectRevert("Pausable: paused");
        tokenSwap.buy(minAmountPerTransaction, type(uint256).max, buyer);
    }

    function testSellWhilePaused() public {
        // First buy some tokens
        vm.prank(buyer);
        tokenSwap.buy(tokenAmount / 2, type(uint256).max, buyer);

        vm.prank(owner);
        tokenSwap.pause();

        vm.prank(buyer);
        token.approve(address(tokenSwap), minAmountPerTransaction);

        vm.prank(buyer);
        vm.expectRevert("Pausable: paused");
        tokenSwap.sell(minAmountPerTransaction, 0, buyer);
    }

    function testUpdateReceiverNotPaused() public {
        vm.prank(owner);
        vm.expectRevert("Pausable: not paused");
        tokenSwap.setReceiver(payable(address(buyer)));
    }

    function testUpdateReceiverPaused() public {
        assertTrue(tokenSwap.receiver() == receiver);
        vm.prank(owner);
        tokenSwap.pause();
        vm.prank(owner);
        vm.expectEmit(true, true, true, true, address(tokenSwap));
        emit ReceiverChanged(address(buyer));
        tokenSwap.setReceiver(address(buyer));
        assertTrue(tokenSwap.receiver() == address(buyer));

        vm.prank(owner);
        vm.expectRevert("receiver can not be zero address");
        tokenSwap.setReceiver(address(0));
    }

    function testUpdateMinAmountPerTransactionNotPaused() public {
        vm.prank(owner);
        vm.expectRevert("Pausable: not paused");
        tokenSwap.setMinAmountPerTransaction(100);
    }

    function testUpdateMinAmountPerTransactionPaused(uint256 newMinAmountPerTransaction) public {
        vm.assume(newMinAmountPerTransaction > 0);
        assertTrue(tokenSwap.minAmountPerTransaction() == minAmountPerTransaction);
        vm.prank(owner);
        tokenSwap.pause();
        vm.prank(owner);
        vm.expectEmit(true, true, true, true, address(tokenSwap));
        emit MinAmountPerTransactionChanged(newMinAmountPerTransaction);
        tokenSwap.setMinAmountPerTransaction(newMinAmountPerTransaction);
        assertTrue(tokenSwap.minAmountPerTransaction() == newMinAmountPerTransaction);

        vm.expectRevert("_minAmountPerTransaction needs to be larger than zero");
        vm.prank(owner);
        tokenSwap.setMinAmountPerTransaction(0);
    }

    function testUpdateCurrencyAndPriceNotPaused() public {
        FakePaymentToken newPaymentToken = new FakePaymentToken(700, 3);
        vm.prank(owner);
        vm.expectRevert("Pausable: not paused");
        tokenSwap.setCurrencyAndTokenPrice(newPaymentToken, 100);
    }

    function testUpdateCurrencyAndPricePaused(uint256 newPrice) public {
        vm.assume(newPrice > 0);
        assertTrue(tokenSwap.tokenPrice() == price);
        assertTrue(tokenSwap.currency() == paymentToken);

        FakePaymentToken newPaymentToken = new FakePaymentToken(700, 3);
        vm.startPrank(owner);
        list.set(address(newPaymentToken), TRUSTED_CURRENCY);

        tokenSwap.pause();
        vm.expectEmit(true, true, true, true, address(tokenSwap));
        emit TokenPriceAndCurrencyChanged(newPrice, newPaymentToken);
        tokenSwap.setCurrencyAndTokenPrice(newPaymentToken, newPrice);
        vm.stopPrank();

        assertTrue(tokenSwap.tokenPrice() == newPrice);
        assertTrue(tokenSwap.currency() == newPaymentToken);

        vm.prank(owner);
        vm.expectRevert("_tokenPrice needs to be a non-zero amount");
        tokenSwap.setCurrencyAndTokenPrice(paymentToken, 0);
    }

    function testUpdateHolderNotPaused() public {
        vm.prank(owner);
        vm.expectRevert("Pausable: not paused");
        tokenSwap.setHolder(address(buyer));
    }

    function testUpdateHolderPaused(address newHolder) public {
        vm.assume(newHolder != address(0));
        assertTrue(tokenSwap.holder() == holder);
        vm.prank(owner);
        tokenSwap.pause();
        vm.prank(owner);
        vm.expectEmit(true, true, true, true, address(tokenSwap));
        emit HolderChanged(newHolder);
        tokenSwap.setHolder(newHolder);
        assertTrue(tokenSwap.holder() == newHolder);

        vm.prank(owner);
        vm.expectRevert("holder can not be zero address");
        tokenSwap.setHolder(address(0));
    }

    function testPauseUnpause() public {
        assertFalse(tokenSwap.paused());
        vm.prank(owner);
        tokenSwap.pause();
        assertTrue(tokenSwap.paused());
        vm.prank(owner);
        tokenSwap.unpause();
        assertFalse(tokenSwap.paused());
    }

    function testOnlyOwnerCanPause(address rando) public {
        vm.assume(rando != owner);
        vm.prank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        tokenSwap.pause();
    }

    function testOnlyOwnerCanUnpause(address rando) public {
        vm.assume(rando != owner);
        vm.prank(owner);
        tokenSwap.pause();
        vm.prank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        tokenSwap.unpause();
    }

    function testSettingInvalidCurrencyReverts(address someCurrency, uint256 currencyAttributes) public {
        vm.assume(someCurrency != address(0));
        vm.assume(currencyAttributes != TRUSTED_CURRENCY);
        vm.prank(owner);
        list.set(someCurrency, currencyAttributes);

        vm.startPrank(owner);
        tokenSwap.pause();
        vm.expectRevert("currency needs to be on the allowlist with TRUSTED_CURRENCY attribute");
        tokenSwap.setCurrencyAndTokenPrice(IERC20(someCurrency), 1);

        // check the setting works when the currency is on the allowlist with TRUSTED_CURRENCY attribute
        list.set(someCurrency, TRUSTED_CURRENCY);
        tokenSwap.setCurrencyAndTokenPrice(IERC20(someCurrency), 1);
    }

    function testBuyRoundsUp(uint256 _tokenBuyAmount, uint256 _price) public {
        vm.assume(_tokenBuyAmount > 0);
        vm.assume(_price > 0);
        vm.assume(UINT256_MAX / _price > _tokenBuyAmount);
        vm.assume(_tokenBuyAmount <= tokenAmount);

        uint256 tokenDecimals = token.decimals();
        uint minCurrencyAmount = (_tokenBuyAmount * _price) / 10 ** tokenDecimals;
        uint maxCurrencyAmount = minCurrencyAmount + 1;

        // set up new payment token
        vm.prank(paymentTokenProvider);
        FakePaymentToken newPaymentToken = new FakePaymentToken(maxCurrencyAmount * 10, paymentTokenDecimals);
        vm.prank(paymentTokenProvider);
        newPaymentToken.transfer(buyer, maxCurrencyAmount * 2);

        vm.prank(owner);
        list.set(address(newPaymentToken), TRUSTED_CURRENCY);

        // update tokenSwap
        vm.prank(owner);
        tokenSwap.pause();
        vm.prank(owner);
        tokenSwap.setCurrencyAndTokenPrice(newPaymentToken, _price);
        vm.prank(owner);
        tokenSwap.setMinAmountPerTransaction(1);
        vm.prank(owner);
        tokenSwap.unpause();

        // set fees to 0
        Fees memory fees = Fees(0, 0, 0, 0);
        FeeSettings(address(token.feeSettings())).planFeeChange(fees);
        FeeSettings(address(token.feeSettings())).executeFeeChange();

        // approve
        vm.prank(buyer);
        newPaymentToken.approve(address(tokenSwap), maxCurrencyAmount * 2);

        uint256 paymentTokenBalanceBefore = newPaymentToken.balanceOf(buyer);

        vm.prank(buyer);
        tokenSwap.buy(_tokenBuyAmount, type(uint256).max, buyer);

        // check that the buyer got the correct amount of tokens
        assertTrue(token.balanceOf(buyer) == _tokenBuyAmount, "buyer got wrong amount of tokens");
        // check rounding
        uint256 realCostInPaymentToken = paymentTokenBalanceBefore - newPaymentToken.balanceOf(buyer);
        assertTrue(realCostInPaymentToken <= maxCurrencyAmount, "cost too high");
        assertTrue(realCostInPaymentToken >= minCurrencyAmount, "cost too low");
        assertTrue(realCostInPaymentToken - minCurrencyAmount <= 1, "more than 1 currency bit was rounded!");
    }

    function testSellRoundsDown(uint256 _tokenSellAmount, uint256 _price) public {
        vm.assume(_tokenSellAmount > 0);
        vm.assume(_price > 0);
        vm.assume(UINT256_MAX / _price > _tokenSellAmount);
        vm.assume(_tokenSellAmount <= tokenAmount / 2);

        // First buy tokens
        vm.prank(buyer);
        tokenSwap.buy(tokenAmount / 2, type(uint256).max, buyer);

        uint256 tokenDecimals = token.decimals();
        uint expectedPayout = (_tokenSellAmount * _price) / 10 ** tokenDecimals;

        // set up new payment token for holder
        vm.prank(paymentTokenProvider);
        FakePaymentToken newPaymentToken = new FakePaymentToken(expectedPayout * 10, paymentTokenDecimals);
        vm.prank(paymentTokenProvider);
        newPaymentToken.transfer(holder, expectedPayout * 5);

        vm.prank(owner);
        list.set(address(newPaymentToken), TRUSTED_CURRENCY);

        // update tokenSwap
        vm.prank(owner);
        tokenSwap.pause();
        vm.prank(owner);
        tokenSwap.setCurrencyAndTokenPrice(newPaymentToken, _price);
        vm.prank(owner);
        tokenSwap.setMinAmountPerTransaction(1);
        vm.prank(owner);
        tokenSwap.unpause();

        // set fees to 0
        Fees memory fees = Fees(0, 0, 0, 0);
        FeeSettings(address(token.feeSettings())).planFeeChange(fees);
        FeeSettings(address(token.feeSettings())).executeFeeChange();

        // approve holder to spend new payment token
        vm.prank(holder);
        newPaymentToken.approve(address(tokenSwap), expectedPayout * 5);

        // approve tokenSwap to transfer seller's tokens
        vm.prank(buyer);
        token.approve(address(tokenSwap), _tokenSellAmount);

        uint256 holderPaymentTokenBalanceBefore = newPaymentToken.balanceOf(holder);
        uint256 buyerPaymentTokenBalanceBefore = newPaymentToken.balanceOf(buyer);

        vm.prank(buyer);
        tokenSwap.sell(_tokenSellAmount, 0, buyer);

        // check that the seller received payment (rounded down)
        uint256 actualPayout = newPaymentToken.balanceOf(buyer) - buyerPaymentTokenBalanceBefore;
        assertTrue(actualPayout == expectedPayout, "seller got wrong payout");
        assertTrue(
            holderPaymentTokenBalanceBefore - newPaymentToken.balanceOf(holder) == expectedPayout,
            "holder paid wrong amount"
        );
    }

    function testTransferOwnership(address newOwner) public {
        vm.prank(owner);
        tokenSwap.transferOwnership(newOwner);
        assertTrue(tokenSwap.owner() == owner);

        vm.prank(newOwner);
        tokenSwap.acceptOwnership();
        assertTrue(tokenSwap.owner() == newOwner);
    }

    function testBuyWithInsufficientHolderTokens() public {
        // Give buyer more payment tokens to afford the purchase
        uint256 costForDoubleAmount = Math.ceilDiv(tokenAmount * 2 * tokenSwap.tokenPrice(), 10 ** 18);
        vm.prank(paymentTokenProvider);
        paymentToken.transfer(buyer, costForDoubleAmount);

        // Buyer approves payment tokens
        vm.prank(buyer);
        paymentToken.approve(address(tokenSwap), costForDoubleAmount);

        // Approve tokens even though holder doesn't have enough
        vm.prank(holder);
        token.approve(address(tokenSwap), tokenAmount * 2);

        // Try to buy more tokens than holder has
        vm.prank(buyer);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        tokenSwap.buy(tokenAmount * 2, type(uint256).max, buyer);
    }

    function testSellWithInsufficientHolderCurrency() public {
        // First buy all available tokens
        vm.prank(buyer);
        tokenSwap.buy(tokenAmount, type(uint256).max, buyer);

        // Remove holder's payment tokens
        uint256 holderBalance = paymentToken.balanceOf(holder);
        vm.prank(holder);
        paymentToken.transfer(paymentTokenProvider, holderBalance);

        // Try to sell tokens back
        vm.prank(buyer);
        token.approve(address(tokenSwap), minAmountPerTransaction);

        vm.prank(buyer);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        tokenSwap.sell(minAmountPerTransaction, 0, buyer);
    }

    function testBuyWithoutApproval() public {
        address newBuyer = vm.addr(5);

        // Give new buyer some payment tokens
        vm.prank(paymentTokenProvider);
        paymentToken.transfer(newBuyer, paymentTokenAmount);

        // Try to buy without approval
        vm.prank(newBuyer);
        vm.expectRevert("ERC20: insufficient allowance");
        tokenSwap.buy(minAmountPerTransaction, type(uint256).max, newBuyer);
    }

    function testSellWithoutApproval() public {
        address newSeller = vm.addr(6);

        // First, buy tokens for new seller
        vm.prank(buyer);
        tokenSwap.buy(minAmountPerTransaction, type(uint256).max, newSeller);

        // Try to sell without approval
        vm.prank(newSeller);
        vm.expectRevert("ERC20: insufficient allowance");
        tokenSwap.sell(minAmountPerTransaction, 0, newSeller);
    }

    function testComplexBuyAndSellScenario() public {
        // Scenario: Multiple buys and sells
        address trader1 = vm.addr(10);
        address trader2 = vm.addr(11);

        // Give traders payment tokens
        vm.prank(paymentTokenProvider);
        paymentToken.transfer(trader1, paymentTokenAmount);
        vm.prank(paymentTokenProvider);
        paymentToken.transfer(trader2, paymentTokenAmount);

        // Trader1 buys
        vm.prank(trader1);
        paymentToken.approve(address(tokenSwap), paymentTokenAmount);
        vm.prank(trader1);
        tokenSwap.buy(10 * 10 ** 18, type(uint256).max, trader1);

        uint256 trader1Tokens = token.balanceOf(trader1);
        assertTrue(trader1Tokens == 10 * 10 ** 18, "trader1 should have 10 tokens");

        // Trader2 buys
        vm.prank(trader2);
        paymentToken.approve(address(tokenSwap), paymentTokenAmount);
        vm.prank(trader2);
        tokenSwap.buy(15 * 10 ** 18, type(uint256).max, trader2);

        uint256 trader2Tokens = token.balanceOf(trader2);
        assertTrue(trader2Tokens == 15 * 10 ** 18, "trader2 should have 15 tokens");

        // Trader1 sells half
        vm.prank(trader1);
        token.approve(address(tokenSwap), trader1Tokens / 2);
        vm.prank(trader1);
        tokenSwap.sell(trader1Tokens / 2, 0, trader1);

        assertTrue(token.balanceOf(trader1) == trader1Tokens / 2, "trader1 should have 5 tokens left");
        assertTrue(paymentToken.balanceOf(trader1) > 0, "trader1 should have received payment");

        // Trader2 sells all
        vm.prank(trader2);
        token.approve(address(tokenSwap), trader2Tokens);
        vm.prank(trader2);
        tokenSwap.sell(trader2Tokens, 0, trader2);

        assertTrue(token.balanceOf(trader2) == 0, "trader2 should have no tokens left");
        assertTrue(paymentToken.balanceOf(trader2) > 0, "trader2 should have received payment");
    }
}
