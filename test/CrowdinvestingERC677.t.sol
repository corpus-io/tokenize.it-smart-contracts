// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/CrowdinvestingCloneFactory.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/MaliciousPaymentToken.sol";
import "./resources/FakeCrowdinvestingAndToken.sol";
import "./resources/CloneCreators.sol";

contract CrowdinvestingTest is Test {
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

    uint8 public constant PAYMENT_TOKEN_DECIMALS = 6;
    uint256 public constant PAYMENT_TOKEN_AMOUNT = 1000 * 10 ** PAYMENT_TOKEN_DECIMALS;

    uint256 public constant PRICE = 7 * 10 ** PAYMENT_TOKEN_DECIMALS; // 7 payment tokens per token

    uint256 public constant MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD = 20 * 10 ** 18; // 20 token
    uint256 public constant MAX_AMOUNT_PER_BUYER = MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 2; // 10 token
    uint256 public constant MIN_AMOUNT_PER_BUYER = MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 200; // 0.1 token

    function setUp() public {
        // set up currency
        vm.prank(PAYMENT_TOKEN_PROVIDER);
        paymentToken = new FakePaymentToken(PAYMENT_TOKEN_AMOUNT, PAYMENT_TOKEN_DECIMALS); // 1000 tokens with 6 decimals
        // transfer currency to BUYER
        vm.prank(PAYMENT_TOKEN_PROVIDER);
        paymentToken.transfer(BUYER, PAYMENT_TOKEN_AMOUNT);
        assertTrue(paymentToken.balanceOf(BUYER) == PAYMENT_TOKEN_AMOUNT);

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
            address(0)
        );

        crowdinvesting = Crowdinvesting(factory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, arguments));

        // allow crowdinvesting contract to mint
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(ADMIN);
        token.grantRole(roleMintAllower, MINT_ALLOWER);
        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(address(crowdinvesting), MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD);

        // give crowdinvesting contract allowance
        vm.prank(BUYER);
        paymentToken.approve(address(crowdinvesting), PAYMENT_TOKEN_AMOUNT);
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

        vm.prank(PAYMENT_TOKEN_PROVIDER);
        maliciousPaymentToken = new MaliciousPaymentToken(_paymentTokenAmount);

        list = createAllowList(TRUSTED_FORWARDER, OWNER);
        vm.prank(OWNER);
        list.set(address(maliciousPaymentToken), TRUSTED_CURRENCY);

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

        vm.prank(OWNER);

        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            OWNER,
            payable(RECEIVER),
            MIN_AMOUNT_PER_BUYER,
            MAX_AMOUNT_PER_BUYER,
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

        // run actual test
        assertTrue(maliciousPaymentToken.balanceOf(BUYER) == _paymentTokenAmount);
        uint256 buyAmount = _maxMintAmount / 100000;
        vm.prank(BUYER);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        _crowdinvesting.buy(buyAmount, type(uint256).max, BUYER);
    }

    function testERC677BuyHappyCase(uint256 tokenBuyAmount) public {
        // uint256 tokenBuyAmount = 10 ** token.decimals(); // buy one token
        vm.assume(tokenBuyAmount >= crowdinvesting.minAmountPerBuyer());
        vm.assume(tokenBuyAmount <= crowdinvesting.maxAmountPerBuyer());
        uint256 costInPaymentToken = Math.ceilDiv(tokenBuyAmount * crowdinvesting.priceBase(), 10 ** 18);
        vm.assume(costInPaymentToken <= paymentToken.balanceOf(BUYER));

        uint256 realTokenBuyAmount = (costInPaymentToken * 10 ** token.decimals()) / crowdinvesting.getPrice();

        // log tokenBuyAmount and costInPaymentToken and PRICE, realTokenBuyAmount
        console.log("tokenBuyAmount: ", tokenBuyAmount);
        console.log("costInPaymentToken: ", costInPaymentToken);
        console.log("tokenPrice: ", crowdinvesting.getPrice());
        console.log("realTokenBuyAmount: ", realTokenBuyAmount);
        // log PRICE from realTokenBuyAmount and costInPaymentToken
        console.log(
            "PRICE from realTokenBuyAmount and costInPaymentToken: ",
            (costInPaymentToken * 10 ** 18) / realTokenBuyAmount
        );

        uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(BUYER);

        FeeSettings localFeeSettings = FeeSettings(address(token.feeSettings()));

        vm.prank(BUYER);
        // vm.expectEmit(true, true, true, true, address(crowdinvesting));
        // emit TokensBought(BUYER, tokenBuyAmount, costInPaymentToken);
        paymentToken.transferAndCall(address(crowdinvesting), costInPaymentToken, new bytes(0));

        // log token holdings of BUYER
        console.log("BUYER token balance: ", token.balanceOf(BUYER));
        // log token buy amount
        console.log("tokenBuyAmount: ", tokenBuyAmount);

        assertTrue(paymentToken.balanceOf(BUYER) == paymentTokenBalanceBefore - costInPaymentToken, "BUYER has paid");
        assertTrue(token.balanceOf(BUYER) == realTokenBuyAmount, "BUYER has wrong token amount");

        FakeCrowdinvesting fakeCrowdinvesting = new FakeCrowdinvesting(address(token));

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
            token.balanceOf(FeeSettings(address(token.feeSettings())).tokenFeeCollector(address(token))) >=
                localFeeSettings.tokenFee(tokenBuyAmount),
            "fee collector has collected fee in tokens"
        );

        assertTrue(crowdinvesting.tokensSold() == realTokenBuyAmount, "crowdinvesting has sold wrong amount of tokens");
        assertTrue(
            crowdinvesting.tokensBought(BUYER) == realTokenBuyAmount,
            "crowdinvesting has stored wrong amount of tokens for BUYER"
        );
    }

    function testBuyTooMuch() public {
        uint256 tokenBuyAmount = MAX_AMOUNT_PER_BUYER + 1;
        uint256 costInPaymentToken = Math.ceilDiv(tokenBuyAmount * crowdinvesting.getPrice(), 10 ** token.decimals());

        uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(BUYER);

        vm.prank(BUYER);
        vm.expectRevert("Total amount of bought tokens needs to be lower than or equal to maxAmount");
        paymentToken.transferAndCall(address(crowdinvesting), costInPaymentToken, new bytes(0));
        assertTrue(paymentToken.balanceOf(BUYER) == paymentTokenBalanceBefore);
        assertTrue(token.balanceOf(BUYER) == 0);
        assertTrue(paymentToken.balanceOf(RECEIVER) == 0);
        assertTrue(crowdinvesting.tokensSold() == 0);
        assertTrue(crowdinvesting.tokensBought(BUYER) == 0);
    }

    function testBuyAndMintToDifferentAddress() public {
        address addressWithFunds = address(1);
        address addressForTokens = address(2);

        uint256 currencyAmount = PRICE; // buy one token
        uint256 tokenBuyAmount = (currencyAmount * 10 ** token.decimals()) / crowdinvesting.getPrice();

        vm.prank(BUYER);
        paymentToken.transfer(addressWithFunds, currencyAmount);

        vm.prank(addressWithFunds);
        paymentToken.approve(address(crowdinvesting), PAYMENT_TOKEN_AMOUNT);

        // check state before
        assertTrue(paymentToken.balanceOf(addressWithFunds) == currencyAmount, "addressWithFunds has no funds");
        assertTrue(paymentToken.balanceOf(addressForTokens) == 0, "addressForTokens has funds");
        assertTrue(token.balanceOf(addressForTokens) == 0, "addressForTokens has tokens before buy");
        assertTrue(token.balanceOf(addressWithFunds) == 0, "addressWithFunds has tokens before buy");

        // execute buy, with addressForTokens as recipient
        bytes memory data = abi.encode(addressForTokens);

        console.log("bytes lenght: ", data.length);

        vm.startPrank(addressWithFunds);
        paymentToken.transferAndCall(address(crowdinvesting), currencyAmount, data);
        vm.stopPrank();

        // log token holdings of addressForTokens
        console.log("addressForTokens token balance: ", token.balanceOf(addressForTokens));

        // check state after
        console.log("addressWithFunds balance: ", paymentToken.balanceOf(addressWithFunds));
        assertTrue(paymentToken.balanceOf(addressWithFunds) == 0, "addressWithFunds has funds after buy");
        assertTrue(paymentToken.balanceOf(addressForTokens) == 0, "addressForTokens has funds after buy");
        assertTrue(
            token.balanceOf(addressForTokens) == tokenBuyAmount,
            "addressForTokens has wrong amount of tokens after buy"
        );
    }

    function testBuyWithMinimumAmountDeliveredFuzzed(uint256 minTokenAmount) public {
        address addressWithFunds = address(1);
        address addressForTokens = address(2);

        uint256 currencyAmount = PRICE; // buy one token
        uint256 tokenBuyAmount = (currencyAmount * 10 ** token.decimals()) / crowdinvesting.getPrice();

        vm.prank(BUYER);
        paymentToken.transfer(addressWithFunds, currencyAmount);

        vm.prank(addressWithFunds);
        paymentToken.approve(address(crowdinvesting), PAYMENT_TOKEN_AMOUNT);

        // check state before
        assertTrue(paymentToken.balanceOf(addressWithFunds) == currencyAmount, "addressWithFunds has no funds");
        assertTrue(paymentToken.balanceOf(addressForTokens) == 0, "addressForTokens has funds");
        assertTrue(token.balanceOf(addressForTokens) == 0, "addressForTokens has tokens before buy");
        assertTrue(token.balanceOf(addressWithFunds) == 0, "addressWithFunds has tokens before buy");

        // execute buy, with addressForTokens as recipient
        bytes memory data = abi.encode(addressForTokens, minTokenAmount);

        console.log("bytes lenght: ", data.length);

        if (minTokenAmount <= tokenBuyAmount) {
            vm.startPrank(addressWithFunds);
            paymentToken.transferAndCall(address(crowdinvesting), currencyAmount, data);
            vm.stopPrank();

            // log token holdings of addressForTokens
            console.log("addressForTokens token balance: ", token.balanceOf(addressForTokens));

            // check state after
            console.log("addressWithFunds balance: ", paymentToken.balanceOf(addressWithFunds));
            assertTrue(paymentToken.balanceOf(addressWithFunds) == 0, "addressWithFunds has funds after buy");
            assertTrue(paymentToken.balanceOf(addressForTokens) == 0, "addressForTokens has funds after buy");
            assertTrue(
                token.balanceOf(addressForTokens) == tokenBuyAmount,
                "addressForTokens has wrong amount of tokens after buy"
            );
        } else {
            vm.startPrank(addressWithFunds);
            vm.expectRevert("Purchase yields less tokens than demanded.");
            paymentToken.transferAndCall(address(crowdinvesting), currencyAmount, data);
            vm.stopPrank();
        }
    }

    function testBuyWithMinimumAmountDelivered0() public {
        address addressWithFunds = address(1);
        address addressForTokens = address(2);

        uint256 currencyAmount = PRICE; // buy one token
        uint256 tokenBuyAmount = (currencyAmount * 10 ** token.decimals()) / crowdinvesting.getPrice();

        vm.prank(BUYER);
        paymentToken.transfer(addressWithFunds, currencyAmount);

        vm.prank(addressWithFunds);
        paymentToken.approve(address(crowdinvesting), PAYMENT_TOKEN_AMOUNT);

        // check state before
        assertTrue(paymentToken.balanceOf(addressWithFunds) == currencyAmount, "addressWithFunds has no funds");
        assertTrue(paymentToken.balanceOf(addressForTokens) == 0, "addressForTokens has funds");
        assertTrue(token.balanceOf(addressForTokens) == 0, "addressForTokens has tokens before buy");
        assertTrue(token.balanceOf(addressWithFunds) == 0, "addressWithFunds has tokens before buy");

        // execute buy, with addressForTokens as recipient
        bytes memory data = abi.encode(addressForTokens, 0);

        console.log("bytes lenght: ", data.length);

        vm.startPrank(addressWithFunds);
        paymentToken.transferAndCall(address(crowdinvesting), currencyAmount, data);
        vm.stopPrank();

        // log token holdings of addressForTokens
        console.log("addressForTokens token balance: ", token.balanceOf(addressForTokens));

        // check state after
        console.log("addressWithFunds balance: ", paymentToken.balanceOf(addressWithFunds));
        assertTrue(paymentToken.balanceOf(addressWithFunds) == 0, "addressWithFunds has funds after buy");
        assertTrue(paymentToken.balanceOf(addressForTokens) == 0, "addressForTokens has funds after buy");
        assertTrue(
            token.balanceOf(addressForTokens) == tokenBuyAmount,
            "addressForTokens has wrong amount of tokens after buy"
        );
    }

    function testBuyWithMinimumAmountDeliveredUint256Max() public {
        address addressWithFunds = address(1);
        address addressForTokens = address(2);

        uint256 currencyAmount = PRICE; // buy one token

        vm.prank(BUYER);
        paymentToken.transfer(addressWithFunds, currencyAmount);

        vm.prank(addressWithFunds);
        paymentToken.approve(address(crowdinvesting), PAYMENT_TOKEN_AMOUNT);

        // check state before
        assertTrue(paymentToken.balanceOf(addressWithFunds) == currencyAmount, "addressWithFunds has no funds");
        assertTrue(paymentToken.balanceOf(addressForTokens) == 0, "addressForTokens has funds");
        assertTrue(token.balanceOf(addressForTokens) == 0, "addressForTokens has tokens before buy");
        assertTrue(token.balanceOf(addressWithFunds) == 0, "addressWithFunds has tokens before buy");

        // execute buy, with addressForTokens as recipient
        bytes memory data = abi.encode(addressForTokens, type(uint256).max);

        vm.startPrank(addressWithFunds);
        vm.expectRevert("Purchase yields less tokens than demanded.");
        paymentToken.transferAndCall(address(crowdinvesting), currencyAmount, data);
        vm.stopPrank();
    }

    function testMultiplePeopleBuyTooMuch() public {
        address person1 = address(1);
        address person2 = address(2);

        uint256 amountToSpend = Math.ceilDiv(
            crowdinvesting.maxAmountOfTokenToBeSold() * crowdinvesting.getPrice(),
            10 ** token.decimals()
        ) / 2;

        vm.prank(BUYER);
        paymentToken.transfer(person1, amountToSpend);
        vm.prank(BUYER);
        paymentToken.transfer(person2, amountToSpend);

        vm.prank(BUYER);
        paymentToken.transferAndCall(address(crowdinvesting), amountToSpend, new bytes(0));
        vm.prank(person1);
        paymentToken.transferAndCall(address(crowdinvesting), amountToSpend, new bytes(0));
        vm.prank(person2);
        vm.expectRevert("Not enough tokens to sell left");
        paymentToken.transferAndCall(address(crowdinvesting), amountToSpend, new bytes(0));
    }

    function testMultipleAddressesBuyForOneReceiver() public {
        address person1 = vm.addr(1);
        address person2 = vm.addr(2);

        uint256 availableBalance = paymentToken.balanceOf(BUYER);

        vm.prank(BUYER);
        paymentToken.transfer(person1, availableBalance / 2);
        vm.prank(BUYER);
        paymentToken.transfer(person2, 10 ** 6);

        uint256 amountToPay = Math.ceilDiv(
            (MAX_AMOUNT_PER_BUYER / 2) * crowdinvesting.getPrice(),
            10 ** token.decimals()
        ) + 1;
        bytes memory data = abi.encode(BUYER);

        console.log("Buying first batch of tokens");

        vm.startPrank(BUYER);
        paymentToken.transferAndCall(address(crowdinvesting), amountToPay, data);
        vm.stopPrank();

        console.log("Buying second batch of tokens");

        vm.startPrank(person1);
        vm.expectRevert("Total amount of bought tokens needs to be lower than or equal to maxAmount");
        paymentToken.transferAndCall(address(crowdinvesting), amountToPay, data);
        vm.stopPrank();
    }

    function testCorrectAccounting() public {
        address person1 = address(1);

        uint256 availableBalance = paymentToken.balanceOf(BUYER);

        vm.prank(BUYER);
        paymentToken.transfer(person1, availableBalance / 2);

        uint256 tokenAmount1 = MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 2;
        uint256 tokenAmount2 = MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 4;

        // check all entries are 0 before
        assertTrue(crowdinvesting.tokensSold() == 0, "crowdinvesting has sold tokens");
        assertTrue(crowdinvesting.tokensBought(BUYER) == 0, "BUYER has bought tokens");
        assertTrue(crowdinvesting.tokensBought(person1) == 0, "person1 has bought tokens");

        vm.prank(BUYER);
        crowdinvesting.buy(tokenAmount1, type(uint256).max, BUYER);
        vm.prank(BUYER);
        crowdinvesting.buy(tokenAmount2, type(uint256).max, person1);

        // check all entries are correct after
        assertTrue(
            crowdinvesting.tokensSold() == tokenAmount1 + tokenAmount2,
            "crowdinvesting has sold wrong amount of tokens"
        );
        assertTrue(crowdinvesting.tokensBought(BUYER) == tokenAmount1);
        assertTrue(crowdinvesting.tokensBought(person1) == tokenAmount2);
        assertTrue(token.balanceOf(BUYER) == tokenAmount1);
        assertTrue(token.balanceOf(person1) == tokenAmount2);
    }

    function testBuyTooLittle() public {
        uint256 tokenBuyAmount = 5 * 10 ** token.decimals();
        uint256 costInPaymentToken = (tokenBuyAmount * PRICE) / 10 ** 18;

        assert(costInPaymentToken == 35 * 10 ** PAYMENT_TOKEN_DECIMALS); // 35 payment tokens, manually calculated

        uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(BUYER);

        uint256 currencyAmount = Math.ceilDiv(
            (MIN_AMOUNT_PER_BUYER / 2) * crowdinvesting.getPrice(),
            10 ** token.decimals()
        );

        vm.startPrank(BUYER);
        vm.expectRevert("Buyer needs to buy at least minAmount");
        paymentToken.transferAndCall(address(crowdinvesting), currencyAmount, new bytes(0));
        assertTrue(paymentToken.balanceOf(BUYER) == paymentTokenBalanceBefore);
        assertTrue(token.balanceOf(BUYER) == 0);
        assertTrue(paymentToken.balanceOf(RECEIVER) == 0);
        assertTrue(crowdinvesting.tokensSold() == 0);
        assertTrue(crowdinvesting.tokensBought(BUYER) == 0);
    }

    function testOnlyCurrencyContractCanCallOnTokenTransfer(address rando) public {
        vm.assume(rando != address(paymentToken));
        vm.prank(rando);
        vm.expectRevert("Only currency contract can call onTokenTransfer");
        crowdinvesting.onTokenTransfer(rando, 0, new bytes(0));
    }
}
