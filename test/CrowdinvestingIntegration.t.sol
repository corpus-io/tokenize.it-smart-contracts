// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/CrowdinvestingCloneFactory.sol";
import "../contracts/FeeSettings.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/MaliciousPaymentToken.sol";
import "./resources/CloneCreators.sol";

contract CrowdinvestingTest is Test {
    Crowdinvesting crowdinvesting;
    AllowList list;
    FeeSettings feeSettings;

    Token implementation = new Token(TRUSTED_FORWARDER);
    TokenProxyFactory tokenFactory = new TokenProxyFactory(address(implementation));
    Token token;
    FakePaymentToken paymentToken;
    CrowdinvestingCloneFactory fundraisingFactory;

    address public constant PLATFORM_ADMIN = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant INVESTOR = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant MINT_ALLOWER = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant MINTER = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant COMPANY_OWNER = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
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
        // transfer currency to buyer
        vm.prank(PAYMENT_TOKEN_PROVIDER);
        paymentToken.transfer(INVESTOR, PAYMENT_TOKEN_AMOUNT);
        assertTrue(paymentToken.balanceOf(INVESTOR) == PAYMENT_TOKEN_AMOUNT);

        list = createAllowList(TRUSTED_FORWARDER, PLATFORM_ADMIN);
        vm.prank(PLATFORM_ADMIN);
        list.set(address(paymentToken), TRUSTED_CURRENCY);

        feeSettings = createFeeSettings(
            TRUSTED_FORWARDER,
            PLATFORM_ADMIN,
            buildFeeTypes(100, 100, 100, PLATFORM_ADMIN, PLATFORM_ADMIN, PLATFORM_ADMIN)
        );
        vm.prank(PLATFORM_ADMIN);
        token = Token(
            tokenFactory.createTokenProxy(
                0,
                TRUSTED_FORWARDER,
                feeSettings,
                COMPANY_OWNER,
                list,
                0x0,
                "TESTTOKEN",
                "TEST"
            )
        );

        vm.prank(COMPANY_OWNER);

        fundraisingFactory = new CrowdinvestingCloneFactory(address(new Crowdinvesting(TRUSTED_FORWARDER)));

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
            address(0)
        );

        crowdinvesting = Crowdinvesting(fundraisingFactory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, arguments));

        // allow crowdinvesting contract to mint
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(COMPANY_OWNER);
        token.grantRole(roleMintAllower, MINT_ALLOWER);
        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(address(crowdinvesting), MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD);

        // give crowdinvesting contract allowance
        vm.prank(INVESTOR);
        paymentToken.approve(address(crowdinvesting), PAYMENT_TOKEN_AMOUNT);
    }

    /*
    set up with FakePaymentToken which has variable decimals to make sure that doesn't break anything
    */
    function feeCalculation(uint32 tokenFeeNumerator, uint32 crowdinvestingFeeNumerator) public {
        // apply fees for test
        uint64 activationDate = uint64(block.timestamp + 13 weeks);
        vm.prank(PLATFORM_ADMIN);
        feeSettings.planFeeChange(FeeTypes.TOKEN, tokenFeeNumerator, activationDate);
        vm.prank(PLATFORM_ADMIN);
        feeSettings.planFeeChange(FeeTypes.CROWDINVESTING, crowdinvestingFeeNumerator, activationDate);
        vm.prank(PLATFORM_ADMIN);
        feeSettings.planFeeChange(FeeTypes.PRIVATE_OFFER, crowdinvestingFeeNumerator, activationDate);
        vm.warp(activationDate + 1 seconds);
        vm.prank(PLATFORM_ADMIN);
        feeSettings.executeFeeChange(FeeTypes.TOKEN);
        vm.prank(PLATFORM_ADMIN);
        feeSettings.executeFeeChange(FeeTypes.CROWDINVESTING);
        vm.prank(PLATFORM_ADMIN);
        feeSettings.executeFeeChange(FeeTypes.PRIVATE_OFFER);

        uint8 _paymentTokenDecimals = 6;
        // uint8 _maxDecimals = 25;
        // for (
        //     uint8 _paymentTokenDecimals = 1;
        //     _paymentTokenDecimals < _maxDecimals;
        //     _paymentTokenDecimals++
        // ) {
        //uint8 _paymentTokenDecimals = 10;

        /*
        _paymentToken: 1 FPT = 10**_paymentTokenDecimals FPTbits (bit = smallest subunit of token)
        Token: 1 CT = 10**18 CTbits
        PRICE definition: 30FPT buy 1CT, but must be expressed in FPTbits/CT
        PRICE = 30 * 10**_paymentTokenDecimals
        */
        uint256 _price = 30 * 10 ** _paymentTokenDecimals;
        uint256 _maxMintAmount = 2 ** 256 - 1; // need maximum possible value because we are using a fake token with variable decimals
        uint256 _paymentTokenAmount = 1000 * 10 ** _paymentTokenDecimals;

        list = createAllowList(TRUSTED_FORWARDER, PLATFORM_ADMIN);
        Token _token = Token(
            tokenFactory.createTokenProxy(
                0,
                TRUSTED_FORWARDER,
                feeSettings,
                COMPANY_OWNER,
                list,
                0x0,
                "FEETESTTOKEN",
                "TEST"
            )
        );

        vm.prank(PAYMENT_TOKEN_PROVIDER);
        paymentToken = new FakePaymentToken(_paymentTokenAmount, _paymentTokenDecimals);
        vm.prank(PLATFORM_ADMIN);
        list.set(address(paymentToken), TRUSTED_CURRENCY);

        vm.prank(COMPANY_OWNER);
        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            address(this),
            payable(RECEIVER),
            1,
            _maxMintAmount / 100,
            _price,
            _price,
            _price,
            _maxMintAmount,
            paymentToken,
            _token,
            0,
            address(0),
            address(0)
        );

        Crowdinvesting _crowdinvesting = Crowdinvesting(
            fundraisingFactory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, arguments)
        );

        // allow invite contract to mint
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(COMPANY_OWNER);
        _token.grantRole(roleMintAllower, MINT_ALLOWER);
        vm.prank(MINT_ALLOWER);
        _token.increaseMintingAllowance(address(_crowdinvesting), _maxMintAmount);

        // mint _paymentToken for buyer
        vm.prank(PAYMENT_TOKEN_PROVIDER);
        paymentToken.transfer(INVESTOR, _paymentTokenAmount);
        assertTrue(paymentToken.balanceOf(INVESTOR) == _paymentTokenAmount);

        // give invite contract allowance
        vm.prank(INVESTOR);
        paymentToken.approve(address(_crowdinvesting), _paymentTokenAmount);

        // run actual test

        uint tokenAmount = 33 * 10 ** token.decimals();

        // buyer has 1k FPT
        assertTrue(paymentToken.balanceOf(INVESTOR) == _paymentTokenAmount);
        // they should be able to buy 33 CT for 999 FPT
        vm.prank(INVESTOR);
        _crowdinvesting.buy(tokenAmount, type(uint256).max, INVESTOR);
        // buyer should have 10 FPT left
        assertTrue(paymentToken.balanceOf(INVESTOR) == 10 * 10 ** _paymentTokenDecimals);
        // buyer should have the 33 CT they bought
        assertTrue(_token.balanceOf(INVESTOR) == tokenAmount, "buyer has wrong amount of token");
        // RECEIVER should have the 990 FPT that were paid, minus the fee

        uint currencyAmount = 990 * 10 ** _paymentTokenDecimals;
        uint256 currencyFee = FeeSettings(address(token.feeSettings())).crowdinvestingFee(
            currencyAmount,
            address(_token)
        );
        assertTrue(
            paymentToken.balanceOf(RECEIVER) == currencyAmount - currencyFee,
            "RECEIVER has wrong amount of currency"
        );
        // fee collector should have the token and currency fees
        assertEq(
            currencyFee,
            paymentToken.balanceOf(feeSettings.feeCollector()),
            "fee collector has wrong amount of currency"
        );
        assertEq(
            FeeSettings(address(token.feeSettings())).tokenFee(tokenAmount, address(_token)),
            _token.balanceOf(feeSettings.feeCollector()),
            "fee collector has wrong amount of token"
        );
    }

    function testFee0() public {
        feeCalculation(0, 0);
    }

    function testVariousFees(uint32 tokenFeeNumerator, uint32 privateOfferFeeNumerator) public {
        (uint32 maxTokenNumerator, ) = feeSettings.feeTypeConfigs(FeeTypes.TOKEN);
        (uint32 maxPrivateOfferNumerator, ) = feeSettings.feeTypeConfigs(FeeTypes.PRIVATE_OFFER);
        vm.assume(tokenFeeNumerator <= maxTokenNumerator);
        vm.assume(privateOfferFeeNumerator <= maxPrivateOfferNumerator);
        feeCalculation(tokenFeeNumerator, privateOfferFeeNumerator);
    }

    /*
    set up with FakePaymentToken which has variable decimals to make sure that doesn't break anything
    */
    function testVaryDecimals() public {
        uint8 _maxDecimals = 25;
        //FakePaymentToken paymentToken;

        for (uint8 _paymentTokenDecimals = 1; _paymentTokenDecimals < _maxDecimals; _paymentTokenDecimals++) {
            //uint8 _paymentTokenDecimals = 10;

            /*
            _paymentToken: 1 FPT = 10**_paymentTokenDecimals FPTbits (bit = smallest subunit of token)
            Token: 1 CT = 10**18 CTbits
            PRICE definition: 30FPT buy 1CT, but must be expressed in FPTbits/CT
            PRICE = 30 * 10**_paymentTokenDecimals
            */
            uint256 _price = 30 * 10 ** _paymentTokenDecimals;
            uint256 _maxMintAmount = 2 ** 256 - 1; // need maximum possible value because we are using a fake token with variable decimals
            uint256 _paymentTokenAmount = 1000 * 10 ** _paymentTokenDecimals;

            list = createAllowList(TRUSTED_FORWARDER, PLATFORM_ADMIN);
            Token _token = Token(
                tokenFactory.createTokenProxy(
                    0,
                    TRUSTED_FORWARDER,
                    feeSettings,
                    COMPANY_OWNER,
                    list,
                    0x0,
                    "DECIMALSTESTTOKEN",
                    "TEST"
                )
            );

            vm.prank(PAYMENT_TOKEN_PROVIDER);
            paymentToken = new FakePaymentToken(_paymentTokenAmount, _paymentTokenDecimals);
            vm.prank(PLATFORM_ADMIN);
            list.set(address(paymentToken), TRUSTED_CURRENCY);

            vm.prank(COMPANY_OWNER);

            CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
                address(this),
                payable(RECEIVER),
                1,
                _maxMintAmount / 100,
                _price,
                _price,
                _price,
                _maxMintAmount,
                paymentToken,
                _token,
                0,
                address(0),
                address(0)
            );

            Crowdinvesting _crowdinvesting = Crowdinvesting(
                fundraisingFactory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, arguments)
            );
            // allow invite contract to mint
            bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

            vm.prank(COMPANY_OWNER);
            _token.grantRole(roleMintAllower, MINT_ALLOWER);
            vm.prank(MINT_ALLOWER);
            _token.increaseMintingAllowance(address(_crowdinvesting), _maxMintAmount);

            // mint _paymentToken for buyer
            vm.prank(PAYMENT_TOKEN_PROVIDER);
            paymentToken.transfer(INVESTOR, _paymentTokenAmount);
            assertTrue(paymentToken.balanceOf(INVESTOR) == _paymentTokenAmount);

            // give invite contract allowance
            vm.prank(INVESTOR);
            paymentToken.approve(address(_crowdinvesting), _paymentTokenAmount);

            // run actual test

            uint tokenAmount = 33 * 10 ** token.decimals();

            // buyer has 1k FPT
            assertTrue(paymentToken.balanceOf(INVESTOR) == _paymentTokenAmount);
            // they should be able to buy 33 CT for 999 FPT
            vm.prank(INVESTOR);
            _crowdinvesting.buy(tokenAmount, type(uint256).max, INVESTOR);
            // buyer should have 10 FPT left
            assertTrue(paymentToken.balanceOf(INVESTOR) == 10 * 10 ** _paymentTokenDecimals);
            // buyer should have the 33 CT they bought
            assertTrue(_token.balanceOf(INVESTOR) == tokenAmount, "buyer has wrong amount of token");
            // RECEIVER should have the 990 FPT that were paid, minus the fee
            uint currencyAmount = 990 * 10 ** _paymentTokenDecimals;
            uint256 currencyFee = FeeSettings(address(token.feeSettings())).crowdinvestingFee(
                currencyAmount,
                address(_token)
            );
            assertTrue(
                paymentToken.balanceOf(RECEIVER) == currencyAmount - currencyFee,
                "RECEIVER has wrong amount of currency"
            );
            // fee collector should have the token and currency fees
            assertEq(
                currencyFee,
                paymentToken.balanceOf(feeSettings.feeCollector()),
                "fee collector has wrong amount of currency"
            );
            assertEq(
                FeeSettings(address(token.feeSettings())).tokenFee(tokenAmount, address(_token)),
                _token.balanceOf(feeSettings.feeCollector()),
                "fee collector has wrong amount of token"
            );
        }
    }
}
