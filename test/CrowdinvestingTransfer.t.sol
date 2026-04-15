// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/FeeSettings.sol";
import "../contracts/factories/CrowdinvestingCloneFactory.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/MaliciousPaymentToken.sol";
import "./resources/FakeCrowdinvestingAndToken.sol";
import "./resources/CloneCreators.sol";
import "./resources/CrowdinvestingArgumentHelper.sol";

contract CrowdinvestingTransferTest is Test {
    event CurrencyReceiverChanged(address indexed);
    event MinAmountPerBuyerChanged(uint256);
    event MaxAmountPerBuyerChanged(uint256);
    event TokenPriceAndCurrencyChanged(uint256, IERC20 indexed);
    event MaxAmountOfTokenToBeSoldChanged(uint256);
    event TokensBought(address indexed BUYER, uint256 tokenAmount, uint256 currencyAmount);

    CrowdinvestingCloneFactory factory;
    Crowdinvesting crowdinvesting;
    AllowList list;
    IFeeSettingsV2 feeSettings;

    address wrongFeeReceiver = address(5);

    TokenProxyFactory tokenCloneFactory;
    Token token;
    FakePaymentToken paymentToken;

    MaliciousPaymentToken maliciousPaymentToken;

    address public constant ADMIN = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant BUYER = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant MINT_ALLOWER = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant MINTER = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant OWNER = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant RECEIVER = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant PAYMENT_TOKEN_PROVIDER = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant TRUSTED_FORWARDER = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;
    address public constant TOKEN_HOLDER = 0xa109709ecfA91A80626ff3989D68F67F5b1dD12a;

    uint8 public constant PAYMENT_TOKEN_DECIMALS = 6;
    uint256 public constant PAYMENT_TOKEN_AMOUNT = 1000 * 10 ** PAYMENT_TOKEN_DECIMALS;

    uint256 public constant PRICE = 7 * 10 ** PAYMENT_TOKEN_DECIMALS; // 7 payment tokens per token

    uint256 public constant MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD = 20 * 10 ** 18; // 20 token
    uint256 public constant MAX_AMOUNT_PER_BUYER = MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 2; // 10 token
    uint256 public constant MIN_AMOUNT_PER_BUYER = MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 200; // 0.1 token

    uint256 public constant LAST_BUY_DATE = 12859023;

    function setUp() public {
        // set up currency
        vm.prank(PAYMENT_TOKEN_PROVIDER);
        paymentToken = new FakePaymentToken(PAYMENT_TOKEN_AMOUNT, PAYMENT_TOKEN_DECIMALS); // 1000 tokens with 6 decimals
        // transfer currency to BUYER
        vm.prank(PAYMENT_TOKEN_PROVIDER);
        paymentToken.transfer(BUYER, PAYMENT_TOKEN_AMOUNT);
        assertTrue(paymentToken.balanceOf(BUYER) == PAYMENT_TOKEN_AMOUNT);

        list = createAllowList(TRUSTED_FORWARDER, OWNER);
        vm.startPrank(OWNER);
        list.set(address(paymentToken), TRUSTED_CURRENCY);
        list.set(TOKEN_HOLDER, 0x0);
        vm.stopPrank();

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

        vm.prank(OWNER);
        factory = new CrowdinvestingCloneFactory(address(new Crowdinvesting(TRUSTED_FORWARDER)));
        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            OWNER,
            payable(RECEIVER),
            MIN_AMOUNT_PER_BUYER,
            MAX_AMOUNT_PER_BUYER,
            PRICE,
            PRICE,
            PRICE,
            MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD,
            paymentToken,
            token,
            0,
            address(0),
            TOKEN_HOLDER
        );
        crowdinvesting = Crowdinvesting(factory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, arguments));

        // allow crowdinvesting contract to mint
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(ADMIN);
        token.grantRole(roleMintAllower, MINT_ALLOWER);
        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(address(ADMIN), MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD);
        vm.prank(ADMIN);
        token.mint(TOKEN_HOLDER, MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD);
        vm.stopPrank();

        // give token holder allowance to crowdinvesting contract
        vm.startPrank(TOKEN_HOLDER);
        token.approve(address(crowdinvesting), MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD);
        vm.stopPrank();

        // give crowdinvesting contract currency allowance
        vm.prank(BUYER);
        paymentToken.approve(address(crowdinvesting), PAYMENT_TOKEN_AMOUNT);
    }

    function testLogicContractCreation() public {
        Crowdinvesting _logic = new Crowdinvesting(address(1));

        console.log("address of logic contract: ", address(_logic));

        // try to initialize
        vm.expectRevert("Initializable: contract is already initialized");
        _logic.initialize(
            CrowdinvestingInitializerArguments(
                address(this),
                payable(RECEIVER),
                MIN_AMOUNT_PER_BUYER,
                MAX_AMOUNT_PER_BUYER,
                PRICE,
                PRICE,
                PRICE,
                MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD,
                paymentToken,
                token,
                0,
                address(0),
                TOKEN_HOLDER
            )
        );

        // OWNER and all settings are 0
        assertTrue(_logic.owner() == address(0), "OWNER is not 0");
        assertTrue(_logic.currencyReceiver() == address(0));
        assertTrue(_logic.minAmountPerBuyer() == 0);
        assertTrue(_logic.maxAmountPerBuyer() == 0);
        assertTrue(_logic.priceBase() == 0);
        assertTrue(address(_logic.currency()) == address(0));
        assertTrue(address(_logic.token()) == address(0));
        assertTrue(address(_logic.tokenHolder()) == address(0));
    }

    function testConstructorHappyCase() public {
        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            address(this),
            payable(RECEIVER),
            MIN_AMOUNT_PER_BUYER,
            MAX_AMOUNT_PER_BUYER,
            PRICE,
            PRICE,
            PRICE,
            MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD,
            paymentToken,
            token,
            LAST_BUY_DATE,
            address(0),
            TOKEN_HOLDER
        );
        Crowdinvesting _crowdinvesting = Crowdinvesting(
            factory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, arguments)
        );
        assertTrue(_crowdinvesting.owner() == address(this));
        assertTrue(_crowdinvesting.currencyReceiver() == RECEIVER);
        assertTrue(_crowdinvesting.minAmountPerBuyer() == MIN_AMOUNT_PER_BUYER);
        assertTrue(_crowdinvesting.maxAmountPerBuyer() == MAX_AMOUNT_PER_BUYER);
        assertTrue(_crowdinvesting.maxAmountOfTokenToBeSold() == MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD);
        assertTrue(_crowdinvesting.priceBase() == PRICE);
        assertTrue(_crowdinvesting.currency() == paymentToken);
        assertTrue(_crowdinvesting.token() == token);
        assertTrue(_crowdinvesting.lastBuyDate() == LAST_BUY_DATE);
        assertTrue(address(_crowdinvesting.tokenHolder()) == TOKEN_HOLDER);
    }

    function testConstructorWithBadArguments() public {
        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            address(this),
            payable(RECEIVER),
            MIN_AMOUNT_PER_BUYER,
            MAX_AMOUNT_PER_BUYER,
            PRICE,
            PRICE,
            PRICE,
            MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD,
            paymentToken,
            token,
            0,
            address(0),
            TOKEN_HOLDER
        );
        vm.expectRevert("CrowdinvestingCloneFactory: Unexpected TRUSTED_FORWARDER");
        Crowdinvesting(factory.createCrowdinvestingClone(0, address(0), arguments));

        // OWNER 0
        CrowdinvestingInitializerArguments memory tempArgs = cloneCrowdinvestingInitializerArguments(arguments);
        tempArgs.owner = address(0);
        vm.expectRevert("OWNER can not be zero address");
        factory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, tempArgs);

        // RECEIVER 0
        tempArgs = cloneCrowdinvestingInitializerArguments(arguments);
        tempArgs.currencyReceiver = address(0);
        vm.expectRevert("currencyReceiver can not be zero address");
        factory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, tempArgs);

        // token minAmount > MAX_AMOUNT_PER_BUYER
        tempArgs = cloneCrowdinvestingInitializerArguments(arguments);
        tempArgs.minAmountPerBuyer = MAX_AMOUNT_PER_BUYER + 1;
        vm.expectRevert("_minAmountPerBuyer needs to be smaller or equal to _maxAmountPerBuyer");
        factory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, tempArgs);

        // token minAmount 0
        tempArgs = cloneCrowdinvestingInitializerArguments(arguments);
        tempArgs.minAmountPerBuyer = 0;
        vm.expectRevert("_minAmountPerBuyer needs to be larger than zero");
        factory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, tempArgs);

        // PRICE 0
        tempArgs = cloneCrowdinvestingInitializerArguments(arguments);
        tempArgs.tokenPrice = 0;
        vm.expectRevert("_tokenPrice needs to be a non-zero amount");
        factory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, tempArgs);

        // max PRICE 0
        tempArgs = cloneCrowdinvestingInitializerArguments(arguments);
        tempArgs.priceMax = 0;
        tempArgs.priceOracle = address(3);
        vm.expectRevert("priceMax needs to be larger or equal to priceBase");
        factory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, tempArgs);

        // min PRICE too high
        tempArgs.priceMax = PRICE;
        tempArgs.priceMin = PRICE + 1;
        vm.expectRevert("priceMin needs to be smaller or equal to priceBase");
        factory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, tempArgs);

        // token maxAmountToBeSold 0
        tempArgs = cloneCrowdinvestingInitializerArguments(arguments);
        tempArgs.maxAmountOfTokenToBeSold = 0;
        vm.expectRevert("_maxAmountOfTokenToBeSold needs to be larger than zero");
        factory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, tempArgs);

        // currency 0
        tempArgs = cloneCrowdinvestingInitializerArguments(arguments);
        tempArgs.currency = IERC20(address(0));
        vm.expectRevert("currency can not be zero address");
        factory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, tempArgs);

        // token 0
        tempArgs = cloneCrowdinvestingInitializerArguments(arguments);
        tempArgs.token = Token(address(0));
        vm.expectRevert("token can not be zero address");
        factory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, tempArgs);

        // TOKEN_HOLDER 0 -> this should not revert, as it is allowed to set TOKEN_HOLDER to 0
        tempArgs = cloneCrowdinvestingInitializerArguments(arguments);
        tempArgs.tokenHolder = address(0);
        factory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, tempArgs);
    }

    /*
    set up with MaliciousPaymentToken which tries to reenter the buy function
    */
    function testReentrancy() public {
        uint8 _paymentTokenDecimals = 18;

        /*
        _paymentToken: 1 FPT = 10**_paymentTokenDecimals FPTbits (bit = smallest subunit of token)
        Token: 1 CT = 10**18 CTbits
        PRICE definition: 30FPT buy 1CT, but must be expressed in FPTbits/CT
        PRICE = 30 * 10**_paymentTokenDecimals
        */

        uint256 _price = 7 * 10 ** _paymentTokenDecimals;
        uint256 _maxMintAmount = 1000 * 10 ** 18; // 2**256 - 1; // need maximum possible value because we are using a fake token with variable decimals
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
        vm.prank(PAYMENT_TOKEN_PROVIDER);
        maliciousPaymentToken = new MaliciousPaymentToken(_paymentTokenAmount);
        vm.prank(OWNER);
        list.set(address(maliciousPaymentToken), TRUSTED_CURRENCY);

        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            address(this),
            payable(RECEIVER),
            1,
            _maxMintAmount / 100,
            _price,
            _price,
            _price,
            _maxMintAmount,
            maliciousPaymentToken,
            _token,
            0,
            address(0),
            address(0)
        );

        Crowdinvesting _crowdinvesting = Crowdinvesting(
            factory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, arguments)
        );

        // allow invite contract to mint
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(ADMIN);
        _token.grantRole(roleMintAllower, MINT_ALLOWER);
        vm.startPrank(MINT_ALLOWER);
        _token.increaseMintingAllowance(
            address(_crowdinvesting),
            _maxMintAmount - token.mintingAllowance(address(_crowdinvesting))
        );
        vm.stopPrank();

        // mint _paymentToken for BUYER
        vm.prank(PAYMENT_TOKEN_PROVIDER);
        maliciousPaymentToken.transfer(BUYER, _paymentTokenAmount);
        assertTrue(maliciousPaymentToken.balanceOf(BUYER) == _paymentTokenAmount);

        // set exploitTarget
        maliciousPaymentToken.setExploitTarget(address(_crowdinvesting), 3, _maxMintAmount / 200000);

        // give invite contract allowance
        vm.prank(BUYER);
        maliciousPaymentToken.approve(address(_crowdinvesting), _paymentTokenAmount);

        // store some state
        //uint buyerPaymentBalanceBefore = _paymentToken.balanceOf(BUYER);

        // run actual test
        assertTrue(maliciousPaymentToken.balanceOf(BUYER) == _paymentTokenAmount);
        uint256 buyAmount = _maxMintAmount / 100000;
        vm.prank(BUYER);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        _crowdinvesting.buy(buyAmount, type(uint256).max, BUYER);
    }

    function testBuyHappyCase(uint256 tokenBuyAmount) public {
        vm.assume(tokenBuyAmount >= crowdinvesting.minAmountPerBuyer());
        vm.assume(tokenBuyAmount <= crowdinvesting.maxAmountPerBuyer());
        uint256 costInPaymentToken = Math.ceilDiv(tokenBuyAmount * crowdinvesting.priceBase(), 10 ** 18);
        vm.assume(costInPaymentToken <= paymentToken.balanceOf(BUYER));

        uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(BUYER);

        FakeCrowdinvesting fakeCrowdinvesting = new FakeCrowdinvesting(address(token));

        // check state is correct before buy
        assertTrue(token.balanceOf(TOKEN_HOLDER) == MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD, "TOKEN_HOLDER has tokens");
        assertTrue(token.balanceOf(BUYER) == 0, "BUYER has no tokens");
        assertTrue(paymentToken.balanceOf(RECEIVER) == 0, "RECEIVER has no payment tokens");
        assertTrue(crowdinvesting.tokensSold() == 0, "crowdinvesting has sold no tokens");
        assertTrue(crowdinvesting.tokensBought(BUYER) == 0, "crowdinvesting has sold no tokens to BUYER");
        uint256 feeCollectorTokenBalanceBefore = token.balanceOf(
            FeeSettings(address(token.feeSettings())).tokenFeeCollector(address(token))
        );
        uint256 feeCollectorPaymentTokenBalanceBefore = paymentToken.balanceOf(
            FeeSettings(address(token.feeSettings())).crowdinvestingFeeCollector(address(token))
        );
        assertEq(feeCollectorPaymentTokenBalanceBefore, 0, "fee collector has payment tokens before buy");

        vm.prank(BUYER);
        vm.expectEmit(true, true, true, true, address(crowdinvesting));
        emit TokensBought(BUYER, tokenBuyAmount, costInPaymentToken);
        crowdinvesting.buy(tokenBuyAmount, type(uint256).max, BUYER);
        assertTrue(paymentToken.balanceOf(BUYER) == paymentTokenBalanceBefore - costInPaymentToken, "BUYER has paid");
        assertTrue(token.balanceOf(BUYER) == tokenBuyAmount, "BUYER has tokens");
        assertTrue(
            paymentToken.balanceOf(RECEIVER) == costInPaymentToken - fakeCrowdinvesting.fee(costInPaymentToken),
            "RECEIVER has payment tokens"
        );
        assertTrue(
            paymentToken.balanceOf(
                FeeSettings(address(token.feeSettings())).crowdinvestingFeeCollector(address(token))
            ) == fakeCrowdinvesting.fee(costInPaymentToken),
            "fee collector has collected fee in payment tokens"
        );
        assertTrue(
            token.balanceOf(FeeSettings(address(token.feeSettings())).tokenFeeCollector(address(token))) ==
                feeCollectorTokenBalanceBefore,
            "fee collector has collected additional fee in tokens"
        );
        assertTrue(
            token.balanceOf(TOKEN_HOLDER) == MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD - tokenBuyAmount,
            "TOKEN_HOLDER has wrong amount of tokens"
        );
        assertTrue(crowdinvesting.tokensSold() == tokenBuyAmount, "crowdinvesting has sold tokens");
        assertTrue(crowdinvesting.tokensBought(BUYER) == tokenBuyAmount, "crowdinvesting has sold tokens to BUYER");
    }

    //     function testBuyWithMaxCurrencyAmount(uint256 tokenBuyAmount, uint256 maxCurrencyAmount) public {
    //         vm.assume(tokenBuyAmount >= crowdinvesting.minAmountPerBuyer());
    //         vm.assume(tokenBuyAmount <= crowdinvesting.maxAmountPerBuyer());
    //         uint256 costInPaymentToken = Math.ceilDiv(tokenBuyAmount * crowdinvesting.priceBase(), 10 ** 18);
    //         vm.assume(costInPaymentToken <= paymentToken.balanceOf(BUYER));

    //         uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(BUYER);

    //         FeeSettings localFeeSettings = FeeSettings(address(token.feeSettings()));
    //         FakeCrowdinvesting fakeCrowdinvesting = new FakeCrowdinvesting(address(token));

    //         if (maxCurrencyAmount >= costInPaymentToken) {
    //             vm.prank(BUYER);
    //             vm.expectEmit(true, true, true, true, address(crowdinvesting));
    //             emit TokensBought(BUYER, tokenBuyAmount, costInPaymentToken);
    //             crowdinvesting.buy(tokenBuyAmount, maxCurrencyAmount, BUYER);
    //             assertTrue(
    //                 paymentTokenBalanceBefore - paymentToken.balanceOf(BUYER) <= maxCurrencyAmount,
    //                 "BUYER has paid too much!"
    //             );
    //             assertTrue(
    //                 paymentToken.balanceOf(BUYER) == paymentTokenBalanceBefore - costInPaymentToken,
    //                 "BUYER has paid"
    //             );
    //             assertTrue(token.balanceOf(BUYER) == tokenBuyAmount, "BUYER has tokens");
    //             assertTrue(
    //                 paymentToken.balanceOf(RECEIVER) == costInPaymentToken - fakeCrowdinvesting.fee(costInPaymentToken),
    //                 "RECEIVER has payment tokens"
    //             );
    //             assertTrue(
    //                 paymentToken.balanceOf(
    //                     FeeSettings(address(token.feeSettings())).crowdinvestingFeeCollector(address(token))
    //                 ) == fakeCrowdinvesting.fee(costInPaymentToken),
    //                 "fee collector has collected fee in payment tokens"
    //             );
    //             assertTrue(
    //                 token.balanceOf(FeeSettings(address(token.feeSettings())).tokenFeeCollector(address(token))) ==
    //                     localFeeSettings.tokenFee(tokenBuyAmount),
    //                 "fee collector has collected fee in tokens"
    //             );
    //             assertTrue(crowdinvesting.tokensSold() == tokenBuyAmount, "crowdinvesting has sold tokens");
    //             assertTrue(crowdinvesting.tokensBought(BUYER) == tokenBuyAmount, "crowdinvesting has sold tokens to BUYER");
    //         } else {
    //             vm.prank(BUYER);
    //             vm.expectRevert("Purchase more expensive than _maxCurrencyAmount");
    //             crowdinvesting.buy(tokenBuyAmount, maxCurrencyAmount, BUYER);
    //         }
    //     }

    //     function testBuyTooMuch() public {
    //         uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(BUYER);

    //         vm.prank(BUYER);
    //         vm.expectRevert("Total amount of bought tokens needs to be lower than or equal to maxAmount");
    //         crowdinvesting.buy(MAX_AMOUNT_PER_BUYER + 10 ** 18, type(uint256).max, BUYER); //+ 10**token.decimals());
    //         assertTrue(paymentToken.balanceOf(BUYER) == paymentTokenBalanceBefore);
    //         assertTrue(token.balanceOf(BUYER) == 0);
    //         assertTrue(paymentToken.balanceOf(RECEIVER) == 0);
    //         assertTrue(crowdinvesting.tokensSold() == 0);
    //         assertTrue(crowdinvesting.tokensBought(BUYER) == 0);
    //     }

    //     function testBuyAndMintToDifferentAddress() public {
    //         address addressWithFunds = vm.addr(1);
    //         address addressForTokens = vm.addr(2);

    //         uint256 availableBalance = paymentToken.balanceOf(BUYER);

    //         vm.prank(BUYER);
    //         paymentToken.transfer(addressWithFunds, availableBalance / 2);

    //         vm.prank(addressWithFunds);
    //         paymentToken.approve(address(crowdinvesting), PAYMENT_TOKEN_AMOUNT);

    //         // check state before
    //         assertTrue(paymentToken.balanceOf(addressWithFunds) == availableBalance / 2, "addressWithFunds has no funds");
    //         assertTrue(paymentToken.balanceOf(addressForTokens) == 0, "addressForTokens has funds");
    //         assertTrue(token.balanceOf(addressForTokens) == 0, "addressForTokens has tokens before buy");
    //         assertTrue(token.balanceOf(addressWithFunds) == 0, "addressWithFunds has tokens before buy");

    //         // execute buy, with addressForTokens as recipient
    //         vm.prank(addressWithFunds);
    //         crowdinvesting.buy(MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 2, type(uint256).max, addressForTokens);

    //         // check state after
    //         console.log("addressWithFunds balance: ", paymentToken.balanceOf(addressWithFunds));
    //         assertTrue(
    //             paymentToken.balanceOf(addressWithFunds) <=
    //                 availableBalance / 2 - paymentToken.balanceOf(crowdinvesting.currencyReceiver()),
    //             "addressWithFunds has funds after buy"
    //         );
    //         assertTrue(paymentToken.balanceOf(addressForTokens) == 0, "addressForTokens has funds after buy");
    //         assertTrue(
    //             token.balanceOf(addressForTokens) == MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 2,
    //             "addressForTokens has wrong amount of tokens after buy"
    //         );
    //         assertTrue(token.balanceOf(addressWithFunds) == 0, "addressWithFunds has tokens after buy");
    //     }

    //     function testMultiplePeopleBuyTooMuch() public {
    //         address person1 = vm.addr(1);
    //         address person2 = vm.addr(2);

    //         uint256 availableBalance = paymentToken.balanceOf(BUYER);

    //         vm.prank(BUYER);
    //         paymentToken.transfer(person1, availableBalance / 3);
    //         vm.prank(BUYER);
    //         paymentToken.transfer(person2, availableBalance / 3);

    //         vm.prank(person1);
    //         paymentToken.approve(address(crowdinvesting), PAYMENT_TOKEN_AMOUNT);

    //         vm.prank(person2);
    //         paymentToken.approve(address(crowdinvesting), PAYMENT_TOKEN_AMOUNT);

    //         vm.prank(BUYER);
    //         crowdinvesting.buy(MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 2, type(uint256).max, BUYER);
    //         vm.prank(person1);
    //         crowdinvesting.buy(MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 2, type(uint256).max, person1);
    //         vm.prank(person2);
    //         vm.expectRevert("Not enough tokens to sell left");
    //         crowdinvesting.buy(10 ** 18, type(uint256).max, person2);
    //     }

    //     function testMultipleAddressesBuyForOneReceiver() public {
    //         address person1 = vm.addr(1);
    //         address person2 = vm.addr(2);

    //         uint256 availableBalance = paymentToken.balanceOf(BUYER);

    //         vm.prank(BUYER);
    //         paymentToken.transfer(person1, availableBalance / 2);
    //         vm.prank(BUYER);
    //         paymentToken.transfer(person2, 10 ** 6);

    //         vm.prank(person1);
    //         paymentToken.approve(address(crowdinvesting), PAYMENT_TOKEN_AMOUNT);

    //         vm.prank(person2);
    //         paymentToken.approve(address(crowdinvesting), PAYMENT_TOKEN_AMOUNT);

    //         vm.prank(BUYER);
    //         crowdinvesting.buy(MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 2, type(uint256).max, BUYER);
    //         vm.prank(person1);
    //         vm.expectRevert("Total amount of bought tokens needs to be lower than or equal to maxAmount");
    //         crowdinvesting.buy(MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 2, type(uint256).max, BUYER);
    //     }

    //     function testCorrectAccounting() public {
    //         address person1 = vm.addr(1);
    //         address person2 = vm.addr(2);

    //         uint256 availableBalance = paymentToken.balanceOf(BUYER);

    //         vm.prank(BUYER);
    //         paymentToken.transfer(person1, availableBalance / 2);
    //         vm.prank(BUYER);
    //         paymentToken.transfer(person2, 10 ** 6);

    //         vm.prank(person1);
    //         paymentToken.approve(address(crowdinvesting), PAYMENT_TOKEN_AMOUNT);

    //         vm.prank(person2);
    //         paymentToken.approve(address(crowdinvesting), PAYMENT_TOKEN_AMOUNT);

    //         // check all entries are 0 before
    //         assertTrue(crowdinvesting.tokensSold() == 0);
    //         assertTrue(crowdinvesting.tokensBought(BUYER) == 0);
    //         assertTrue(crowdinvesting.tokensBought(person1) == 0);
    //         assertTrue(crowdinvesting.tokensBought(person2) == 0);

    //         vm.prank(BUYER);
    //         crowdinvesting.buy(MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 2, type(uint256).max, BUYER);
    //         vm.prank(BUYER);
    //         crowdinvesting.buy(MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 4, type(uint256).max, person1);
    //         vm.prank(BUYER);
    //         crowdinvesting.buy(MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 8, type(uint256).max, person2);

    //         // check all entries are correct after
    //         assertTrue(crowdinvesting.tokensSold() == (MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD * 7) / 8);
    //         assertTrue(crowdinvesting.tokensBought(BUYER) == MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 2);
    //         assertTrue(crowdinvesting.tokensBought(person1) == MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 4);
    //         assertTrue(crowdinvesting.tokensBought(person2) == MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 8);
    //         assertTrue(token.balanceOf(BUYER) == MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 2);
    //         assertTrue(token.balanceOf(person1) == MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 4);
    //         assertTrue(token.balanceOf(person2) == MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 8);
    //     }

    //     function testExceedMintingAllowance() public {
    //         // reduce minting allowance of fundraising contract, so the revert happens in Token
    //         vm.startPrank(MINT_ALLOWER);
    //         token.decreaseMintingAllowance(
    //             address(crowdinvesting),
    //             token.mintingAllowance(address(crowdinvesting)) - (MAX_AMOUNT_PER_BUYER / 2)
    //         );
    //         vm.stopPrank();

    //         vm.prank(BUYER);
    //         vm.expectRevert("MintingAllowance too low");
    //         crowdinvesting.buy(MAX_AMOUNT_PER_BUYER, type(uint256).max, BUYER); //+ 10**token.decimals());
    //         assertTrue(token.balanceOf(BUYER) == 0);
    //         assertTrue(paymentToken.balanceOf(RECEIVER) == 0);
    //         assertTrue(crowdinvesting.tokensSold() == 0);
    //         assertTrue(crowdinvesting.tokensBought(BUYER) == 0);
    //     }

    //     function testBuyTooLittle() public {
    //         uint256 tokenBuyAmount = 5 * 10 ** token.decimals();
    //         uint256 costInPaymentToken = (tokenBuyAmount * PRICE) / 10 ** 18;

    //         assert(costInPaymentToken == 35 * 10 ** PAYMENT_TOKEN_DECIMALS); // 35 payment tokens, manually calculated

    //         uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(BUYER);

    //         vm.prank(BUYER);
    //         vm.expectRevert("Buyer needs to buy at least minAmount");
    //         crowdinvesting.buy(MIN_AMOUNT_PER_BUYER / 2, type(uint256).max, BUYER);
    //         assertTrue(paymentToken.balanceOf(BUYER) == paymentTokenBalanceBefore);
    //         assertTrue(token.balanceOf(BUYER) == 0);
    //         assertTrue(paymentToken.balanceOf(RECEIVER) == 0);
    //         assertTrue(crowdinvesting.tokensSold() == 0);
    //         assertTrue(crowdinvesting.tokensBought(BUYER) == 0);
    //     }

    //     function testBuySmallAmountAfterInitialInvestment() public {
    //         uint256 tokenBuyAmount = MIN_AMOUNT_PER_BUYER;
    //         uint256 costInPaymentTokenForMinAmount = (tokenBuyAmount * PRICE) / 10 ** 18;
    //         uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(BUYER);

    //         vm.prank(BUYER);
    //         crowdinvesting.buy(MIN_AMOUNT_PER_BUYER, type(uint256).max, BUYER);

    //         // buy less than minAmount -> should be okay because minAmount has already been bought.
    //         vm.prank(BUYER);
    //         crowdinvesting.buy(MIN_AMOUNT_PER_BUYER / 2, type(uint256).max, BUYER);

    //         uint256 totalBought = (MIN_AMOUNT_PER_BUYER * 3) / 2;
    //         uint256 totalPaid = (costInPaymentTokenForMinAmount * 3) / 2;

    //         assertTrue(
    //             paymentToken.balanceOf(BUYER) == paymentTokenBalanceBefore - (costInPaymentTokenForMinAmount * 3) / 2,
    //             "BUYER has payment tokens"
    //         );
    //         assertTrue(token.balanceOf(BUYER) == totalBought, "BUYER has tokens");
    //         uint256 tokenFee = token.feeSettings().tokenFee(totalBought, address(token));
    //         uint256 paymentTokenFee = token.feeSettings().crowdinvestingFee(totalPaid, address(token));
    //         // assertTrue(
    //         //     paymentToken.balanceOf(RECEIVER) == (costInPaymentTokenForMinAmount * 3) / 2 - paymentTokenFee,
    //         //     "RECEIVER received payment tokens"
    //         // );
    //         assertEq(
    //             token.balanceOf(FeeSettings(address(token.feeSettings())).tokenFeeCollector(address(token))),
    //             tokenFee,
    //             "fee collector has not collected fee in tokens"
    //         );
    //         assertEq(
    //             paymentToken.balanceOf(
    //                 FeeSettings(address(token.feeSettings())).crowdinvestingFeeCollector(address(token))
    //             ),
    //             paymentTokenFee,
    //             "fee collector has not collected fee in payment tokens"
    //         );
    //         assertTrue(crowdinvesting.tokensSold() == (MIN_AMOUNT_PER_BUYER * 3) / 2, "crowdinvesting has sold tokens");
    //         assertTrue(
    //             crowdinvesting.tokensBought(BUYER) == crowdinvesting.tokensSold(),
    //             "crowdinvesting has sold tokens to BUYER"
    //         );
    //     }

    //     function ensureRealCostIsHigherEqualAdvertisedCost(uint256 tokenBuyAmount) public {
    //         uint256 _price = 1; // PRICE = 1 currency bit per full token (10**18 token bits)

    //         // set PRICE that is finer than the resolution of the payment token
    //         vm.startPrank(OWNER);
    //         crowdinvesting.pause();
    //         crowdinvesting.setCurrencyAndTokenPrice(crowdinvesting.currency(), _price);
    //         crowdinvesting.setMinAmountPerBuyer(1); // min amount = 1 currency bit
    //         vm.warp(block.timestamp + 1 days + 1 seconds);
    //         crowdinvesting.unpause();
    //         vm.stopPrank();

    //         // this is rounded down and resolves to 0 cost in payment token
    //         uint256 naiveCostInPaymentToken = (tokenBuyAmount * _price) / 10 ** 18;
    //         console.log("naiveCostInPaymentToken", naiveCostInPaymentToken);
    //         //assertTrue(naiveCostInPaymentToken == 0, "Naive cost is not 0"); // 35 payment tokens, manually calculated

    //         uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(BUYER);

    //         vm.prank(BUYER);
    //         crowdinvesting.buy(tokenBuyAmount, type(uint256).max, BUYER);

    //         console.log("paymentTokenBalanceBefore", paymentTokenBalanceBefore);
    //         console.log("paymentToken.balanceOf(BUYER)", paymentToken.balanceOf(BUYER));

    //         uint256 realCostInPaymentToken = paymentTokenBalanceBefore - paymentToken.balanceOf(BUYER);
    //         uint256 realPrice = (realCostInPaymentToken * 10 ** 18) / token.balanceOf(BUYER);
    //         console.log("realCostInPaymentToken", realCostInPaymentToken);
    //         console.log("token.balanceOf(BUYER)", token.balanceOf(BUYER));
    //         console.log("advertised PRICE: ", crowdinvesting.priceBase());
    //         console.log("real PRICE: ", realPrice);
    //         assertTrue(token.balanceOf(BUYER) == tokenBuyAmount, "BUYER has not received tokens");
    //         assertTrue(paymentToken.balanceOf(RECEIVER) >= 1, "RECEIVER has not received any payment");
    //         assertTrue(realCostInPaymentToken >= 1, "real cost is 0, but should be at least 1");
    //         assertTrue(realCostInPaymentToken - naiveCostInPaymentToken >= 0, "real cost is less than advertised cost");
    //         assertTrue(realCostInPaymentToken - naiveCostInPaymentToken <= 1, "more than 1 currency bit was rounded!");
    //         assertTrue(realPrice >= _price, "real PRICE is less than advertised");
    //     }

    //     function testBuyAnyAmountRoundsUp(uint tokenBuyAmount) public {
    //         vm.assume(tokenBuyAmount < crowdinvesting.maxAmountPerBuyer());
    //         vm.assume(tokenBuyAmount > 0);
    //         ensureRealCostIsHigherEqualAdvertisedCost(tokenBuyAmount);
    //     }

    //     function testBuy1BitRoundsUp() public {
    //         // this will result in the naive cost being 0
    //         ensureRealCostIsHigherEqualAdvertisedCost(1);
    //     }

    //     /*
    //         try to buy more than allowed
    //     */
    //     function testBuyMoreThanMaxAmountPerBuyer() public {
    //         vm.prank(BUYER);
    //         vm.expectRevert("Total amount of bought tokens needs to be lower than or equal to maxAmount");
    //         crowdinvesting.buy(MAX_AMOUNT_PER_BUYER + 1, type(uint256).max, BUYER);
    //     }

    //     /*
    //         try to buy less than allowed
    //     */
    //     function testBuyLessThanMinAmountPerBuyer() public {
    //         vm.prank(BUYER);
    //         vm.expectRevert("Buyer needs to buy at least minAmount");
    //         crowdinvesting.buy(MIN_AMOUNT_PER_BUYER - 1, type(uint256).max, BUYER);
    //     }

    //     /*
    //         try to buy while paused
    //     */
    //     function testBuyWhilePaused() public {
    //         vm.prank(OWNER);
    //         crowdinvesting.pause();
    //         vm.prank(BUYER);
    //         vm.expectRevert("Pausable: paused");
    //         crowdinvesting.buy(MIN_AMOUNT_PER_BUYER, type(uint256).max, BUYER);
    //     }

    //     /*
    //         try to update currencyReceiver not paused
    //     */
    //     function testUpdateCurrencyReceiverNotPaused() public {
    //         vm.prank(OWNER);
    //         vm.expectRevert("Pausable: not paused");
    //         crowdinvesting.setCurrencyReceiver(payable(address(BUYER)));
    //     }

    //     /*
    //         try to update currencyReceiver while paused
    //     */
    //     function testUpdateCurrencyReceiverPaused() public {
    //         assertTrue(crowdinvesting.currencyReceiver() == RECEIVER);
    //         vm.prank(OWNER);
    //         crowdinvesting.pause();
    //         vm.prank(OWNER);
    //         vm.expectEmit(true, true, true, true, address(crowdinvesting));
    //         emit CurrencyReceiverChanged(address(BUYER));
    //         crowdinvesting.setCurrencyReceiver(address(BUYER));
    //         assertTrue(crowdinvesting.currencyReceiver() == address(BUYER));

    //         vm.prank(OWNER);
    //         vm.expectRevert("RECEIVER can not be zero address");
    //         crowdinvesting.setCurrencyReceiver(address(0));
    //     }

    //     /*
    //         try to update MIN_AMOUNT_PER_BUYER not paused
    //     */
    //     function testUpdateMinAmountPerBuyerNotPaused() public {
    //         vm.prank(OWNER);
    //         vm.expectRevert("Pausable: not paused");
    //         crowdinvesting.setMinAmountPerBuyer(100);
    //     }

    //     /*
    //         try to update MIN_AMOUNT_PER_BUYER while paused
    //     */
    //     function testUpdateMinAmountPerBuyerPaused(uint256 newMinAmountPerBuyer) public {
    //         vm.assume(newMinAmountPerBuyer <= crowdinvesting.maxAmountPerBuyer());
    //         vm.assume(newMinAmountPerBuyer > 0);
    //         assertTrue(crowdinvesting.minAmountPerBuyer() == MIN_AMOUNT_PER_BUYER);
    //         vm.prank(OWNER);
    //         crowdinvesting.pause();
    //         vm.prank(OWNER);
    //         vm.expectEmit(true, true, true, true, address(crowdinvesting));
    //         emit MinAmountPerBuyerChanged(newMinAmountPerBuyer);
    //         crowdinvesting.setMinAmountPerBuyer(newMinAmountPerBuyer);
    //         assertTrue(crowdinvesting.minAmountPerBuyer() == newMinAmountPerBuyer);

    //         uint256 _maxAmountPerBuyer = crowdinvesting.maxAmountPerBuyer();
    //         vm.expectRevert("_minAmount needs to be smaller or equal to maxAmount");
    //         vm.prank(OWNER);
    //         crowdinvesting.setMinAmountPerBuyer(_maxAmountPerBuyer + 1); //crowdinvesting.maxAmountPerBuyer() + 1);

    //         vm.expectRevert("_minAmountPerBuyer needs to be larger than zero");
    //         vm.prank(OWNER);
    //         crowdinvesting.setMinAmountPerBuyer(0); //crowdinvesting.maxAmountPerBuyer() + 1);

    //         console.log("minAmount: ", crowdinvesting.minAmountPerBuyer());
    //         console.log("maxAmount: ", crowdinvesting.maxAmountPerBuyer());
    //     }

    //     /*
    //         try to update MAX_AMOUNT_PER_BUYER not paused
    //     */
    //     function testUpdateMaxAmountPerBuyerNotPaused() public {
    //         vm.prank(OWNER);
    //         vm.expectRevert("Pausable: not paused");
    //         crowdinvesting.setMaxAmountPerBuyer(100);
    //     }

    //     /*
    //         try to update MAX_AMOUNT_PER_BUYER while paused
    //     */
    //     function testUpdateMaxAmountPerBuyerPaused(uint256 newMaxAmountPerBuyer) public {
    //         vm.assume(newMaxAmountPerBuyer >= crowdinvesting.minAmountPerBuyer());
    //         assertTrue(crowdinvesting.maxAmountPerBuyer() == MAX_AMOUNT_PER_BUYER);
    //         vm.prank(OWNER);
    //         crowdinvesting.pause();
    //         vm.prank(OWNER);
    //         vm.expectEmit(true, true, true, true, address(crowdinvesting));
    //         emit MaxAmountPerBuyerChanged(newMaxAmountPerBuyer);
    //         crowdinvesting.setMaxAmountPerBuyer(newMaxAmountPerBuyer);
    //         assertTrue(crowdinvesting.maxAmountPerBuyer() == newMaxAmountPerBuyer);
    //         uint256 _minAmountPerBuyer = crowdinvesting.minAmountPerBuyer();
    //         vm.expectRevert("_maxAmount needs to be larger or equal to minAmount");
    //         vm.prank(OWNER);
    //         crowdinvesting.setMaxAmountPerBuyer(_minAmountPerBuyer - 1);
    //     }

    //     /*
    //         try to update currency and PRICE while not paused
    //     */
    //     function testUpdateCurrencyAndPriceNotPaused() public {
    //         FakePaymentToken newPaymentToken = new FakePaymentToken(700, 3);
    //         vm.prank(OWNER);
    //         vm.expectRevert("Pausable: not paused");
    //         crowdinvesting.setCurrencyAndTokenPrice(newPaymentToken, 100);
    //     }

    //     /*
    //         try to update currency and PRICE while paused
    //     */
    //     function testUpdateCurrencyAndPricePaused(uint256 newPrice) public {
    //         vm.assume(newPrice > 0);
    //         assertTrue(crowdinvesting.priceBase() == PRICE);
    //         assertTrue(crowdinvesting.currency() == paymentToken);

    //         FakePaymentToken newPaymentToken = new FakePaymentToken(700, 3);
    //         vm.startPrank(OWNER);
    //         list.set(address(newPaymentToken), TRUSTED_CURRENCY);

    //         crowdinvesting.pause();
    //         vm.expectEmit(true, true, true, true, address(crowdinvesting));
    //         emit TokenPriceAndCurrencyChanged(newPrice, newPaymentToken);
    //         crowdinvesting.setCurrencyAndTokenPrice(newPaymentToken, newPrice);
    //         vm.stopPrank();

    //         assertTrue(crowdinvesting.priceBase() == newPrice);
    //         assertTrue(crowdinvesting.currency() == newPaymentToken);
    //         vm.prank(OWNER);
    //         vm.expectRevert("_tokenPrice needs to be a non-zero amount");
    //         crowdinvesting.setCurrencyAndTokenPrice(paymentToken, 0);
    //     }

    //     /*
    //         try to update MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD while not paused
    //     */
    //     function testUpdateMaxAmountOfTokenToBeSoldNotPaused() public {
    //         vm.prank(OWNER);
    //         vm.expectRevert("Pausable: not paused");
    //         crowdinvesting.setMaxAmountOfTokenToBeSold(123 * 10 ** 18);
    //     }

    //     /*
    //         try to update MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD while paused
    //     */
    //     function testUpdateMaxAmountOfTokenToBeSoldPaused(uint256 newMaxAmountOfTokenToBeSold) public {
    //         vm.assume(newMaxAmountOfTokenToBeSold > 0);
    //         assertTrue(crowdinvesting.maxAmountOfTokenToBeSold() == MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD);
    //         vm.prank(OWNER);
    //         crowdinvesting.pause();
    //         vm.prank(OWNER);
    //         vm.expectEmit(true, true, true, true, address(crowdinvesting));
    //         emit MaxAmountOfTokenToBeSoldChanged(newMaxAmountOfTokenToBeSold);
    //         crowdinvesting.setMaxAmountOfTokenToBeSold(newMaxAmountOfTokenToBeSold);
    //         assertTrue(crowdinvesting.maxAmountOfTokenToBeSold() == newMaxAmountOfTokenToBeSold);
    //         vm.prank(OWNER);
    //         vm.expectRevert("_maxAmountOfTokenToBeSold needs to be larger than zero");
    //         crowdinvesting.setMaxAmountOfTokenToBeSold(0);
    //     }

    //     /*
    //         try to unpause immediately after pausing
    //     */
    //     function testUnpauseImmediatelyAfterPausing() public {
    //         vm.prank(OWNER);
    //         crowdinvesting.pause();
    //         assertTrue(crowdinvesting.paused());
    //         vm.prank(OWNER);
    //         vm.expectRevert("There needs to be at minimum one day to change parameters");
    //         crowdinvesting.unpause();
    //     }

    //     /*
    //         try to unpause after delay has passed
    //     */
    //     function testUnpauseAfterDelay() public {
    //         uint256 time = block.timestamp;
    //         vm.warp(time);
    //         vm.prank(OWNER);
    //         crowdinvesting.pause();
    //         assertTrue(crowdinvesting.paused());
    //         vm.warp(time + crowdinvesting.DELAY());
    //         vm.prank(OWNER);
    //         crowdinvesting.unpause();
    //     }

    //     /*
    //         try to unpause after more than 1 day has passed
    //     */
    //     function testUnpauseAfterPause() public {
    //         uint256 time = 200 days;
    //         uint256 coolDownStart = crowdinvesting.coolDownStart();
    //         vm.warp(time);
    //         vm.prank(OWNER);
    //         crowdinvesting.pause();
    //         assertTrue(crowdinvesting.paused());
    //         assertTrue(crowdinvesting.coolDownStart() == coolDownStart, "coolDownStart should not change with pause");
    //         vm.warp(time + 1 seconds);
    //         vm.prank(OWNER);
    //         crowdinvesting.unpause();
    //     }

    //     /*
    //         try to unpause too soon after setMaxAmountOfTokenToBeSold
    //     */
    //     function testUnpauseTooSoonAfterSetMaxAmountOfTokenToBeSold(
    //         uint128 startTime,
    //         uint32 changeDelay,
    //         uint32 attemptUnpauseDelay
    //     ) public {
    //         uint256 unpauseDelay = 1 hours;
    //         vm.assume(startTime < type(uint128).max / 2);
    //         vm.assume(startTime > 0);
    //         vm.assume(changeDelay > 0);
    //         vm.assume(attemptUnpauseDelay > 0);
    //         vm.assume(attemptUnpauseDelay < unpauseDelay + changeDelay);

    //         vm.warp(startTime);
    //         vm.prank(OWNER);
    //         crowdinvesting.pause();
    //         assertTrue(crowdinvesting.paused(), "crowdinvesting should be paused");
    //         vm.warp(startTime + changeDelay);
    //         vm.prank(OWNER);
    //         crowdinvesting.setMaxAmountOfTokenToBeSold(700);
    //         assertTrue(
    //             crowdinvesting.coolDownStart() == startTime + changeDelay,
    //             "coolDownStart should be startTime + changeDelay"
    //         );
    //         vm.warp(startTime + attemptUnpauseDelay);
    //         vm.prank(OWNER);
    //         console.log("current time: ", block.timestamp);
    //         console.log("unpause at: ", startTime + changeDelay + unpauseDelay);
    //         vm.expectRevert("There needs to be at minimum one day to change parameters");
    //         crowdinvesting.unpause(); // must fail because of the parameter update
    //     }

    //     /*
    //         try to unpause after setMaxAmountOfTokenToBeSold
    //     */
    //     function testUnpauseAfterSetMaxAmountOfTokenToBeSold() public {
    //         uint256 time = block.timestamp;
    //         vm.warp(time);
    //         vm.prank(OWNER);
    //         crowdinvesting.pause();
    //         assertTrue(crowdinvesting.paused());
    //         vm.warp(time + 2 hours);
    //         vm.prank(OWNER);
    //         crowdinvesting.setMaxAmountOfTokenToBeSold(700);
    //         assertTrue(crowdinvesting.coolDownStart() == time + 2 hours);
    //         vm.warp(time + crowdinvesting.DELAY() + 2 hours + 1 seconds);
    //         vm.prank(OWNER);
    //         crowdinvesting.unpause();
    //     }

    //     /*
    //         try to unpause too soon after setCurrencyReceiver
    //     */
    //     function testUnpauseTooSoonAfterSetCurrencyReceiver(
    //         uint128 startTime,
    //         uint32 changeDelay,
    //         uint32 attemptUnpauseDelay,
    //         address newCurrencyReceiver
    //     ) public {
    //         uint256 unpauseDelay = crowdinvesting.DELAY();
    //         vm.assume(startTime < type(uint128).max / 2);
    //         vm.assume(startTime > 0);
    //         vm.assume(changeDelay > 0);
    //         vm.assume(attemptUnpauseDelay > 0);
    //         vm.assume(attemptUnpauseDelay < unpauseDelay + changeDelay);
    //         vm.assume(newCurrencyReceiver != address(0));

    //         vm.warp(startTime);
    //         vm.prank(OWNER);
    //         crowdinvesting.pause();
    //         assertTrue(crowdinvesting.paused(), "crowdinvesting should be paused");
    //         vm.warp(startTime + changeDelay);
    //         vm.prank(OWNER);
    //         crowdinvesting.setCurrencyReceiver(newCurrencyReceiver);
    //         assertTrue(
    //             crowdinvesting.coolDownStart() == startTime + changeDelay,
    //             "coolDownStart should be startTime + changeDelay"
    //         );
    //         vm.warp(startTime + attemptUnpauseDelay);
    //         vm.prank(OWNER);
    //         console.log("current time: ", block.timestamp);
    //         console.log("unpause at: ", startTime + changeDelay + unpauseDelay);
    //         vm.expectRevert("There needs to be at minimum one day to change parameters");
    //         crowdinvesting.unpause(); // must fail because of the parameter update
    //     }

    //     /*
    //         try to unpause after setCurrencyReceiver
    //     */
    //     function testUnpauseAfterSetCurrencyReceiver() public {
    //         uint256 time = block.timestamp;
    //         vm.warp(time);
    //         vm.prank(OWNER);
    //         crowdinvesting.pause();
    //         assertTrue(crowdinvesting.paused());
    //         vm.warp(time + 2 hours);
    //         vm.prank(OWNER);
    //         crowdinvesting.setCurrencyReceiver(PAYMENT_TOKEN_PROVIDER);
    //         assertTrue(crowdinvesting.coolDownStart() == time + 2 hours);
    //         vm.warp(time + crowdinvesting.DELAY() + 2 hours + 1 seconds);
    //         vm.prank(OWNER);
    //         crowdinvesting.unpause();
    //     }

    //     /*
    //         try to unpause too soon after setMinAmountPerBuyer
    //     */
    //     function testUnpauseTooSoonAfterSetMinAmountPerBuyer(
    //         uint128 startTime,
    //         uint32 changeDelay,
    //         uint32 attemptUnpauseDelay,
    //         uint256 newMinAmountPerBuyer
    //     ) public {
    //         uint256 unpauseDelay = crowdinvesting.DELAY();
    //         vm.assume(startTime < type(uint128).max / 2);
    //         vm.assume(startTime > 0);
    //         vm.assume(changeDelay > 0);
    //         vm.assume(attemptUnpauseDelay > 0);
    //         vm.assume(attemptUnpauseDelay < unpauseDelay + changeDelay);
    //         vm.assume(newMinAmountPerBuyer > 0);
    //         vm.assume(newMinAmountPerBuyer <= crowdinvesting.maxAmountPerBuyer());

    //         vm.warp(startTime);
    //         vm.prank(OWNER);
    //         crowdinvesting.pause();
    //         assertTrue(crowdinvesting.paused(), "crowdinvesting should be paused");
    //         vm.warp(startTime + changeDelay);
    //         vm.prank(OWNER);
    //         crowdinvesting.setMinAmountPerBuyer(newMinAmountPerBuyer);
    //         assertTrue(
    //             crowdinvesting.coolDownStart() == startTime + changeDelay,
    //             "coolDownStart should be startTime + changeDelay"
    //         );
    //         vm.warp(startTime + attemptUnpauseDelay);
    //         vm.prank(OWNER);
    //         console.log("current time: ", block.timestamp);
    //         console.log("unpause at: ", startTime + changeDelay + unpauseDelay);
    //         vm.expectRevert("There needs to be at minimum one day to change parameters");
    //         crowdinvesting.unpause(); // must fail because of the parameter update
    //     }

    //     /*
    //         try to unpause after setMinAmountPerBuyer
    //     */
    //     function testUnpauseAfterSetMinAmountPerBuyer() public {
    //         uint256 time = block.timestamp;
    //         vm.warp(time);
    //         vm.prank(OWNER);
    //         crowdinvesting.pause();
    //         assertTrue(crowdinvesting.paused());
    //         vm.warp(time + 2 hours);
    //         vm.prank(OWNER);
    //         crowdinvesting.setMinAmountPerBuyer(700);
    //         assertTrue(crowdinvesting.coolDownStart() == time + 2 hours);
    //         vm.warp(time + crowdinvesting.DELAY() + 2 hours + 1 seconds);
    //         vm.prank(OWNER);
    //         crowdinvesting.unpause();
    //     }

    //     /*
    //         try to unpause too soon after setMaxAmountPerBuyer
    //     */
    //     function testUnpauseTooSoonAfterSetMaxAmountPerBuyer(
    //         uint128 startTime,
    //         uint32 changeDelay,
    //         uint32 attemptUnpauseDelay,
    //         uint256 newMaxAmountPerBuyer
    //     ) public {
    //         uint256 unpauseDelay = crowdinvesting.DELAY();
    //         vm.assume(startTime < type(uint128).max / 2);
    //         vm.assume(startTime > 0);
    //         vm.assume(changeDelay > 0);
    //         vm.assume(attemptUnpauseDelay > 0);
    //         vm.assume(attemptUnpauseDelay < unpauseDelay + changeDelay);
    //         vm.assume(newMaxAmountPerBuyer >= crowdinvesting.minAmountPerBuyer());

    //         vm.warp(startTime);
    //         vm.prank(OWNER);
    //         crowdinvesting.pause();
    //         assertTrue(crowdinvesting.paused(), "crowdinvesting should be paused");
    //         vm.warp(startTime + changeDelay);
    //         vm.prank(OWNER);
    //         crowdinvesting.setMaxAmountPerBuyer(newMaxAmountPerBuyer);
    //         assertTrue(
    //             crowdinvesting.coolDownStart() == startTime + changeDelay,
    //             "coolDownStart should be startTime + changeDelay"
    //         );
    //         vm.warp(startTime + attemptUnpauseDelay);
    //         vm.prank(OWNER);
    //         console.log("current time: ", block.timestamp);
    //         console.log("unpause at: ", startTime + changeDelay + unpauseDelay);
    //         vm.expectRevert("There needs to be at minimum one day to change parameters");
    //         crowdinvesting.unpause(); // must fail because of the parameter update
    //     }

    //     /*
    //         try to unpause after setMaxAmountPerBuyer
    //     */
    //     function testUnpauseAfterSetMaxAmountPerBuyer() public {
    //         uint256 time = block.timestamp;
    //         vm.warp(time);
    //         vm.prank(OWNER);
    //         crowdinvesting.pause();
    //         assertTrue(crowdinvesting.paused());
    //         vm.warp(time + 2 hours);
    //         vm.prank(OWNER);
    //         crowdinvesting.setMaxAmountPerBuyer(2 * MIN_AMOUNT_PER_BUYER);
    //         assertTrue(crowdinvesting.coolDownStart() == time + 2 hours);
    //         vm.warp(time + crowdinvesting.DELAY() + 2 hours + 1 seconds);
    //         vm.prank(OWNER);
    //         crowdinvesting.unpause();
    //     }

    //     /*
    //         try to unpause too soon after setCurrencyAndTokenPrice
    //     */
    //     function testUnpauseTooSoonAfterSetCurrencyAndTokenPrice(
    //         uint128 startTime,
    //         uint32 changeDelay,
    //         uint32 attemptUnpauseDelay,
    //         uint256 newTokenPrice
    //     ) public {
    //         uint256 unpauseDelay = crowdinvesting.DELAY();
    //         vm.assume(startTime < type(uint128).max / 2);
    //         vm.assume(startTime > 0);
    //         vm.assume(changeDelay > 0);
    //         vm.assume(attemptUnpauseDelay > 0);
    //         vm.assume(attemptUnpauseDelay < unpauseDelay + changeDelay);
    //         vm.assume(newTokenPrice > 0);

    //         vm.warp(startTime);
    //         vm.prank(OWNER);
    //         crowdinvesting.pause();
    //         assertTrue(crowdinvesting.paused(), "crowdinvesting should be paused");
    //         vm.warp(startTime + changeDelay);
    //         vm.prank(OWNER);
    //         crowdinvesting.setCurrencyAndTokenPrice(paymentToken, newTokenPrice);
    //         assertTrue(
    //             crowdinvesting.coolDownStart() == startTime + changeDelay,
    //             "coolDownStart should be startTime + changeDelay"
    //         );
    //         vm.warp(startTime + attemptUnpauseDelay);
    //         vm.prank(OWNER);
    //         console.log("current time: ", block.timestamp);
    //         console.log("unpause at: ", startTime + changeDelay + unpauseDelay);
    //         vm.expectRevert("There needs to be at minimum one day to change parameters");
    //         crowdinvesting.unpause(); // must fail because of the parameter update
    //     }

    //     /*
    //         try to unpause after setCurrencyAndTokenPrice
    //     */
    //     function testUnpauseAfterSetCurrencyAndTokenPrice() public {
    //         uint256 time = block.timestamp;
    //         vm.warp(time);
    //         vm.prank(OWNER);
    //         crowdinvesting.pause();
    //         assertTrue(crowdinvesting.paused());
    //         vm.warp(time + 2 hours);
    //         vm.prank(OWNER);
    //         crowdinvesting.setCurrencyAndTokenPrice(paymentToken, 700);
    //         assertTrue(crowdinvesting.coolDownStart() == time + 2 hours);
    //         vm.warp(time + crowdinvesting.DELAY() + 2 hours + 1 seconds);
    //         vm.prank(OWNER);
    //         crowdinvesting.unpause();
    //     }

    //     function testRevertsOnOverflow(uint256 _tokenBuyAmount, uint256 _price) public {
    //         vm.assume(_tokenBuyAmount > 0);
    //         vm.assume(_price > 0);
    //         vm.assume(UINT256_MAX / _price < _tokenBuyAmount); // this will cause an overflow on multiplication

    //         // new currency
    //         // set up currency
    //         vm.prank(PAYMENT_TOKEN_PROVIDER);
    //         paymentToken = new FakePaymentToken(UINT256_MAX, PAYMENT_TOKEN_DECIMALS); // 1000 tokens with 6 decimals
    //         // transfer currency to BUYER
    //         vm.prank(PAYMENT_TOKEN_PROVIDER);
    //         paymentToken.transfer(BUYER, UINT256_MAX);

    //         vm.prank(OWNER);
    //         list.set(address(paymentToken), TRUSTED_CURRENCY);

    //         // create the crowdinvesting contract
    //         CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
    //             address(this),
    //             payable(RECEIVER),
    //             1,
    //             UINT256_MAX,
    //             _price,
    //             _price,
    //             _price,
    //             UINT256_MAX,
    //             paymentToken,
    //             token,
    //             0,
    //             address(0),
    //             address(0)
    //         );
    //         vm.prank(OWNER);
    //         crowdinvesting = Crowdinvesting(factory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, arguments));

    //         // grant allowances
    //         vm.prank(MINT_ALLOWER);
    //         token.increaseMintingAllowance(address(crowdinvesting), UINT256_MAX);
    //         vm.prank(BUYER);
    //         paymentToken.increaseAllowance(address(crowdinvesting), UINT256_MAX);

    //         vm.expectRevert(); //("Arithmetic over/underflow"); //("Division or modulo by 0");
    //         vm.prank(BUYER);
    //         crowdinvesting.buy(_tokenBuyAmount, type(uint256).max, BUYER);
    //     }

    //     function testSettingInvalidCurrencyReverts(address someCurrency, uint256 currencyAttributes) public {
    //         vm.assume(someCurrency != address(0));
    //         vm.assume(currencyAttributes != TRUSTED_CURRENCY);
    //         vm.prank(OWNER);
    //         list.set(someCurrency, currencyAttributes);

    //         vm.startPrank(OWNER);
    //         crowdinvesting.pause();
    //         vm.expectRevert("currency needs to be on the allowlist with TRUSTED_CURRENCY attribute");
    //         crowdinvesting.setCurrencyAndTokenPrice(IERC20(someCurrency), 1);

    //         // check the settings works when the currency is on the allowlist with TRUSTED_CURRENCY attribute
    //         list.set(someCurrency, TRUSTED_CURRENCY);
    //         crowdinvesting.setCurrencyAndTokenPrice(IERC20(someCurrency), 1);
    //     }

    //     function testRoundsUp(uint256 _tokenBuyAmount, uint256 _price) public {
    //         vm.assume(_tokenBuyAmount > 0);
    //         vm.assume(_price > 0);
    //         vm.assume(UINT256_MAX / _price > _tokenBuyAmount); // this will cause an overflow on multiplication

    //         uint256 tokenDecimals = token.decimals();
    //         uint minCurrencyAmount = (_tokenBuyAmount * _price) / 10 ** tokenDecimals;
    //         console.log("minCurrencyAmount: %s", minCurrencyAmount);
    //         uint maxCurrencyAmount = minCurrencyAmount + 1;
    //         console.log("maxCurrencyAmount: %s", maxCurrencyAmount);

    //         // new currency
    //         // set up currency
    //         vm.prank(PAYMENT_TOKEN_PROVIDER);
    //         paymentToken = new FakePaymentToken(maxCurrencyAmount, PAYMENT_TOKEN_DECIMALS); // 1000 tokens with 6 decimals
    //         // transfer currency to BUYER
    //         vm.prank(PAYMENT_TOKEN_PROVIDER);
    //         paymentToken.transfer(BUYER, maxCurrencyAmount);

    //         vm.prank(OWNER);
    //         list.set(address(paymentToken), TRUSTED_CURRENCY);

    //         // create the crowdinvesting contract
    //         CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
    //             address(this),
    //             payable(RECEIVER),
    //             _tokenBuyAmount,
    //             _tokenBuyAmount,
    //             _price,
    //             _price,
    //             _price,
    //             _tokenBuyAmount,
    //             paymentToken,
    //             token,
    //             0,
    //             address(0),
    //             address(0)
    //         );
    //         vm.prank(OWNER);
    //         crowdinvesting = Crowdinvesting(factory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, arguments));

    //         // set fees to 0, otherwise extra currency is minted which causes an overflow
    //         Fees memory fees = Fees(0, 0, 0, 0);
    //         FeeSettings(address(token.feeSettings())).planFeeChange(fees);
    //         FeeSettings(address(token.feeSettings())).executeFeeChange();

    //         // grant allowances
    //         vm.prank(MINT_ALLOWER);
    //         token.increaseMintingAllowance(address(crowdinvesting), _tokenBuyAmount);
    //         vm.prank(BUYER);
    //         paymentToken.increaseAllowance(address(crowdinvesting), maxCurrencyAmount);

    //         vm.prank(BUYER);
    //         crowdinvesting.buy(_tokenBuyAmount, type(uint256).max, BUYER);

    //         // check that the BUYER got the correct amount of tokens
    //         assertTrue(token.balanceOf(BUYER) == _tokenBuyAmount, "BUYER got wrong amount of tokens");
    //         // check that the crowdinvesting got the correct amount of currency
    //         assertTrue(
    //             paymentToken.balanceOf(RECEIVER) <= maxCurrencyAmount,
    //             "crowdinvesting got wrong amount of currency"
    //         );
    //         assertTrue(
    //             paymentToken.balanceOf(RECEIVER) >= minCurrencyAmount,
    //             "crowdinvesting got wrong amount of currency"
    //         );
    //     }

    //     function testTransferOwnership(address newOwner) public {
    //         vm.prank(OWNER);
    //         crowdinvesting.transferOwnership(newOwner);
    //         assertTrue(crowdinvesting.owner() == OWNER);

    //         vm.prank(newOwner);
    //         crowdinvesting.acceptOwnership();
    //         assertTrue(crowdinvesting.owner() == newOwner);
    //     }

    //     function testOfferExpiration(uint256 _lastBuyDate, uint256 testDate) public {
    //         vm.assume(testDate > 1 days + 1);
    //         vm.assume(testDate < 100 * 365 days);
    //         vm.assume(_lastBuyDate > 1);
    //         vm.assume(_lastBuyDate < 100 * 365 days);

    //         // because of limitations in the test suite, we have to decide on a fixed date to base our warping on
    //         uint256 startDate = 100 * 365 days;
    //         vm.warp(startDate);

    //         uint256 tokenBuyAmount = 5 * 10 ** token.decimals();
    //         uint256 costInPaymentToken = Math.ceilDiv(tokenBuyAmount * crowdinvesting.priceBase(), 10 ** 18);

    //         vm.startPrank(OWNER);
    //         crowdinvesting.pause();
    //         crowdinvesting.setLastBuyDate(startDate + _lastBuyDate);
    //         vm.warp(startDate + 1 days + 1);
    //         crowdinvesting.unpause();
    //         vm.stopPrank();

    //         vm.warp(startDate + testDate);

    //         // log block.timestamp and LAST_BUY_DATE
    //         console.log("block.timestamp: ", block.timestamp);
    //         console.log("LAST_BUY_DATE: ", _lastBuyDate);

    //         if (testDate > _lastBuyDate) {
    //             vm.expectRevert("Last buy date has passed: not selling tokens anymore.");
    //             vm.prank(BUYER);
    //             crowdinvesting.buy(tokenBuyAmount, type(uint256).max, BUYER);
    //         } else {
    //             vm.prank(BUYER);
    //             vm.expectEmit(true, true, true, true, address(crowdinvesting));
    //             emit TokensBought(BUYER, tokenBuyAmount, costInPaymentToken);
    //             crowdinvesting.buy(tokenBuyAmount, type(uint256).max, BUYER);
    //         }
    //     }

    //     function testLastBuyDateInConstructor(uint256 _lastBuyDate, uint256 testDate) public {
    //         vm.assume(_lastBuyDate > block.timestamp || _lastBuyDate == 0);
    //         CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
    //             address(this),
    //             payable(RECEIVER),
    //             MIN_AMOUNT_PER_BUYER,
    //             MAX_AMOUNT_PER_BUYER,
    //             PRICE,
    //             PRICE,
    //             PRICE,
    //             MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD,
    //             paymentToken,
    //             token,
    //             _lastBuyDate,
    //             address(0),
    //             address(0)
    //         );
    //         Crowdinvesting _crowdinvesting = Crowdinvesting(
    //             factory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, arguments)
    //         );

    //         vm.warp(testDate);

    //         uint256 tokenBuyAmount = 5 * 10 ** token.decimals();
    //         uint256 costInPaymentToken = Math.ceilDiv(tokenBuyAmount * crowdinvesting.priceBase(), 10 ** 18);

    //         // log test date, auto pause date and block.timestamp
    //         console.log("testDate: ", testDate);
    //         console.log("LAST_BUY_DATE: ", _lastBuyDate);
    //         console.log("block.timestamp: ", block.timestamp);

    //         if (_lastBuyDate != 0 && testDate > _lastBuyDate) {
    //             // auto-pause should trigger
    //             vm.startPrank(BUYER);
    //             paymentToken.approve(address(_crowdinvesting), type(uint256).max);
    //             vm.expectRevert("Last buy date has passed: not selling tokens anymore.");
    //             _crowdinvesting.buy(tokenBuyAmount, type(uint256).max, BUYER);
    //             vm.stopPrank();
    //         } else {
    //             // auto-pause should not trigger
    //             vm.prank(ADMIN);
    //             token.increaseMintingAllowance(address(_crowdinvesting), MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD);

    //             vm.startPrank(BUYER);
    //             paymentToken.approve(address(_crowdinvesting), type(uint256).max);
    //             vm.expectEmit(true, true, true, true, address(_crowdinvesting));
    //             emit TokensBought(BUYER, tokenBuyAmount, costInPaymentToken);
    //             _crowdinvesting.buy(tokenBuyAmount, type(uint256).max, BUYER);
    //             vm.stopPrank();
    //         }
    //     }
}
