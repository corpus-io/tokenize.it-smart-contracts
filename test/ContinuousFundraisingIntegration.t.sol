// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/TokenCloneFactory.sol";
import "../contracts/ContinuousFundraising.sol";
import "../contracts/FeeSettings.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/MaliciousPaymentToken.sol";

contract ContinuousFundraisingTest is Test {
    ContinuousFundraising raise;
    AllowList list;
    FeeSettings feeSettings;

    Token implementation = new Token(trustedForwarder);
    TokenCloneFactory factory = new TokenCloneFactory(address(implementation));
    Token token;
    FakePaymentToken paymentToken;

    address public constant platformAdmin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant investor = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant mintAllower = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant minter = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant companyOwner = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant receiver = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant paymentTokenProvider = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant trustedForwarder = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    uint8 public constant paymentTokenDecimals = 6;
    uint256 public constant paymentTokenAmount = 1000 * 10 ** paymentTokenDecimals;

    uint256 public constant price = 7 * 10 ** paymentTokenDecimals; // 7 payment tokens per token

    uint256 public constant maxAmountOfTokenToBeSold = 20 * 10 ** 18; // 20 token
    uint256 public constant maxAmountPerBuyer = maxAmountOfTokenToBeSold / 2; // 10 token
    uint256 public constant minAmountPerBuyer = maxAmountOfTokenToBeSold / 200; // 0.1 token

    function setUp() public {
        list = new AllowList();
        Fees memory fees = Fees(100, 100, 100, 100);
        vm.prank(platformAdmin);
        feeSettings = new FeeSettings(fees, platformAdmin);
        vm.prank(platformAdmin);
        token = Token(
            factory.createTokenClone(0, trustedForwarder, feeSettings, companyOwner, list, 0x0, "TESTTOKEN", "TEST")
        );

        // set up currency
        vm.prank(paymentTokenProvider);
        paymentToken = new FakePaymentToken(paymentTokenAmount, paymentTokenDecimals); // 1000 tokens with 6 decimals
        // transfer currency to buyer
        vm.prank(paymentTokenProvider);
        paymentToken.transfer(investor, paymentTokenAmount);
        assertTrue(paymentToken.balanceOf(investor) == paymentTokenAmount);

        vm.prank(companyOwner);
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

        vm.prank(companyOwner);
        token.grantRole(roleMintAllower, mintAllower);
        vm.prank(mintAllower);
        token.increaseMintingAllowance(address(raise), maxAmountOfTokenToBeSold);

        // give raise contract allowance
        vm.prank(investor);
        paymentToken.approve(address(raise), paymentTokenAmount);
    }

    /*
    set up with FakePaymentToken which has variable decimals to make sure that doesn't break anything
    */
    function feeCalculation(uint256 tokenFeeDenominator, uint256 continuousFundraisingFeeDenominator) public {
        // apply fees for test
        Fees memory fees = Fees(
            tokenFeeDenominator,
            continuousFundraisingFeeDenominator,
            continuousFundraisingFeeDenominator,
            block.timestamp + 13 weeks
        );
        vm.prank(platformAdmin);
        feeSettings.planFeeChange(fees);
        vm.warp(fees.time + 1 seconds);
        vm.prank(platformAdmin);
        feeSettings.executeFeeChange();

        FakePaymentToken _paymentToken;

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
        price definition: 30FPT buy 1CT, but must be expressed in FPTbits/CT
        price = 30 * 10**_paymentTokenDecimals
        */
        uint256 _price = 30 * 10 ** _paymentTokenDecimals;
        uint256 _maxMintAmount = 2 ** 256 - 1; // need maximum possible value because we are using a fake token with variable decimals
        uint256 _paymentTokenAmount = 1000 * 10 ** _paymentTokenDecimals;

        list = new AllowList();
        Token _token = Token(
            factory.createTokenClone(0, trustedForwarder, feeSettings, companyOwner, list, 0x0, "FEETESTTOKEN", "TEST")
        );

        vm.prank(paymentTokenProvider);
        _paymentToken = new FakePaymentToken(_paymentTokenAmount, _paymentTokenDecimals);
        vm.prank(companyOwner);

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

        vm.prank(companyOwner);
        _token.grantRole(roleMintAllower, mintAllower);
        vm.prank(mintAllower);
        _token.increaseMintingAllowance(address(_raise), _maxMintAmount);

        // mint _paymentToken for buyer
        vm.prank(paymentTokenProvider);
        _paymentToken.transfer(investor, _paymentTokenAmount);
        assertTrue(_paymentToken.balanceOf(investor) == _paymentTokenAmount);

        // give invite contract allowance
        vm.prank(investor);
        _paymentToken.approve(address(_raise), _paymentTokenAmount);

        // run actual test

        uint tokenAmount = 33 * 10 ** token.decimals();

        // buyer has 1k FPT
        assertTrue(_paymentToken.balanceOf(investor) == _paymentTokenAmount);
        // they should be able to buy 33 CT for 999 FPT
        vm.prank(investor);
        _raise.buy(tokenAmount, investor);
        // buyer should have 10 FPT left
        assertTrue(_paymentToken.balanceOf(investor) == 10 * 10 ** _paymentTokenDecimals);
        // buyer should have the 33 CT they bought
        assertTrue(_token.balanceOf(investor) == tokenAmount, "buyer has wrong amount of token");
        // receiver should have the 990 FPT that were paid, minus the fee

        uint currencyAmount = 990 * 10 ** _paymentTokenDecimals;
        uint256 currencyFee = currencyAmount /
            FeeSettings(address(token.feeSettings())).continuousFundraisingFeeDenominator();
        assertTrue(
            _paymentToken.balanceOf(receiver) == currencyAmount - currencyFee,
            "receiver has wrong amount of currency"
        );
        // fee collector should have the token and currency fees
        assertEq(
            currencyFee,
            _paymentToken.balanceOf(feeSettings.feeCollector()),
            "fee collector has wrong amount of currency"
        );
        assertEq(
            tokenAmount / FeeSettings(address(token.feeSettings())).tokenFeeDenominator(),
            _token.balanceOf(feeSettings.feeCollector()),
            "fee collector has wrong amount of token"
        );
        // }
    }

    function testFee0() public {
        feeCalculation(UINT256_MAX, UINT256_MAX);
    }

    function testVariousFees(uint256 tokenFeeDenominator, uint256 continuousFundraisingFeeDenominator) public {
        vm.assume(tokenFeeDenominator >= 20);
        vm.assume(continuousFundraisingFeeDenominator >= 20);
        feeCalculation(tokenFeeDenominator, continuousFundraisingFeeDenominator);
    }

    /*
    set up with FakePaymentToken which has variable decimals to make sure that doesn't break anything
    */
    function testVaryDecimals() public {
        uint8 _maxDecimals = 25;
        FakePaymentToken _paymentToken;

        for (uint8 _paymentTokenDecimals = 1; _paymentTokenDecimals < _maxDecimals; _paymentTokenDecimals++) {
            //uint8 _paymentTokenDecimals = 10;

            /*
            _paymentToken: 1 FPT = 10**_paymentTokenDecimals FPTbits (bit = smallest subunit of token)
            Token: 1 CT = 10**18 CTbits
            price definition: 30FPT buy 1CT, but must be expressed in FPTbits/CT
            price = 30 * 10**_paymentTokenDecimals
            */
            uint256 _price = 30 * 10 ** _paymentTokenDecimals;
            uint256 _maxMintAmount = 2 ** 256 - 1; // need maximum possible value because we are using a fake token with variable decimals
            uint256 _paymentTokenAmount = 1000 * 10 ** _paymentTokenDecimals;

            list = new AllowList();
            Token _token = Token(
                factory.createTokenClone(
                    0,
                    trustedForwarder,
                    feeSettings,
                    companyOwner,
                    list,
                    0x0,
                    "DECIMALSTESTTOKEN",
                    "TEST"
                )
            );

            vm.prank(paymentTokenProvider);
            _paymentToken = new FakePaymentToken(_paymentTokenAmount, _paymentTokenDecimals);
            vm.prank(companyOwner);

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

            vm.prank(companyOwner);
            _token.grantRole(roleMintAllower, mintAllower);
            vm.prank(mintAllower);
            _token.increaseMintingAllowance(address(_raise), _maxMintAmount);

            // mint _paymentToken for buyer
            vm.prank(paymentTokenProvider);
            _paymentToken.transfer(investor, _paymentTokenAmount);
            assertTrue(_paymentToken.balanceOf(investor) == _paymentTokenAmount);

            // give invite contract allowance
            vm.prank(investor);
            _paymentToken.approve(address(_raise), _paymentTokenAmount);

            // run actual test

            uint tokenAmount = 33 * 10 ** token.decimals();

            // buyer has 1k FPT
            assertTrue(_paymentToken.balanceOf(investor) == _paymentTokenAmount);
            // they should be able to buy 33 CT for 999 FPT
            vm.prank(investor);
            _raise.buy(tokenAmount, investor);
            // buyer should have 10 FPT left
            assertTrue(_paymentToken.balanceOf(investor) == 10 * 10 ** _paymentTokenDecimals);
            // buyer should have the 33 CT they bought
            assertTrue(_token.balanceOf(investor) == tokenAmount, "buyer has wrong amount of token");
            // receiver should have the 990 FPT that were paid, minus the fee
            uint currencyAmount = 990 * 10 ** _paymentTokenDecimals;
            uint256 currencyFee = currencyAmount /
                FeeSettings(address(token.feeSettings())).continuousFundraisingFeeDenominator();
            assertTrue(
                _paymentToken.balanceOf(receiver) == currencyAmount - currencyFee,
                "receiver has wrong amount of currency"
            );
            // fee collector should have the token and currency fees
            assertEq(
                currencyFee,
                _paymentToken.balanceOf(feeSettings.feeCollector()),
                "fee collector has wrong amount of currency"
            );
            assertEq(
                tokenAmount / FeeSettings(address(token.feeSettings())).tokenFeeDenominator(),
                _token.balanceOf(feeSettings.feeCollector()),
                "fee collector has wrong amount of token"
            );
        }
    }
}
