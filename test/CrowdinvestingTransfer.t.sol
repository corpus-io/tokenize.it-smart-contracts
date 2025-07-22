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
    event TokensBought(address indexed buyer, uint256 tokenAmount, uint256 currencyAmount);
    event TokenHolderChanged(address tokenHolder);

    CrowdinvestingCloneFactory factory;
    Crowdinvesting crowdinvesting;
    AllowList list;
    IFeeSettingsV2 feeSettings;

    address wrongFeeReceiver = address(5);

    TokenProxyFactory tokenCloneFactory;
    Token token;
    FakePaymentToken paymentToken;

    MaliciousPaymentToken maliciousPaymentToken;

    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant buyer = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant mintAllower = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant minter = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant owner = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant receiver = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant paymentTokenProvider = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant trustedForwarder = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;
    address public constant tokenHolder = 0xa109709ecfA91A80626ff3989D68F67F5b1dD12a;

    uint8 public constant paymentTokenDecimals = 6;
    uint256 public constant paymentTokenAmount = 1000 * 10 ** paymentTokenDecimals;

    uint256 public constant price = 7 * 10 ** paymentTokenDecimals; // 7 payment tokens per token

    uint256 public constant maxAmountOfTokenToBeSold = 20 * 10 ** 18; // 20 token
    uint256 public constant maxAmountPerBuyer = maxAmountOfTokenToBeSold / 2; // 10 token
    uint256 public constant minAmountPerBuyer = maxAmountOfTokenToBeSold / 200; // 0.1 token

    uint256 public constant lastBuyDate = 12859023;

    function setUp() public {
        // set up currency
        vm.prank(paymentTokenProvider);
        paymentToken = new FakePaymentToken(paymentTokenAmount, paymentTokenDecimals); // 1000 tokens with 6 decimals
        // transfer currency to buyer
        vm.prank(paymentTokenProvider);
        paymentToken.transfer(buyer, paymentTokenAmount);
        assertTrue(paymentToken.balanceOf(buyer) == paymentTokenAmount);

        list = createAllowList(trustedForwarder, owner);
        vm.startPrank(owner);
        list.set(address(paymentToken), TRUSTED_CURRENCY);
        list.set(tokenHolder, 0x0);
        vm.stopPrank();

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

        vm.prank(owner);
        factory = new CrowdinvestingCloneFactory(address(new Crowdinvesting(trustedForwarder)));
        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            owner,
            payable(receiver),
            minAmountPerBuyer,
            maxAmountPerBuyer,
            price,
            price,
            price,
            maxAmountOfTokenToBeSold,
            paymentToken,
            token,
            0,
            address(0),
            tokenHolder
        );
        crowdinvesting = Crowdinvesting(factory.createCrowdinvestingClone(0, trustedForwarder, arguments));

        // allow crowdinvesting contract to mint
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(admin);
        token.grantRole(roleMintAllower, mintAllower);
        vm.prank(mintAllower);
        token.increaseMintingAllowance(address(admin), maxAmountOfTokenToBeSold);
        vm.prank(admin);
        token.mint(tokenHolder, maxAmountOfTokenToBeSold);
        vm.stopPrank();

        // give token holder allowance to crowdinvesting contract
        vm.startPrank(tokenHolder);
        token.approve(address(crowdinvesting), maxAmountOfTokenToBeSold);
        vm.stopPrank();

        // give crowdinvesting contract currency allowance
        vm.prank(buyer);
        paymentToken.approve(address(crowdinvesting), paymentTokenAmount);
    }

    function testLogicContractCreation() public {
        Crowdinvesting _logic = new Crowdinvesting(address(1));

        console.log("address of logic contract: ", address(_logic));

        // try to initialize
        vm.expectRevert("Initializable: contract is already initialized");
        _logic.initialize(
            CrowdinvestingInitializerArguments(
                address(this),
                payable(receiver),
                minAmountPerBuyer,
                maxAmountPerBuyer,
                price,
                price,
                price,
                maxAmountOfTokenToBeSold,
                paymentToken,
                token,
                0,
                address(0),
                tokenHolder
            )
        );

        // owner and all settings are 0
        assertTrue(_logic.owner() == address(0), "owner is not 0");
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
            payable(receiver),
            minAmountPerBuyer,
            maxAmountPerBuyer,
            price,
            price,
            price,
            maxAmountOfTokenToBeSold,
            paymentToken,
            token,
            lastBuyDate,
            address(0),
            tokenHolder
        );
        Crowdinvesting _crowdinvesting = Crowdinvesting(
            factory.createCrowdinvestingClone(0, trustedForwarder, arguments)
        );
        assertTrue(_crowdinvesting.owner() == address(this));
        assertTrue(_crowdinvesting.currencyReceiver() == receiver);
        assertTrue(_crowdinvesting.minAmountPerBuyer() == minAmountPerBuyer);
        assertTrue(_crowdinvesting.maxAmountPerBuyer() == maxAmountPerBuyer);
        assertTrue(_crowdinvesting.maxAmountOfTokenToBeSold() == maxAmountOfTokenToBeSold);
        assertTrue(_crowdinvesting.priceBase() == price);
        assertTrue(_crowdinvesting.currency() == paymentToken);
        assertTrue(_crowdinvesting.token() == token);
        assertTrue(_crowdinvesting.lastBuyDate() == lastBuyDate);
        assertTrue(address(_crowdinvesting.tokenHolder()) == tokenHolder);
    }

    function testConstructorWithBadArguments() public {
        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            address(this),
            payable(receiver),
            minAmountPerBuyer,
            maxAmountPerBuyer,
            price,
            price,
            price,
            maxAmountOfTokenToBeSold,
            paymentToken,
            token,
            0,
            address(0),
            tokenHolder
        );
        vm.expectRevert("CrowdinvestingCloneFactory: Unexpected trustedForwarder");
        Crowdinvesting(factory.createCrowdinvestingClone(0, address(0), arguments));

        // owner 0
        CrowdinvestingInitializerArguments memory tempArgs = cloneCrowdinvestingInitializerArguments(arguments);
        tempArgs.owner = address(0);
        vm.expectRevert("owner can not be zero address");
        factory.createCrowdinvestingClone(0, trustedForwarder, tempArgs);

        // receiver 0
        tempArgs = cloneCrowdinvestingInitializerArguments(arguments);
        tempArgs.currencyReceiver = address(0);
        vm.expectRevert("currencyReceiver can not be zero address");
        factory.createCrowdinvestingClone(0, trustedForwarder, tempArgs);

        // token minAmount > maxAmountPerBuyer
        tempArgs = cloneCrowdinvestingInitializerArguments(arguments);
        tempArgs.minAmountPerBuyer = maxAmountPerBuyer + 1;
        vm.expectRevert("_minAmountPerBuyer needs to be smaller or equal to _maxAmountPerBuyer");
        factory.createCrowdinvestingClone(0, trustedForwarder, tempArgs);

        // token minAmount 0
        tempArgs = cloneCrowdinvestingInitializerArguments(arguments);
        tempArgs.minAmountPerBuyer = 0;
        vm.expectRevert("_minAmountPerBuyer needs to be larger than zero");
        factory.createCrowdinvestingClone(0, trustedForwarder, tempArgs);

        // price 0
        tempArgs = cloneCrowdinvestingInitializerArguments(arguments);
        tempArgs.tokenPrice = 0;
        vm.expectRevert("_tokenPrice needs to be a non-zero amount");
        factory.createCrowdinvestingClone(0, trustedForwarder, tempArgs);

        // max price 0
        tempArgs = cloneCrowdinvestingInitializerArguments(arguments);
        tempArgs.priceMax = 0;
        tempArgs.priceOracle = address(3);
        vm.expectRevert("priceMax needs to be larger or equal to priceBase");
        factory.createCrowdinvestingClone(0, trustedForwarder, tempArgs);

        // min price too high
        tempArgs.priceMax = price;
        tempArgs.priceMin = price + 1;
        vm.expectRevert("priceMin needs to be smaller or equal to priceBase");
        factory.createCrowdinvestingClone(0, trustedForwarder, tempArgs);

        // token maxAmountToBeSold 0
        tempArgs = cloneCrowdinvestingInitializerArguments(arguments);
        tempArgs.maxAmountOfTokenToBeSold = 0;
        vm.expectRevert("_maxAmountOfTokenToBeSold needs to be larger than zero");
        factory.createCrowdinvestingClone(0, trustedForwarder, tempArgs);

        // currency 0
        tempArgs = cloneCrowdinvestingInitializerArguments(arguments);
        tempArgs.currency = IERC20(address(0));
        vm.expectRevert("currency can not be zero address");
        factory.createCrowdinvestingClone(0, trustedForwarder, tempArgs);

        // token 0
        tempArgs = cloneCrowdinvestingInitializerArguments(arguments);
        tempArgs.token = Token(address(0));
        vm.expectRevert("token can not be zero address");
        factory.createCrowdinvestingClone(0, trustedForwarder, tempArgs);

        // tokenHolder 0 -> this should not revert, as it is allowed to set tokenHolder to 0
        tempArgs = cloneCrowdinvestingInitializerArguments(arguments);
        tempArgs.tokenHolder = address(0);
        factory.createCrowdinvestingClone(0, trustedForwarder, tempArgs);
    }

    /*
    set up with MaliciousPaymentToken which tries to reenter the buy function
    */
    function testReentrancy() public {
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
        vm.prank(paymentTokenProvider);
        maliciousPaymentToken = new MaliciousPaymentToken(_paymentTokenAmount);
        vm.prank(owner);
        list.set(address(maliciousPaymentToken), TRUSTED_CURRENCY);

        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            address(this),
            payable(receiver),
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
            factory.createCrowdinvestingClone(0, trustedForwarder, arguments)
        );

        // allow invite contract to mint
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(admin);
        _token.grantRole(roleMintAllower, mintAllower);
        vm.startPrank(mintAllower);
        _token.increaseMintingAllowance(
            address(_crowdinvesting),
            _maxMintAmount - token.mintingAllowance(address(_crowdinvesting))
        );
        vm.stopPrank();

        // mint _paymentToken for buyer
        vm.prank(paymentTokenProvider);
        maliciousPaymentToken.transfer(buyer, _paymentTokenAmount);
        assertTrue(maliciousPaymentToken.balanceOf(buyer) == _paymentTokenAmount);

        // set exploitTarget
        maliciousPaymentToken.setExploitTarget(address(_crowdinvesting), 3, _maxMintAmount / 200000);

        // give invite contract allowance
        vm.prank(buyer);
        maliciousPaymentToken.approve(address(_crowdinvesting), _paymentTokenAmount);

        // store some state
        //uint buyerPaymentBalanceBefore = _paymentToken.balanceOf(buyer);

        // run actual test
        assertTrue(maliciousPaymentToken.balanceOf(buyer) == _paymentTokenAmount);
        uint256 buyAmount = _maxMintAmount / 100000;
        vm.prank(buyer);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        _crowdinvesting.buy(buyAmount, type(uint256).max, buyer);
    }

    function testBuyTransferHappyCase(uint256 tokenBuyAmount) public {
        vm.assume(tokenBuyAmount >= crowdinvesting.minAmountPerBuyer());
        vm.assume(tokenBuyAmount <= crowdinvesting.maxAmountPerBuyer());
        uint256 costInPaymentToken = Math.ceilDiv(tokenBuyAmount * crowdinvesting.priceBase(), 10 ** 18);
        vm.assume(costInPaymentToken <= paymentToken.balanceOf(buyer));

        uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(buyer);

        FakeCrowdinvesting fakeCrowdinvesting = new FakeCrowdinvesting(address(token));

        // check state is correct before buy
        assertTrue(token.balanceOf(tokenHolder) == maxAmountOfTokenToBeSold, "tokenHolder has tokens");
        assertTrue(token.balanceOf(buyer) == 0, "buyer has no tokens");
        assertTrue(paymentToken.balanceOf(receiver) == 0, "receiver has no payment tokens");
        assertTrue(crowdinvesting.tokensSold() == 0, "crowdinvesting has sold no tokens");
        assertTrue(crowdinvesting.tokensBought(buyer) == 0, "crowdinvesting has sold no tokens to buyer");
        uint256 feeCollectorTokenBalanceBefore = token.balanceOf(
            FeeSettings(address(token.feeSettings())).tokenFeeCollector(address(token))
        );
        uint256 feeCollectorPaymentTokenBalanceBefore = paymentToken.balanceOf(
            FeeSettings(address(token.feeSettings())).crowdinvestingFeeCollector(address(token))
        );
        assertEq(feeCollectorPaymentTokenBalanceBefore, 0, "fee collector has payment tokens before buy");

        vm.prank(buyer);
        vm.expectEmit(true, true, true, true, address(crowdinvesting));
        emit TokensBought(buyer, tokenBuyAmount, costInPaymentToken);
        crowdinvesting.buy(tokenBuyAmount, type(uint256).max, buyer);
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
        assertTrue(
            token.balanceOf(FeeSettings(address(token.feeSettings())).tokenFeeCollector(address(token))) ==
                feeCollectorTokenBalanceBefore,
            "fee collector has collected additional fee in tokens"
        );
        assertTrue(
            token.balanceOf(tokenHolder) == maxAmountOfTokenToBeSold - tokenBuyAmount,
            "tokenHolder has wrong amount of tokens"
        );
        assertTrue(crowdinvesting.tokensSold() == tokenBuyAmount, "crowdinvesting has sold tokens");
        assertTrue(crowdinvesting.tokensBought(buyer) == tokenBuyAmount, "crowdinvesting has sold tokens to buyer");
    }

    function testSwitchToMintAndBuy(uint256 tokenBuyAmount) public {
        vm.assume(tokenBuyAmount >= crowdinvesting.minAmountPerBuyer());
        vm.assume(tokenBuyAmount <= crowdinvesting.maxAmountPerBuyer());
        uint256 costInPaymentToken = Math.ceilDiv(tokenBuyAmount * crowdinvesting.priceBase(), 10 ** 18);
        vm.assume(costInPaymentToken <= paymentToken.balanceOf(buyer));

        // Step 1: Set tokenHolder to 0
        vm.prank(owner);
        crowdinvesting.pause();
        vm.prank(owner);
        vm.expectEmit(true, true, true, true, address(crowdinvesting));
        emit TokenHolderChanged(address(0));
        crowdinvesting.setTokenHolder(address(0));
        assertTrue(crowdinvesting.tokenHolder() == address(0), "tokenHolder should be set to 0");
        vm.warp(block.timestamp + crowdinvesting.delay() + 1);
        vm.prank(owner);
        crowdinvesting.unpause();

        // Ensure minting allowance for crowdinvesting contract
        vm.prank(mintAllower);
        token.increaseMintingAllowance(address(crowdinvesting), tokenBuyAmount);

        // Store initial state
        uint256 initialTotalSupply = token.totalSupply();
        uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(buyer);
        uint256 initialReceiverBalance = paymentToken.balanceOf(receiver);
        uint256 initialTokensSold = crowdinvesting.tokensSold();
        uint256 initialTokensBoughtByBuyer = crowdinvesting.tokensBought(buyer);

        // Step 2: Buy tokens
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true, address(crowdinvesting));
        emit TokensBought(buyer, tokenBuyAmount, costInPaymentToken);
        crowdinvesting.buy(tokenBuyAmount, type(uint256).max, buyer);

        // Step 3: Check that new tokens have been minted
        assertTrue(token.balanceOf(buyer) == tokenBuyAmount, "buyer should have received tokens");
        assertTrue(
            token.totalSupply() ==
                initialTotalSupply + tokenBuyAmount + token.feeSettings().tokenFee(tokenBuyAmount, address(token)),
            "correct number of new tokens should have been minted"
        );
        assertTrue(
            paymentToken.balanceOf(buyer) == paymentTokenBalanceBefore - costInPaymentToken,
            "buyer should have paid"
        );
        assertTrue(
            paymentToken.balanceOf(receiver) >= initialReceiverBalance,
            "receiver should have received payment tokens"
        );
        assertTrue(crowdinvesting.tokensSold() == initialTokensSold + tokenBuyAmount, "tokensSold should be updated");
        assertTrue(
            crowdinvesting.tokensBought(buyer) == initialTokensBoughtByBuyer + tokenBuyAmount,
            "tokensBought for buyer should be updated"
        );
        assertTrue(
            token.balanceOf(tokenHolder) == maxAmountOfTokenToBeSold,
            "tokenHolder balance should remain unchanged"
        );
    }
}
