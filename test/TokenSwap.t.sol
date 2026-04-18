// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";

import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/FeeSettings.sol";
import "../contracts/common/IFeeSettings.sol";
import "../contracts/factories/TokenSwapCloneFactory.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/MaliciousPaymentToken.sol";
import "./resources/CloneCreators.sol";

/**
 * @notice A minimal fee settings that supports IFeeSettingsV2 but NOT IFeeSettingsV3.
 *         Used to exercise the V2 fallback path in TokenSwapBase._getFeeAndFeeReceiver().
 */
contract V2OnlyFeeSettings {
    address public immutable collector;

    uint256 public constant SOME_RANDOM_FIXED_FEE = 62648;

    constructor(address _collector) {
        collector = _collector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        if (interfaceId == 0x01ffc9a7) return true; // ERC165
        if (interfaceId == 0xffffffff) return false; // ERC165 invalid
        if (interfaceId == type(IFeeSettingsV2).interfaceId) return true;
        return false; // does NOT support IFeeSettingsV3
    }

    function tokenFee(uint256, address) external pure returns (uint256) {
        return SOME_RANDOM_FIXED_FEE;
    }

    function tokenFeeCollector(address) external view returns (address) {
        return collector;
    }

    function crowdinvestingFee(uint256, address) external pure returns (uint256) {
        return SOME_RANDOM_FIXED_FEE;
    }

    function crowdinvestingFeeCollector(address) external view returns (address) {
        return collector;
    }

    function privateOfferFee(uint256, address) external pure returns (uint256) {
        return SOME_RANDOM_FIXED_FEE;
    }

    function privateOfferFeeCollector(address) external view returns (address) {
        return collector;
    }

    function owner() external pure returns (address) {
        return address(0);
    }
}

contract TokenSwapTest is Test {
    event ReceiverChanged(address indexed);
    event MinAmountPerTransactionChanged(uint256);
    event TokenPriceChanged(uint256);
    event TokensBought(address indexed BUYER, uint256 TOKEN_AMOUNT, uint256 currencyAmount);
    event TokensSold(address indexed SELLER, uint256 TOKEN_AMOUNT, uint256 currencyAmount);

    TokenSwapCloneFactory factory;
    TokenSwap tokenSwap;
    AllowList list;
    IFeeSettingsV2 feeSettings;

    address wrongFeeReceiver = address(5);

    TokenProxyFactory tokenCloneFactory;
    Token token;
    FakePaymentToken paymentToken;

    MaliciousPaymentToken maliciousPaymentToken;

    address public constant ADMIN = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant BUYER = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant SELLER = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant OWNER = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant RECEIVER = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant HOLDER = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant PAYMENT_TOKEN_PROVIDER = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;
    address public constant TRUSTED_FORWARDER = 0xa109709ecfA91A80626ff3989D68F67F5b1dD12a;

    uint8 public constant PAYMENT_TOKEN_DECIMALS = 6;
    uint256 public constant PAYMENT_TOKEN_AMOUNT = 1000 * 10 ** PAYMENT_TOKEN_DECIMALS;
    uint256 public constant TOKEN_AMOUNT = 100 * 10 ** 18; // 100 tokens

    uint256 public constant PRICE = 7 * 10 ** PAYMENT_TOKEN_DECIMALS; // 7 payment tokens per token

    function setUp() public {
        vm.startPrank(PAYMENT_TOKEN_PROVIDER);
        // set up currency
        paymentToken = new FakePaymentToken(PAYMENT_TOKEN_AMOUNT * 10, PAYMENT_TOKEN_DECIMALS);
        // transfer currency to BUYER
        paymentToken.transfer(BUYER, PAYMENT_TOKEN_AMOUNT);
        assertTrue(paymentToken.balanceOf(BUYER) == PAYMENT_TOKEN_AMOUNT);
        // transfer currency to HOLDER for sell orders
        paymentToken.transfer(HOLDER, PAYMENT_TOKEN_AMOUNT * 2);
        vm.stopPrank();

        list = createAllowList(TRUSTED_FORWARDER, OWNER);
        vm.prank(OWNER);
        list.set(address(paymentToken), TRUSTED_CURRENCY);

        feeSettings = createFeeSettings(
            TRUSTED_FORWARDER,
            address(this),
            buildFeeTypes(100, 100, 100, wrongFeeReceiver, ADMIN, wrongFeeReceiver)
        );

        // create token
        address tokenLogicContract = address(new Token(TRUSTED_FORWARDER));
        tokenCloneFactory = new TokenProxyFactory(tokenLogicContract);
        token = Token(
            tokenCloneFactory.createTokenProxy(0, TRUSTED_FORWARDER, feeSettings, ADMIN, list, 0x0, "TESTTOKEN", "TEST")
        );

        // mint tokens to HOLDER
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();
        vm.prank(ADMIN);
        token.grantRole(roleMintAllower, ADMIN);
        vm.prank(ADMIN);
        token.mint(HOLDER, TOKEN_AMOUNT);

        vm.prank(OWNER);
        factory = new TokenSwapCloneFactory(address(new TokenSwap(TRUSTED_FORWARDER)));
        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            OWNER,
            payable(RECEIVER),
            HOLDER,
            PRICE,
            paymentToken,
            token
        );
        tokenSwap = TokenSwap(factory.createTokenSwapClone(0, TRUSTED_FORWARDER, arguments));

        // grant tokenSwap an allowance for HOLDER's tokens
        vm.prank(HOLDER);
        token.approve(address(tokenSwap), TOKEN_AMOUNT);

        // grant tokenSwap an allowance to spend BUYER's payment tokens
        vm.prank(BUYER);
        paymentToken.approve(address(tokenSwap), PAYMENT_TOKEN_AMOUNT);

        // grant tokenSwap an allowance to spend HOLDER's payment tokens for sell transactions
        vm.prank(HOLDER);
        paymentToken.approve(address(tokenSwap), PAYMENT_TOKEN_AMOUNT * 2);
    }

    // Helper function to create a copy of TokenSwapInitializerArguments
    function cloneTokenSwapInitializerArguments(
        TokenSwapInitializerArguments memory original
    ) internal pure returns (TokenSwapInitializerArguments memory) {
        return
            TokenSwapInitializerArguments(
                original.owner,
                original.receiver,
                original.holder,
                original.tokenPrice,
                original.currency,
                original.token
            );
    }

    function testLogicContractCreation() public {
        TokenSwap _logic = new TokenSwap(address(1));

        console.log("address of logic contract: ", address(_logic));

        // try to initialize
        vm.expectRevert("Initializable: contract is already initialized");
        _logic.initialize(
            TokenSwapInitializerArguments(address(this), payable(RECEIVER), HOLDER, PRICE, paymentToken, token)
        );

        // OWNER and all settings are 0
        assertTrue(_logic.owner() == address(0), "OWNER is not 0");
        assertTrue(_logic.receiver() == address(0));
        assertTrue(_logic.tokenPrice() == 0);
        assertTrue(address(_logic.currency()) == address(0));
        assertTrue(address(_logic.token()) == address(0));
        assertTrue(_logic.holder() == address(0));
    }

    function testConstructorHappyCase() public {
        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            address(this),
            payable(RECEIVER),
            HOLDER,
            PRICE,
            paymentToken,
            token
        );
        TokenSwap _tokenSwap = TokenSwap(factory.createTokenSwapClone(0, TRUSTED_FORWARDER, arguments));
        assertTrue(_tokenSwap.owner() == address(this));
        assertTrue(_tokenSwap.receiver() == RECEIVER);
        assertTrue(_tokenSwap.tokenPrice() == PRICE);
        assertTrue(_tokenSwap.currency() == paymentToken);
        assertTrue(_tokenSwap.token() == token);
        assertTrue(_tokenSwap.holder() == HOLDER);

        // try to initialize again
        vm.expectRevert("Initializable: contract is already initialized");
        _tokenSwap.initialize(arguments);
    }

    function testConstructorWithBadArguments() public {
        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            address(this),
            payable(RECEIVER),
            HOLDER,
            PRICE,
            paymentToken,
            token
        );

        vm.expectRevert(Factory.UnexpectedTrustedForwarder.selector);
        TokenSwap(factory.createTokenSwapClone(0, address(0), arguments));

        // OWNER 0
        TokenSwapInitializerArguments memory tempArgs = cloneTokenSwapInitializerArguments(arguments);
        tempArgs.owner = address(0);
        vm.expectRevert(ZeroOwnerAddress.selector);
        factory.createTokenSwapClone(0, TRUSTED_FORWARDER, tempArgs);

        // RECEIVER 0
        tempArgs = cloneTokenSwapInitializerArguments(arguments);
        tempArgs.receiver = address(0);
        vm.expectRevert(ZeroReceiverAddress.selector);
        factory.createTokenSwapClone(0, TRUSTED_FORWARDER, tempArgs);

        // HOLDER 0
        tempArgs = cloneTokenSwapInitializerArguments(arguments);
        tempArgs.holder = address(0);
        vm.expectRevert(TokenSwap.ZeroHolderAddress.selector);
        factory.createTokenSwapClone(0, TRUSTED_FORWARDER, tempArgs);

        // PRICE 0
        tempArgs = cloneTokenSwapInitializerArguments(arguments);
        tempArgs.tokenPrice = 0;
        vm.expectRevert(ZeroPrice.selector);
        factory.createTokenSwapClone(0, TRUSTED_FORWARDER, tempArgs);

        // currency 0
        tempArgs = cloneTokenSwapInitializerArguments(arguments);
        tempArgs.currency = IERC20(address(0));
        vm.expectRevert(ZeroCurrencyAddress.selector);
        factory.createTokenSwapClone(0, TRUSTED_FORWARDER, tempArgs);

        // token 0
        tempArgs = cloneTokenSwapInitializerArguments(arguments);
        tempArgs.token = Token(address(0));
        vm.expectRevert(ZeroTokenAddress.selector);
        factory.createTokenSwapClone(0, TRUSTED_FORWARDER, tempArgs);
    }

    /*
    set up with MaliciousPaymentToken which tries to reenter the buy function
    */
    function testReentrancyOnBuy() public {
        uint8 _paymentTokenDecimals = 18;
        uint256 _price = 7 * 10 ** _paymentTokenDecimals;
        uint256 _tokenAmount = 1000 * 10 ** 18;
        uint256 _paymentTokenAmount = 100000 * 10 ** _paymentTokenDecimals;

        list = createAllowList(TRUSTED_FORWARDER, OWNER);
        Token _token = Token(
            tokenCloneFactory.createTokenProxy(
                0,
                TRUSTED_FORWARDER,
                feeSettings,
                ADMIN,
                list,
                0x0,
                "REENTRANCYTOKEN",
                "TEST"
            )
        );

        // mint tokens to HOLDER
        bytes32 roleMintAllower = _token.MINTALLOWER_ROLE();
        vm.prank(ADMIN);
        _token.grantRole(roleMintAllower, ADMIN);
        vm.prank(ADMIN);
        _token.mint(HOLDER, _tokenAmount);

        vm.prank(PAYMENT_TOKEN_PROVIDER);
        maliciousPaymentToken = new MaliciousPaymentToken(_paymentTokenAmount);
        vm.prank(OWNER);
        list.set(address(maliciousPaymentToken), TRUSTED_CURRENCY);

        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            address(this),
            payable(RECEIVER),
            HOLDER,
            _price,
            maliciousPaymentToken,
            _token
        );

        TokenSwap _tokenSwap = TokenSwap(factory.createTokenSwapClone(0, TRUSTED_FORWARDER, arguments));

        // grant tokenSwap an allowance for HOLDER's tokens
        vm.prank(HOLDER);
        _token.approve(address(_tokenSwap), _tokenAmount);

        // mint _paymentToken for BUYER
        vm.prank(PAYMENT_TOKEN_PROVIDER);
        maliciousPaymentToken.transfer(BUYER, _paymentTokenAmount);
        assertTrue(maliciousPaymentToken.balanceOf(BUYER) == _paymentTokenAmount);

        // set exploitTarget
        maliciousPaymentToken.setExploitTarget(address(_tokenSwap), 3, _tokenAmount / 200);

        // grant tokenSwap an allowance to spend BUYER's payment tokens
        vm.prank(BUYER);
        maliciousPaymentToken.approve(address(_tokenSwap), _paymentTokenAmount);

        // run actual test
        assertTrue(maliciousPaymentToken.balanceOf(BUYER) == _paymentTokenAmount);
        uint256 buyAmount = _tokenAmount / 100;
        vm.prank(BUYER);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        _tokenSwap.buy(buyAmount, type(uint256).max, BUYER);
    }

    function testReentrancyOnSell() public {
        uint8 _paymentTokenDecimals = 18;
        uint256 _price = 7 * 10 ** _paymentTokenDecimals;
        uint256 _tokenAmount = 1000 * 10 ** 18;
        uint256 _paymentTokenAmount = 100000 * 10 ** _paymentTokenDecimals;

        list = createAllowList(TRUSTED_FORWARDER, OWNER);
        Token _token = Token(
            tokenCloneFactory.createTokenProxy(
                0,
                TRUSTED_FORWARDER,
                feeSettings,
                ADMIN,
                list,
                0x0,
                "REENTRANCYTOKEN",
                "TEST"
            )
        );

        // mint tokens to SELLER
        bytes32 roleMintAllower = _token.MINTALLOWER_ROLE();
        vm.prank(ADMIN);
        _token.grantRole(roleMintAllower, ADMIN);
        vm.prank(ADMIN);
        _token.mint(SELLER, _tokenAmount);

        vm.prank(PAYMENT_TOKEN_PROVIDER);
        maliciousPaymentToken = new MaliciousPaymentToken(_paymentTokenAmount);
        vm.prank(OWNER);
        list.set(address(maliciousPaymentToken), TRUSTED_CURRENCY);

        // transfer malicious payment token to HOLDER
        vm.prank(PAYMENT_TOKEN_PROVIDER);
        maliciousPaymentToken.transfer(HOLDER, _paymentTokenAmount);

        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            address(this),
            payable(RECEIVER),
            HOLDER,
            _price,
            maliciousPaymentToken,
            _token
        );

        TokenSwap _tokenSwap = TokenSwap(factory.createTokenSwapClone(0, TRUSTED_FORWARDER, arguments));

        // grant tokenSwap an allowance to spend HOLDER's payment tokens
        vm.prank(HOLDER);
        maliciousPaymentToken.approve(address(_tokenSwap), _paymentTokenAmount);

        // set exploitTarget for sell (which transfers from HOLDER to SELLER)
        maliciousPaymentToken.setExploitTarget(address(_tokenSwap), 3, _tokenAmount / 200);

        // grant tokenSwap an allowance for SELLER's tokens
        vm.prank(SELLER);
        _token.approve(address(_tokenSwap), _tokenAmount);

        // run actual test
        uint256 sellAmount = _tokenAmount / 100;
        vm.prank(SELLER);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        _tokenSwap.sell(sellAmount, 0, SELLER);
    }

    function testBuyHappyCase(uint256 tokenBuyAmount) public {
        vm.assume(tokenBuyAmount >= 10 ** 18);
        vm.assume(tokenBuyAmount <= TOKEN_AMOUNT);
        uint256 costInPaymentToken = Math.ceilDiv(tokenBuyAmount * tokenSwap.tokenPrice(), 10 ** 18);
        vm.assume(costInPaymentToken <= paymentToken.balanceOf(BUYER));

        uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(BUYER);
        uint256 holderTokenBalanceBefore = token.balanceOf(HOLDER);

        uint256 expectedFee = token.feeSettings().privateOfferFee(costInPaymentToken, address(token));

        vm.prank(BUYER);
        vm.expectEmit(true, true, true, true, address(tokenSwap));
        emit TokensBought(BUYER, tokenBuyAmount, costInPaymentToken);
        tokenSwap.buy(tokenBuyAmount, type(uint256).max, BUYER);

        assertTrue(
            paymentToken.balanceOf(BUYER) == paymentTokenBalanceBefore - costInPaymentToken,
            "BUYER payment token balance should decrease by costInPaymentToken"
        );
        assertTrue(token.balanceOf(BUYER) == tokenBuyAmount, "BUYER token balance should equal tokenBuyAmount");
        assertTrue(
            paymentToken.balanceOf(RECEIVER) == costInPaymentToken - expectedFee,
            "RECEIVER payment token balance should equal costInPaymentToken minus expectedFee"
        );
        assertTrue(
            paymentToken.balanceOf(token.feeSettings().privateOfferFeeCollector(address(token))) == expectedFee,
            "fee collector payment token balance should equal expectedFee"
        );
        assertTrue(
            token.balanceOf(HOLDER) == holderTokenBalanceBefore - tokenBuyAmount,
            "HOLDER token balance should decrease by tokenBuyAmount"
        );
    }

    /**
     * this is not an expected use case, but it should still work with the proper setup
     */
    function testBuyAndSellHappyCase(uint256 tokenSellAmount, uint256 tokenBuyAmount) public {
        vm.assume(tokenSellAmount >= 10 ** 18);
        vm.assume(tokenSellAmount <= UINT256_MAX / 10 ** 20); // to avoid overflow during calculations
        vm.assume(tokenBuyAmount >= 10 ** 18);
        vm.assume(tokenBuyAmount <= tokenSellAmount);

        // Mint tokens to SELLER for the sell transaction
        address seller2 = vm.addr(20);
        console.log("seller2 :", seller2);
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();
        vm.prank(ADMIN);
        token.grantRole(roleMintAllower, ADMIN);
        vm.prank(ADMIN);
        token.mint(seller2, tokenSellAmount);

        // Change RECEIVER to HOLDER so HOLDER receives tokens when someone sells
        vm.prank(OWNER);
        tokenSwap.pause();
        vm.prank(OWNER);
        tokenSwap.setReceiver(HOLDER);
        vm.prank(OWNER);
        tokenSwap.unpause();

        // Step 1: Seller sells tokens to HOLDER
        // Seller gives tokens, HOLDER (as RECEIVER) receives tokens, HOLDER (as currency provider) pays currency
        uint256 sellPayoutInPaymentToken = (tokenSellAmount * tokenSwap.tokenPrice()) / (10 ** 18);
        uint256 sellExpectedFee = token.feeSettings().privateOfferFee(sellPayoutInPaymentToken, address(token));
        uint256 sellExpectedPayout = sellPayoutInPaymentToken - sellExpectedFee;

        // Give HOLDER enough payment tokens to pay the SELLER
        vm.prank(PAYMENT_TOKEN_PROVIDER);
        paymentToken.mint(HOLDER, sellPayoutInPaymentToken);

        uint256 holderPaymentTokenBalanceBefore = paymentToken.balanceOf(HOLDER);
        uint256 holderTokenBalanceBefore = token.balanceOf(HOLDER);

        // Grant unlimited allowances
        // Seller2 approves tokenSwap to transfer their tokens
        vm.prank(seller2);
        token.approve(address(tokenSwap), type(uint256).max);

        // Holder approves tokenSwap to spend their payment tokens (for sell transactions)
        vm.prank(HOLDER);
        paymentToken.approve(address(tokenSwap), type(uint256).max);

        console.log("selling now");

        vm.prank(seller2);
        tokenSwap.sell(tokenSellAmount, 0, seller2);

        console.log("sold");

        // Verify sell: HOLDER now has tokens, SELLER has currency
        assertTrue(
            token.balanceOf(HOLDER) == holderTokenBalanceBefore + tokenSellAmount,
            "HOLDER token balance should increase by tokenSellAmount after sell"
        );
        assertTrue(
            paymentToken.balanceOf(HOLDER) == holderPaymentTokenBalanceBefore - sellPayoutInPaymentToken,
            "HOLDER payment token balance should decrease by sellPayoutInPaymentToken after sell"
        );
        assertTrue(
            paymentToken.balanceOf(seller2) == sellExpectedPayout,
            "SELLER should receive expectedPayout in payment tokens"
        );

        // Step 2: Different BUYER buys tokens from HOLDER
        address buyer2 = vm.addr(21);

        // Give buyer2 payment tokens
        uint256 buyCostInPaymentToken = Math.ceilDiv(tokenBuyAmount * tokenSwap.tokenPrice(), 10 ** 18);
        vm.prank(PAYMENT_TOKEN_PROVIDER);
        paymentToken.mint(buyer2, buyCostInPaymentToken);

        // Buyer2 grants unlimited payment token allowance
        vm.prank(buyer2);
        paymentToken.approve(address(tokenSwap), type(uint256).max);

        // Holder grants unlimited token allowance
        vm.prank(HOLDER);
        token.approve(address(tokenSwap), type(uint256).max);

        uint256 buyExpectedFee = token.feeSettings().privateOfferFee(buyCostInPaymentToken, address(token));

        uint256 holderTokenBalanceBeforeBuy = token.balanceOf(HOLDER);
        uint256 holderPaymentTokenBalanceBeforeBuy = paymentToken.balanceOf(HOLDER);

        console.log("buying now");
        vm.prank(buyer2);
        tokenSwap.buy(tokenBuyAmount, type(uint256).max, buyer2);
        console.log("bought");

        // Verify buy: buyer2 has tokens, HOLDER has less tokens and more currency
        assertTrue(
            token.balanceOf(buyer2) == tokenBuyAmount,
            "buyer2 token balance should equal tokenBuyAmount after buy"
        );
        assertTrue(
            token.balanceOf(HOLDER) == holderTokenBalanceBeforeBuy - tokenBuyAmount,
            "HOLDER token balance should decrease by tokenBuyAmount after buy"
        );
        assertTrue(
            paymentToken.balanceOf(HOLDER) ==
                holderPaymentTokenBalanceBeforeBuy + buyCostInPaymentToken - buyExpectedFee,
            "HOLDER payment token balance should increase by cost minus fee after buy"
        );
    }

    function testBuyWithMaxCurrencyAmount(uint256 tokenBuyAmount, uint256 maxCurrencyAmount) public {
        vm.assume(tokenBuyAmount >= 10 ** 18);
        vm.assume(tokenBuyAmount <= TOKEN_AMOUNT);
        uint256 costInPaymentToken = Math.ceilDiv(tokenBuyAmount * tokenSwap.tokenPrice(), 10 ** 18);
        vm.assume(costInPaymentToken <= paymentToken.balanceOf(BUYER));

        uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(BUYER);

        uint256 expectedFee = token.feeSettings().privateOfferFee(costInPaymentToken, address(token));

        if (maxCurrencyAmount >= costInPaymentToken) {
            vm.prank(BUYER);
            vm.expectEmit(true, true, true, true, address(tokenSwap));
            emit TokensBought(BUYER, tokenBuyAmount, costInPaymentToken);
            tokenSwap.buy(tokenBuyAmount, maxCurrencyAmount, BUYER);
            assertTrue(
                paymentTokenBalanceBefore - paymentToken.balanceOf(BUYER) <= maxCurrencyAmount,
                "BUYER should not pay more than maxCurrencyAmount"
            );
            assertTrue(
                paymentToken.balanceOf(BUYER) == paymentTokenBalanceBefore - costInPaymentToken,
                "BUYER payment token balance should decrease by costInPaymentToken"
            );
            assertTrue(token.balanceOf(BUYER) == tokenBuyAmount, "BUYER token balance should equal tokenBuyAmount");
            assertTrue(
                paymentToken.balanceOf(RECEIVER) == costInPaymentToken - expectedFee,
                "RECEIVER payment token balance should equal costInPaymentToken minus expectedFee"
            );
        } else {
            vm.prank(BUYER);
            vm.expectRevert(PurchaseTooExpensive.selector);
            tokenSwap.buy(tokenBuyAmount, maxCurrencyAmount, BUYER);
        }
    }

    function testSellWithMinCurrencyAmount(uint256 tokenSellAmount, uint256 minCurrencyAmount) public {
        // First, BUYER needs to buy tokens
        vm.prank(BUYER);
        tokenSwap.buy(TOKEN_AMOUNT / 2, type(uint256).max, BUYER);

        vm.assume(tokenSellAmount >= 10 ** 18);
        vm.assume(tokenSellAmount <= token.balanceOf(BUYER));
        uint256 payoutInPaymentToken = (tokenSellAmount * tokenSwap.tokenPrice()) / (10 ** 18);

        uint256 expectedFee = token.feeSettings().privateOfferFee(payoutInPaymentToken, address(token));
        uint256 expectedPayout = payoutInPaymentToken - expectedFee;

        vm.prank(BUYER);
        token.approve(address(tokenSwap), tokenSellAmount);

        if (minCurrencyAmount <= expectedPayout) {
            vm.prank(BUYER);
            tokenSwap.sell(tokenSellAmount, minCurrencyAmount, BUYER);
            assertTrue(
                paymentToken.balanceOf(BUYER) >= minCurrencyAmount,
                "BUYER payment token balance should be at least minCurrencyAmount"
            );
        } else {
            vm.prank(BUYER);
            vm.expectRevert(TokenSwap.PayoutTooLow.selector);
            tokenSwap.sell(tokenSellAmount, minCurrencyAmount, BUYER);
        }
    }

    function testBuyAndTransferToDifferentAddress() public {
        address addressWithFunds = vm.addr(1);
        address addressForTokens = vm.addr(2);

        uint256 availableBalance = paymentToken.balanceOf(BUYER);

        vm.prank(BUYER);
        paymentToken.transfer(addressWithFunds, availableBalance / 2);

        vm.prank(addressWithFunds);
        paymentToken.approve(address(tokenSwap), PAYMENT_TOKEN_AMOUNT);

        // check state before
        assertTrue(
            paymentToken.balanceOf(addressWithFunds) == availableBalance / 2,
            "addressWithFunds payment token balance should equal half of availableBalance"
        );
        assertTrue(
            paymentToken.balanceOf(addressForTokens) == 0,
            "addressForTokens payment token balance should be 0 before buy"
        );
        assertTrue(token.balanceOf(addressForTokens) == 0, "addressForTokens token balance should be 0 before buy");
        assertTrue(token.balanceOf(addressWithFunds) == 0, "addressWithFunds token balance should be 0 before buy");

        // execute buy, with addressForTokens as recipient
        vm.prank(addressWithFunds);
        tokenSwap.buy(TOKEN_AMOUNT / 2, type(uint256).max, addressForTokens);

        // check state after
        assertTrue(
            paymentToken.balanceOf(addressWithFunds) <=
                availableBalance / 2 - paymentToken.balanceOf(tokenSwap.receiver()),
            "addressWithFunds payment token balance should be reduced after buy"
        );
        assertTrue(
            paymentToken.balanceOf(addressForTokens) == 0,
            "addressForTokens payment token balance should be 0 after buy"
        );
        assertTrue(
            token.balanceOf(addressForTokens) == TOKEN_AMOUNT / 2,
            "addressForTokens token balance should equal TOKEN_AMOUNT / 2 after buy"
        );
        assertTrue(token.balanceOf(addressWithFunds) == 0, "addressWithFunds token balance should be 0 after buy");
    }

    function testSellAndTransferCurrencyToDifferentAddress() public {
        address addressWithTokens = vm.addr(1);
        address addressForCurrency = vm.addr(2);

        // First, buy tokens for addressWithTokens
        uint256 buyAmount = TOKEN_AMOUNT / 2;
        vm.prank(BUYER);
        tokenSwap.buy(buyAmount, type(uint256).max, addressWithTokens);

        // check state before sell
        assertTrue(
            token.balanceOf(addressWithTokens) == buyAmount,
            "addressWithTokens token balance should equal buyAmount before sell"
        );
        assertTrue(
            paymentToken.balanceOf(addressForCurrency) == 0,
            "addressForCurrency payment token balance should be 0 before sell"
        );

        // approve tokenSwap to transfer tokens
        vm.prank(addressWithTokens);
        token.approve(address(tokenSwap), buyAmount);

        // execute sell, with addressForCurrency as recipient for currency
        vm.prank(addressWithTokens);
        tokenSwap.sell(buyAmount, 0, addressForCurrency);

        // check state after
        assertTrue(token.balanceOf(addressWithTokens) == 0, "addressWithTokens token balance should be 0 after sell");
        assertTrue(
            paymentToken.balanceOf(addressForCurrency) > 0,
            "addressForCurrency payment token balance should be greater than 0 after sell"
        );
    }

    function testBuy() public {
        vm.prank(BUYER);
        tokenSwap.buy(10 ** 18, type(uint256).max, BUYER);
    }

    function testBuyFailsAfterHolderRemovesAllowance() public {
        // Holder removes their token allowance to tokenSwap
        vm.prank(HOLDER);
        token.approve(address(tokenSwap), 0);

        // Attempt to buy should fail due to insufficient allowance
        vm.prank(BUYER);
        vm.expectRevert("ERC20: insufficient allowance");
        tokenSwap.buy(10 ** 18, type(uint256).max, BUYER);
    }

    function testSell() public {
        // Mint tokens to BUYER so they have tokens to sell
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();
        vm.prank(ADMIN);
        token.grantRole(roleMintAllower, ADMIN);
        vm.prank(ADMIN);
        token.mint(BUYER, 10 ** 18);

        // Buyer approves tokenSwap to transfer their tokens
        vm.prank(BUYER);
        token.approve(address(tokenSwap), 10 ** 18);

        // Buyer sells tokens
        vm.prank(BUYER);
        tokenSwap.sell(10 ** 18, 0, BUYER);
    }

    function testSellFailsAfterHolderRemovesAllowance() public {
        // Mint tokens to BUYER so they have tokens to sell
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();
        vm.prank(ADMIN);
        token.grantRole(roleMintAllower, ADMIN);
        vm.prank(ADMIN);
        token.mint(BUYER, 10 ** 18);

        // Holder removes their payment token allowance to tokenSwap
        vm.prank(HOLDER);
        paymentToken.approve(address(tokenSwap), 0);

        // Buyer approves tokenSwap to transfer their tokens
        vm.prank(BUYER);
        token.approve(address(tokenSwap), 10 ** 18);

        // Attempt to sell should fail due to HOLDER's insufficient payment token allowance
        vm.prank(BUYER);
        vm.expectRevert("ERC20: insufficient allowance");
        tokenSwap.sell(10 ** 18, 0, BUYER);
    }

    function testBuyWhilePaused() public {
        vm.prank(OWNER);
        tokenSwap.pause();
        vm.prank(BUYER);
        vm.expectRevert("Pausable: paused");
        tokenSwap.buy(10 ** 18, type(uint256).max, BUYER);
    }

    function testSellWhilePaused() public {
        // First buy some tokens
        vm.prank(BUYER);
        tokenSwap.buy(TOKEN_AMOUNT / 2, type(uint256).max, BUYER);

        vm.prank(OWNER);
        tokenSwap.pause();

        vm.prank(BUYER);
        token.approve(address(tokenSwap), 10 ** 18);

        vm.prank(BUYER);
        vm.expectRevert("Pausable: paused");
        tokenSwap.sell(10 ** 18, 0, BUYER);
    }

    function testUpdateReceiver() public {
        assertTrue(tokenSwap.receiver() == RECEIVER);
        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true, address(tokenSwap));
        emit ReceiverChanged(address(BUYER));
        tokenSwap.setReceiver(address(BUYER));
        assertTrue(tokenSwap.receiver() == address(BUYER));

        vm.prank(OWNER);
        vm.expectRevert(ZeroReceiverAddress.selector);
        tokenSwap.setReceiver(address(0));
    }

    function testUpdatePrice(uint256 newPrice) public {
        vm.assume(newPrice > 0);
        assertTrue(tokenSwap.tokenPrice() == PRICE);

        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true, address(tokenSwap));
        emit TokenPriceChanged(newPrice);
        tokenSwap.setTokenPrice(newPrice);

        assertTrue(tokenSwap.tokenPrice() == newPrice);

        vm.prank(OWNER);
        vm.expectRevert(ZeroPrice.selector);
        tokenSwap.setTokenPrice(0);
    }

    function testPauseUnpause() public {
        assertFalse(tokenSwap.paused());
        vm.prank(OWNER);
        tokenSwap.pause();
        assertTrue(tokenSwap.paused());
        vm.prank(OWNER);
        tokenSwap.unpause();
        assertFalse(tokenSwap.paused());
    }

    function testOnlyOwnerCanPause(address rando) public {
        vm.assume(rando != OWNER);
        vm.assume(rando != TRUSTED_FORWARDER);
        vm.prank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        tokenSwap.pause();
    }

    function testOnlyOwnerCanUnpause(address rando) public {
        vm.assume(rando != OWNER);
        vm.assume(rando != TRUSTED_FORWARDER);
        vm.prank(OWNER);
        tokenSwap.pause();
        vm.prank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        tokenSwap.unpause();
    }

    function testBuyRoundsUp(uint256 _tokenBuyAmount, uint256 _price) public {
        vm.assume(_tokenBuyAmount > 0);
        vm.assume(_price > 0);
        vm.assume((UINT256_MAX - paymentToken.totalSupply()) / _price > _tokenBuyAmount);
        vm.assume(_tokenBuyAmount <= TOKEN_AMOUNT);

        uint256 tokenDecimals = token.decimals();
        uint minCurrencyAmount = (_tokenBuyAmount * _price) / 10 ** tokenDecimals;
        uint maxCurrencyAmount = minCurrencyAmount + 1;
        console.log("funding wallet");
        vm.prank(PAYMENT_TOKEN_PROVIDER);
        paymentToken.mint(BUYER, maxCurrencyAmount);
        console.log("wallet funded");

        // update PRICE
        vm.prank(OWNER);
        tokenSwap.setTokenPrice(_price);

        // set fees to 0
        {
            FeeSettings _feeSettings = FeeSettings(address(token.feeSettings()));
            _feeSettings.planFeeChange(FeeTypes.TOKEN, 0, uint64(block.timestamp));
            _feeSettings.planFeeChange(FeeTypes.CROWDINVESTING, 0, uint64(block.timestamp));
            _feeSettings.planFeeChange(FeeTypes.PRIVATE_OFFER, 0, uint64(block.timestamp));
            _feeSettings.planFeeChange(FeeTypes.SECONDARY_MARKET, 0, uint64(block.timestamp));
            _feeSettings.executeFeeChange(FeeTypes.TOKEN);
            _feeSettings.executeFeeChange(FeeTypes.CROWDINVESTING);
            _feeSettings.executeFeeChange(FeeTypes.PRIVATE_OFFER);
            _feeSettings.executeFeeChange(FeeTypes.SECONDARY_MARKET);
        }

        // approve
        vm.prank(BUYER);
        paymentToken.approve(address(tokenSwap), type(uint256).max);

        uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(BUYER);

        vm.prank(BUYER);
        tokenSwap.buy(_tokenBuyAmount, type(uint256).max, BUYER);

        // check that the BUYER got the correct amount of tokens
        assertTrue(token.balanceOf(BUYER) == _tokenBuyAmount, "BUYER token balance should equal _tokenBuyAmount");
        // check rounding
        uint256 realCostInPaymentToken = paymentTokenBalanceBefore - paymentToken.balanceOf(BUYER);
        assertTrue(realCostInPaymentToken <= type(uint256).max, "cost should be valid");
        assertTrue(realCostInPaymentToken >= minCurrencyAmount, "cost should be at least minCurrencyAmount");
        assertTrue(
            realCostInPaymentToken - minCurrencyAmount <= 1,
            "rounding difference should be at most 1 payment token unit"
        );
    }

    function testSellRoundsDown(uint256 _tokenSellAmount, uint256 _price) public {
        vm.assume(_tokenSellAmount > 0);
        vm.assume(_price > 0);
        vm.assume((UINT256_MAX - paymentToken.totalSupply()) / _price > _tokenSellAmount);
        vm.assume(_tokenSellAmount <= TOKEN_AMOUNT / 2);

        // mint tokens to SELLER
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();
        vm.prank(ADMIN);
        token.grantRole(roleMintAllower, ADMIN);
        vm.prank(ADMIN);
        token.mint(BUYER, TOKEN_AMOUNT);

        uint256 tokenDecimals = token.decimals();
        uint256 expectedPayout = (_tokenSellAmount * _price) / 10 ** tokenDecimals;

        console.log("funding wallet");
        vm.prank(PAYMENT_TOKEN_PROVIDER);
        paymentToken.mint(HOLDER, expectedPayout);
        console.log("wallet funded");

        // update tokenSwap PRICE only
        vm.prank(OWNER);
        tokenSwap.setTokenPrice(_price);

        // set fees to 0
        {
            FeeSettings _feeSettings = FeeSettings(address(token.feeSettings()));
            _feeSettings.planFeeChange(FeeTypes.CROWDINVESTING, 0, uint64(block.timestamp));
            _feeSettings.planFeeChange(FeeTypes.TOKEN, 0, uint64(block.timestamp));
            _feeSettings.planFeeChange(FeeTypes.PRIVATE_OFFER, 0, uint64(block.timestamp));
            _feeSettings.planFeeChange(FeeTypes.SECONDARY_MARKET, 0, uint64(block.timestamp));
            _feeSettings.executeFeeChange(FeeTypes.TOKEN);
            _feeSettings.executeFeeChange(FeeTypes.CROWDINVESTING);
            _feeSettings.executeFeeChange(FeeTypes.PRIVATE_OFFER);
            _feeSettings.executeFeeChange(FeeTypes.SECONDARY_MARKET);
        }

        // approve HOLDER to spend payment token
        vm.prank(HOLDER);
        paymentToken.approve(address(tokenSwap), type(uint256).max);

        // approve tokenSwap to transfer SELLER's tokens
        vm.prank(BUYER);
        token.approve(address(tokenSwap), _tokenSellAmount);

        uint256 holderPaymentTokenBalanceBefore = paymentToken.balanceOf(HOLDER);
        uint256 buyerPaymentTokenBalanceBefore = paymentToken.balanceOf(BUYER);

        vm.prank(BUYER);
        tokenSwap.sell(_tokenSellAmount, 0, BUYER);

        // check that the SELLER received payment (rounded down)
        uint256 actualPayout = paymentToken.balanceOf(BUYER) - buyerPaymentTokenBalanceBefore;
        assertTrue(actualPayout == expectedPayout, "SELLER should receive exactly expectedPayout");
        assertTrue(
            holderPaymentTokenBalanceBefore - paymentToken.balanceOf(HOLDER) == expectedPayout,
            "HOLDER payment token balance should decrease by exactly expectedPayout"
        );
    }

    function testTransferOwnership(address newOwner) public {
        vm.assume(newOwner != address(0));

        assertTrue(tokenSwap.owner() == OWNER, "wrong OWNER");

        vm.prank(OWNER);
        tokenSwap.transferOwnership(newOwner);

        assertTrue(tokenSwap.owner() == newOwner, "OWNER should be newOwner after acceptance");
    }

    function testBuyWithInsufficientHolderTokens() public {
        // Give BUYER more payment tokens to afford the purchase
        uint256 costForDoubleAmount = Math.ceilDiv(TOKEN_AMOUNT * 2 * tokenSwap.tokenPrice(), 10 ** 18);
        vm.prank(PAYMENT_TOKEN_PROVIDER);
        paymentToken.transfer(BUYER, costForDoubleAmount);

        // Buyer approves payment tokens
        vm.prank(BUYER);
        paymentToken.approve(address(tokenSwap), costForDoubleAmount);

        // Approve tokens even though HOLDER doesn't have enough
        vm.prank(HOLDER);
        token.approve(address(tokenSwap), TOKEN_AMOUNT * 2);

        // Try to buy more tokens than HOLDER has
        vm.prank(BUYER);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        tokenSwap.buy(TOKEN_AMOUNT * 2, type(uint256).max, BUYER);
    }

    function testSellWithInsufficientHolderCurrency() public {
        // First buy all available tokens
        vm.prank(BUYER);
        tokenSwap.buy(TOKEN_AMOUNT, type(uint256).max, BUYER);

        // Remove HOLDER's payment tokens
        uint256 holderBalance = paymentToken.balanceOf(HOLDER);
        vm.prank(HOLDER);
        paymentToken.transfer(PAYMENT_TOKEN_PROVIDER, holderBalance);

        // Try to sell tokens back
        vm.prank(BUYER);
        token.approve(address(tokenSwap), 10 ** 18);

        vm.prank(BUYER);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        tokenSwap.sell(10 ** 18, 0, BUYER);
    }

    function testBuyWithoutApproval() public {
        address newBuyer = vm.addr(5);

        // Give new BUYER some payment tokens
        vm.prank(PAYMENT_TOKEN_PROVIDER);
        paymentToken.transfer(newBuyer, PAYMENT_TOKEN_AMOUNT);

        // Try to buy without approval
        vm.prank(newBuyer);
        vm.expectRevert("ERC20: insufficient allowance");
        tokenSwap.buy(10 ** 18, type(uint256).max, newBuyer);
    }

    function testSellWithoutApproval() public {
        address newSeller = vm.addr(6);

        // First, buy tokens for new SELLER
        vm.prank(BUYER);
        tokenSwap.buy(10 ** 18, type(uint256).max, newSeller);

        // Try to sell without approval
        vm.prank(newSeller);
        vm.expectRevert("ERC20: insufficient allowance");
        tokenSwap.sell(10 ** 18, 0, newSeller);
    }

    function testComplexBuyAndSellScenario() public {
        // Scenario: Multiple buys and sells
        address trader1 = vm.addr(10);
        address trader2 = vm.addr(11);

        // Give traders payment tokens
        vm.prank(PAYMENT_TOKEN_PROVIDER);
        paymentToken.transfer(trader1, PAYMENT_TOKEN_AMOUNT);
        vm.prank(PAYMENT_TOKEN_PROVIDER);
        paymentToken.transfer(trader2, PAYMENT_TOKEN_AMOUNT);

        // Trader1 buys
        vm.prank(trader1);
        paymentToken.approve(address(tokenSwap), PAYMENT_TOKEN_AMOUNT);
        vm.prank(trader1);
        tokenSwap.buy(10 * 10 ** 18, type(uint256).max, trader1);

        uint256 trader1Tokens = token.balanceOf(trader1);
        assertTrue(trader1Tokens == 10 * 10 ** 18, "trader1 token balance should equal 10 tokens after buy");

        // Trader2 buys
        vm.prank(trader2);
        paymentToken.approve(address(tokenSwap), PAYMENT_TOKEN_AMOUNT);
        vm.prank(trader2);
        tokenSwap.buy(15 * 10 ** 18, type(uint256).max, trader2);

        uint256 trader2Tokens = token.balanceOf(trader2);
        assertTrue(trader2Tokens == 15 * 10 ** 18, "trader2 token balance should equal 15 tokens after buy");

        // Trader1 sells half
        vm.prank(trader1);
        token.approve(address(tokenSwap), trader1Tokens / 2);
        vm.prank(trader1);
        tokenSwap.sell(trader1Tokens / 2, 0, trader1);

        assertTrue(
            token.balanceOf(trader1) == trader1Tokens / 2,
            "trader1 token balance should equal half of initial tokens after sell"
        );
        assertTrue(
            paymentToken.balanceOf(trader1) > 0,
            "trader1 payment token balance should be greater than 0 after sell"
        );

        // Trader2 sells all
        vm.prank(trader2);
        token.approve(address(tokenSwap), trader2Tokens);
        vm.prank(trader2);
        tokenSwap.sell(trader2Tokens, 0, trader2);

        assertTrue(token.balanceOf(trader2) == 0, "trader2 token balance should be 0 after selling all");
        assertTrue(
            paymentToken.balanceOf(trader2) > 0,
            "trader2 payment token balance should be greater than 0 after sell"
        );
    }

    function testPriceAndFeeCalculationsAreCorrectDuringBuy() public {
        // Set up: 1 token costs 100 payment tokens, 2% fee
        uint256 buyAmount = 1 * 10 ** 18; // 1 token (18 decimals)
        uint256 pricePerToken = 100 * 10 ** PAYMENT_TOKEN_DECIMALS; // 100 payment tokens per token
        uint256 totalCost = pricePerToken;
        uint256 totalFee = 2 * 10 ** PAYMENT_TOKEN_DECIMALS; // 2 payment tokens
        uint256 earningAfterFee = 98 * 10 ** PAYMENT_TOKEN_DECIMALS; // 98 payment tokens
        uint32 feePercentage = 200; // 2%

        // Update fee settings to 2% secondary market fee
        uint64 feeActivationTime = 13 weeks;
        FeeSettings _feeSettings = FeeSettings(address(token.feeSettings()));
        _feeSettings.planFeeChange(FeeTypes.SECONDARY_MARKET, feePercentage, feeActivationTime);
        vm.warp(feeActivationTime + 1);
        _feeSettings.executeFeeChange(FeeTypes.SECONDARY_MARKET);
        assertTrue(_feeSettings.fee(FeeTypes.SECONDARY_MARKET, 100 * 10 ** 10, address(token)) == 2 * 10 ** 10);

        // Update token PRICE
        vm.prank(OWNER);
        tokenSwap.setTokenPrice(pricePerToken);

        // Fund BUYER with enough payment tokens (100)
        vm.prank(PAYMENT_TOKEN_PROVIDER);
        paymentToken.mint(BUYER, totalCost);

        // Approve tokenSwap to spend BUYER's payment tokens
        vm.prank(BUYER);
        paymentToken.approve(address(tokenSwap), totalCost);

        // Get fee collector address
        address feeCollector = token.feeSettings().privateOfferFeeCollector(address(token));

        // Record balances before buy
        uint256 buyerBalanceBefore = paymentToken.balanceOf(BUYER);
        uint256 holderTokenBalanceBefore = token.balanceOf(HOLDER);
        uint256 receiverBalanceBefore = paymentToken.balanceOf(RECEIVER);
        uint256 feeCollectorBalanceBefore = paymentToken.balanceOf(feeCollector);

        // Execute buy with event assertion
        vm.prank(BUYER);
        vm.expectEmit(true, true, true, true, address(tokenSwap));
        emit TokensBought(BUYER, buyAmount, totalCost);
        tokenSwap.buy(buyAmount, totalCost, BUYER);

        // Assert: 1 token is transferred to BUYER
        assertTrue(token.balanceOf(BUYER) == buyAmount, "BUYER should receive 1 token");

        assertTrue(token.balanceOf(HOLDER) == holderTokenBalanceBefore - buyAmount, "HOLDER should lose 1 token");

        // Assert: BUYER has 100 payment tokens less
        assertTrue(
            paymentToken.balanceOf(BUYER) == buyerBalanceBefore - totalCost,
            "BUYER should spend 100 payment tokens"
        );

        // Assert: RECEIVER gets 98 payment tokens (100 - 2 fee)
        assertTrue(
            paymentToken.balanceOf(RECEIVER) == receiverBalanceBefore + earningAfterFee,
            "RECEIVER should get 98 payment tokens"
        );

        // Assert: fee collector gets 2 payment tokens (2% fee)
        assertTrue(
            paymentToken.balanceOf(feeCollector) == feeCollectorBalanceBefore + totalFee,
            "fee collector should get 2 payment tokens"
        );
    }

    function testPriceAndFeeCalculationsAreCorrectDuringSell() public {
        // Set up: 1 token costs 100 payment tokens, 2% fee
        uint256 sellAmount = 1 * 10 ** 18; // 1 token (18 decimals)
        uint256 pricePerToken = 100 * 10 ** PAYMENT_TOKEN_DECIMALS; // 100 payment tokens per token
        uint256 totalPayout = pricePerToken;
        uint256 totalFee = 2 * 10 ** PAYMENT_TOKEN_DECIMALS; // 2 payment tokens
        uint256 payoutAfterFee = 98 * 10 ** PAYMENT_TOKEN_DECIMALS; // 98 payment tokens
        uint32 feePercentage = 200; // 2%

        // Update fee settings to 2% secondary market fee
        uint64 feeActivationTime = 13 weeks;
        FeeSettings _feeSettings = FeeSettings(address(token.feeSettings()));
        _feeSettings.planFeeChange(FeeTypes.SECONDARY_MARKET, feePercentage, feeActivationTime);
        vm.warp(feeActivationTime + 1);
        _feeSettings.executeFeeChange(FeeTypes.SECONDARY_MARKET);
        assertTrue(_feeSettings.fee(FeeTypes.SECONDARY_MARKET, 100 * 10 ** 10, address(token)) == 2 * 10 ** 10);

        // Update token PRICE
        vm.prank(OWNER);
        tokenSwap.setTokenPrice(pricePerToken);

        // Fund SELLER (BUYER) with 1 token
        vm.prank(PAYMENT_TOKEN_PROVIDER);
        paymentToken.mint(BUYER, pricePerToken);

        vm.prank(BUYER);
        paymentToken.approve(address(tokenSwap), pricePerToken);

        vm.prank(BUYER);
        tokenSwap.buy(sellAmount, type(uint256).max, BUYER);

        // Fund HOLDER with enough payment tokens to pay the SELLER
        vm.prank(PAYMENT_TOKEN_PROVIDER);
        paymentToken.mint(HOLDER, totalPayout);

        // Approve tokenSwap to spend HOLDER's payment tokens
        vm.prank(HOLDER);
        paymentToken.approve(address(tokenSwap), totalPayout);

        // Approve tokenSwap to transfer SELLER's tokens
        vm.prank(BUYER);
        token.approve(address(tokenSwap), sellAmount);

        // Get fee collector address
        address feeCollector = token.feeSettings().privateOfferFeeCollector(address(token));

        // Record balances before sell
        uint256 sellerBalanceBefore = paymentToken.balanceOf(BUYER);
        uint256 feeCollectorBalanceBefore = paymentToken.balanceOf(feeCollector);
        uint256 sellerTokenBalanceBefore = token.balanceOf(BUYER);
        uint256 receiverTokenBalanceBefore = token.balanceOf(RECEIVER);

        // Execute sell with event assertion
        vm.prank(BUYER);
        vm.expectEmit(true, true, true, true, address(tokenSwap));
        emit TokensSold(BUYER, sellAmount, totalPayout);
        tokenSwap.sell(sellAmount, 0, BUYER);

        // Assert: 1 token is transferred from SELLER
        assertTrue(token.balanceOf(BUYER) == sellerTokenBalanceBefore - sellAmount, "SELLER should lose 1 token");

        // Assert: SELLER receives 98 payment tokens (100 - 2 fee)
        assertTrue(
            paymentToken.balanceOf(BUYER) == sellerBalanceBefore + payoutAfterFee,
            "SELLER should receive 98 payment tokens"
        );

        // Assert: RECEIVER gets 1 token (the sold token)
        assertTrue(token.balanceOf(RECEIVER) == receiverTokenBalanceBefore + sellAmount, "RECEIVER should get 1 token");

        // Assert: fee collector gets 2 payment tokens (2% fee)
        assertTrue(
            paymentToken.balanceOf(feeCollector) == feeCollectorBalanceBefore + totalFee,
            "fee collector should get 2 payment tokens"
        );
    }

    /// Exercises the V2 fallback path in TokenSwapBase._getFeeAndFeeReceiver():
    /// when feeSettings does not support IFeeSettingsV3, privateOfferFee/privateOfferFeeCollector are used.
    function testV2FallbackFeePathOnBuy() public {
        address feeCollectorAddress = address(0x1234);
        V2OnlyFeeSettings v2Fee = new V2OnlyFeeSettings(feeCollectorAddress);

        // Switch the token to use V2-only fee settings.
        // suggestNewFeeSettings requires msg.sender == feeSettings.owner(); the test contract owns feeSettings.
        token.suggestNewFeeSettings(IFeeSettingsV2(address(v2Fee)));
        vm.prank(ADMIN);
        token.acceptNewFeeSettings(IFeeSettingsV2(address(v2Fee)));

        uint256 feeCollectorBalanceBefore = paymentToken.balanceOf(feeCollectorAddress);

        // Run a buy on the existing tokenSwap — this triggers the V2 fallback in _getFeeAndFeeReceiver.
        uint256 buyAmount = 1e18;
        uint256 cost = Math.ceilDiv(buyAmount * tokenSwap.tokenPrice(), 10 ** token.decimals());
        vm.prank(BUYER);
        tokenSwap.buy(buyAmount, type(uint256).max, BUYER);

        assertEq(token.balanceOf(BUYER), buyAmount, "BUYER should have received tokens via V2 fallback fee path");
        assertTrue(paymentToken.balanceOf(BUYER) == PAYMENT_TOKEN_AMOUNT - cost, "BUYER payment token balance wrong");
        assertEq(
            paymentToken.balanceOf(feeCollectorAddress),
            feeCollectorBalanceBefore + v2Fee.SOME_RANDOM_FIXED_FEE(),
            "Wrong fee"
        );
    }
}
