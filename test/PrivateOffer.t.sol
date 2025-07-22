// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/PrivateOffer.sol";
import "../contracts/factories/PrivateOfferCloneFactory.sol";
import "./resources/CloneCreators.sol";
import "./resources/FakePaymentToken.sol";

contract PrivateOfferTest is Test {
    event Deal(
        address indexed currencyPayer,
        address indexed tokenReceiver,
        uint256 tokenAmount,
        uint256 tokenPrice,
        IERC20 currency,
        Token indexed token
    );

    PrivateOfferCloneFactory factory;

    AllowList list;
    FeeSettings feeSettings;
    Token token;
    FakePaymentToken currency;

    address wrongFeeReceiver = address(5);

    uint256 MAX_INT = type(uint256).max;

    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant tokenReceiver = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant mintAllower = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant currencyPayer = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant owner = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant currencyReceiver = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant paymentTokenProvider = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant trustedForwarder = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;
    address public constant tokenHolder = 0xa109709ecfA91A80626ff3989D68F67F5b1dD12a;

    uint256 public constant price = 10000000;

    uint256 requirements = 92785934;

    function setUp() public {
        Vesting vestingImplementation = new Vesting(trustedForwarder);
        VestingCloneFactory vestingCloneFactory = new VestingCloneFactory(address(vestingImplementation));
        PrivateOffer privateOfferImplementation = new PrivateOffer();
        factory = new PrivateOfferCloneFactory(address(privateOfferImplementation), vestingCloneFactory);

        vm.prank(paymentTokenProvider);
        currency = new FakePaymentToken(0, 18);

        list = createAllowList(trustedForwarder, address(this));
        list.set(tokenReceiver, requirements);
        list.set(tokenHolder, requirements);
        list.set(address(currency), TRUSTED_CURRENCY);

        Fees memory fees = Fees(100, 100, 100, 0);
        feeSettings = createFeeSettings(
            trustedForwarder,
            address(this),
            fees,
            wrongFeeReceiver,
            wrongFeeReceiver,
            admin
        );

        Token implementation = new Token(trustedForwarder);
        TokenProxyFactory tokenCloneFactory = new TokenProxyFactory(address(implementation));
        token = Token(
            tokenCloneFactory.createTokenProxy(
                0,
                trustedForwarder,
                feeSettings,
                admin,
                list,
                requirements,
                "token",
                "TOK"
            )
        );
    }

    function testAcceptDealAndMintTokens(uint256 rawSalt) public {
        //uint rawSalt = 0;
        bytes32 salt = bytes32(rawSalt);

        //bytes memory creationCode = type(PrivateOffer).creationCode;
        uint256 amount = 20000000000000;
        uint256 expiration = block.timestamp + 1000;

        PrivateOfferFixedArguments memory fixedArguments = PrivateOfferFixedArguments(
            currencyReceiver,
            address(0),
            amount,
            amount,
            price,
            expiration,
            currency,
            token
        );

        PrivateOfferVariableArguments memory variableArguments = PrivateOfferVariableArguments(
            tokenReceiver,
            tokenReceiver,
            amount
        );

        address expectedAddress = factory.predictCloneAddress(salt, fixedArguments);
        console.log("expectedAddress: %s", expectedAddress);

        // make sure balances are as expected before deployment
        uint256 tokenDecimals = token.decimals();

        vm.startPrank(paymentTokenProvider);
        currency.mint(tokenReceiver, (amount * price) / 10 ** tokenDecimals);
        vm.stopPrank();

        vm.prank(admin);
        token.increaseMintingAllowance(expectedAddress, amount);

        vm.prank(tokenReceiver);
        currency.approve(expectedAddress, (amount * price) / 10 ** tokenDecimals);

        // make sure balances are as expected before deployment

        uint currencyAmount = (amount * price) / 10 ** tokenDecimals;
        assertEq(currency.balanceOf(tokenReceiver), currencyAmount);
        assertEq(currency.balanceOf(currencyReceiver), 0);
        assertEq(token.balanceOf(tokenReceiver), 0);
        assertEq(
            currency.balanceOf(FeeSettings(address(token.feeSettings())).privateOfferFeeCollector(address(token))),
            0,
            "privateOfferFeeCollector currency balance is not correct"
        );
        assertEq(
            token.balanceOf(FeeSettings(address(token.feeSettings())).tokenFeeCollector(address(token))),
            0,
            "tokenFeeCollector currency balance is not correct"
        );

        uint256 feeCollectorCurrencyBalanceBefore = currency.balanceOf(
            FeeSettings(address(token.feeSettings())).feeCollector()
        );
        vm.expectEmit(true, true, true, true, address(expectedAddress));
        emit Deal(tokenReceiver, tokenReceiver, amount, price, currency, token);

        address inviteAddress = factory.createPrivateOfferClone(salt, fixedArguments, variableArguments);

        console.log(
            "feeCollector currency balance after deployment: %s",
            currency.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector())
        );

        assertEq(inviteAddress, expectedAddress, "deployed contract address is not correct");

        console.log("buyer balance: %s", currency.balanceOf(tokenReceiver));
        console.log("receiver balance: %s", currency.balanceOf(currencyReceiver));
        console.log("buyer token balance: %s", token.balanceOf(tokenReceiver));
        uint256 len;
        assembly {
            len := extcodesize(expectedAddress)
        }
        console.log("Deployed contract size: %s", len);

        // make sure balances are as expected after deployment
        assertEq(currency.balanceOf(tokenReceiver), 0);

        assertEq(
            currency.balanceOf(currencyReceiver),
            currencyAmount - FeeSettings(address(token.feeSettings())).privateOfferFee(currencyAmount, address(token))
        );

        assertEq(
            currency.balanceOf(FeeSettings(address(token.feeSettings())).privateOfferFeeCollector(address(token))),
            feeCollectorCurrencyBalanceBefore +
                FeeSettings(address(token.feeSettings())).privateOfferFee(currencyAmount, address(token)),
            "feeCollector currency balance is not correct"
        );

        assertEq(token.balanceOf(tokenReceiver), amount);

        assertEq(
            token.balanceOf(FeeSettings(address(token.feeSettings())).tokenFeeCollector(address(token))),
            FeeSettings(address(token.feeSettings())).tokenFee(amount, address(token))
        );
    }

    function testAcceptDealAndTransferTokens(uint256 rawSalt) public {
        //uint rawSalt = 0;
        bytes32 salt = bytes32(rawSalt);

        //bytes memory creationCode = type(PrivateOffer).creationCode;
        uint256 amount = 20000000000000;
        uint256 expiration = block.timestamp + 1000;

        PrivateOfferFixedArguments memory fixedArguments = PrivateOfferFixedArguments(
            currencyReceiver,
            tokenHolder,
            amount,
            amount,
            price,
            expiration,
            currency,
            token
        );

        PrivateOfferVariableArguments memory variableArguments = PrivateOfferVariableArguments(
            tokenReceiver,
            tokenReceiver,
            amount
        );

        address expectedAddress = factory.predictCloneAddress(salt, fixedArguments);

        uint256 tokenDecimals = token.decimals();

        vm.startPrank(paymentTokenProvider);
        currency.mint(tokenReceiver, (amount * price) / 10 ** tokenDecimals);
        vm.stopPrank();

        vm.startPrank(admin);
        token.increaseMintingAllowance(admin, amount);
        token.mint(tokenHolder, amount);
        vm.stopPrank();

        vm.startPrank(tokenHolder);
        token.approve(expectedAddress, amount);
        vm.stopPrank();

        vm.prank(tokenReceiver);
        currency.approve(expectedAddress, (amount * price) / 10 ** tokenDecimals);

        // make sure balances are as expected before deployment

        uint currencyAmount = (amount * price) / 10 ** tokenDecimals;
        assertEq(currency.balanceOf(tokenReceiver), currencyAmount);
        assertEq(currency.balanceOf(currencyReceiver), 0);
        assertEq(token.balanceOf(tokenReceiver), 0);
        assertEq(token.balanceOf(tokenHolder), amount);
        uint256 expectedTotalTokenSupply = amount +
            FeeSettings(address(token.feeSettings())).tokenFee(amount, address(token));
        assertEq(token.totalSupply(), expectedTotalTokenSupply, "token supply is not as expected before deployment");
        assertEq(
            currency.balanceOf(FeeSettings(address(token.feeSettings())).privateOfferFeeCollector(address(token))),
            0,
            "privateOfferFeeCollector currency balance is not correct"
        );
        assertEq(
            token.balanceOf(FeeSettings(address(token.feeSettings())).tokenFeeCollector(address(token))),
            FeeSettings(address(token.feeSettings())).tokenFee(amount, address(token)),
            "tokenFeeCollector currency balance is not correct"
        );

        // make sure balances are as expected after deployment
        uint256 feeCollectorCurrencyBalanceBefore = currency.balanceOf(
            FeeSettings(address(token.feeSettings())).feeCollector()
        );
        vm.expectEmit(true, true, true, true, address(expectedAddress));
        emit Deal(tokenReceiver, tokenReceiver, amount, price, currency, token);

        address inviteAddress = factory.createPrivateOfferClone(salt, fixedArguments, variableArguments);

        console.log(
            "feeCollector currency balance after deployment: %s",
            currency.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector())
        );

        assertEq(inviteAddress, expectedAddress, "deployed contract address is not correct");

        console.log("buyer balance: %s", currency.balanceOf(tokenReceiver));
        console.log("receiver balance: %s", currency.balanceOf(currencyReceiver));
        console.log("buyer token balance: %s", token.balanceOf(tokenReceiver));
        uint256 len;
        assembly {
            len := extcodesize(expectedAddress)
        }
        console.log("Deployed contract size: %s", len);
        assertEq(currency.balanceOf(tokenReceiver), 0);

        assertEq(
            currency.balanceOf(currencyReceiver),
            currencyAmount - FeeSettings(address(token.feeSettings())).privateOfferFee(currencyAmount, address(token))
        );

        assertEq(
            currency.balanceOf(FeeSettings(address(token.feeSettings())).privateOfferFeeCollector(address(token))),
            feeCollectorCurrencyBalanceBefore +
                FeeSettings(address(token.feeSettings())).privateOfferFee(currencyAmount, address(token)),
            "feeCollector currency balance is not correct"
        );

        assertEq(token.balanceOf(tokenReceiver), amount, "tokenReceiver received wrong amount of tokens");
        assertEq(token.balanceOf(tokenHolder), 0, "tokenHolder still has tokens");
        assertEq(token.totalSupply(), expectedTotalTokenSupply, "token supply changed during deployment");

        assertEq(
            token.balanceOf(FeeSettings(address(token.feeSettings())).tokenFeeCollector(address(token))),
            FeeSettings(address(token.feeSettings())).tokenFee(amount, address(token))
        );
    }

    function ensureCostIsRoundedUp(uint256 _tokenBuyAmount, uint256 _nominalPrice) public {
        console.log(
            "feeCollector currency balance: %s",
            currency.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector())
        );

        //uint rawSalt = 0;
        bytes32 salt = bytes32(uint256(8));

        //bytes memory creationCode = type(PrivateOffer).creationCode;
        uint256 expiration = block.timestamp + 1000;

        PrivateOfferFixedArguments memory fixedArguments = PrivateOfferFixedArguments(
            currencyReceiver,
            address(0),
            _tokenBuyAmount,
            _tokenBuyAmount,
            _nominalPrice,
            expiration,
            currency,
            token
        );

        PrivateOfferVariableArguments memory variableArguments = PrivateOfferVariableArguments(
            currencyPayer,
            tokenReceiver,
            _tokenBuyAmount
        );

        address expectedAddress = factory.predictCloneAddress(salt, fixedArguments);

        // set fees to 0, otherwise extra tokens are minted which causes an overflow
        Fees memory fees = Fees(0, 0, 0, 0);
        FeeSettings(address(token.feeSettings())).planFeeChange(fees);
        FeeSettings(address(token.feeSettings())).executeFeeChange();

        vm.prank(admin);
        token.increaseMintingAllowance(expectedAddress, _tokenBuyAmount);

        uint minCurrencyAmount = (_tokenBuyAmount * _nominalPrice) / 10 ** token.decimals();
        console.log("minCurrencyAmount: %s", minCurrencyAmount);
        uint maxCurrencyAmount = minCurrencyAmount + 1;
        console.log("maxCurrencyAmount: %s", maxCurrencyAmount);

        vm.prank(paymentTokenProvider);
        currency.mint(currencyPayer, maxCurrencyAmount);

        vm.prank(currencyPayer);
        currency.approve(expectedAddress, maxCurrencyAmount);

        // make sure balances are as expected before deployment

        console.log(
            "feeCollector currency balance: %s",
            currency.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector())
        );

        assertEq(currency.balanceOf(currencyPayer), maxCurrencyAmount, "CurrencyPayer has wrong balance");
        assertEq(currency.balanceOf(currencyReceiver), 0, "CurrencyReceiver has wrong balance");
        assertEq(
            token.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector()),
            0,
            "feeCollector token balance is not correct"
        );
        assertEq(token.balanceOf(tokenReceiver), 0);

        console.log(
            "feeCollector currency balance before deployment: %s",
            currency.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector())
        );
        // make sure balances are as expected after deployment
        uint256 currencyReceiverBalanceBefore = currency.balanceOf(currencyReceiver);

        address inviteAddress = factory.createPrivateOfferClone(salt, fixedArguments, variableArguments);

        console.log(
            "feeCollector currency balance after deployment: %s",
            currency.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector())
        );

        assertEq(inviteAddress, expectedAddress, "deployed contract address is not correct");

        console.log("currencyPayer balance: %s", currency.balanceOf(currencyPayer));
        console.log("currencyReceiver balance: %s", currency.balanceOf(currencyReceiver));
        console.log("tokenReceiver token balance: %s", token.balanceOf(tokenReceiver));
        uint256 len;
        assembly {
            len := extcodesize(expectedAddress)
        }
        console.log("Deployed contract size: %s", len);
        assertTrue(currency.balanceOf(currencyPayer) <= 1, "currencyPayer has too much currency left");

        assertTrue(
            currency.balanceOf(currencyReceiver) > currencyReceiverBalanceBefore,
            "currencyReceiver received no payment"
        );

        console.log(
            "feeCollector currency balance: %s",
            currency.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector())
        );

        assertTrue(maxCurrencyAmount - currency.balanceOf(currencyPayer) >= 1, "currencyPayer paid nothing");
        uint totalCurrencyReceived = currency.balanceOf(currencyReceiver) +
            currency.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector());
        console.log("totalCurrencyReceived: %s", totalCurrencyReceived);
        assertTrue(totalCurrencyReceived >= minCurrencyAmount, "Receiver and feeCollector received less than expected");

        assertTrue(totalCurrencyReceived <= maxCurrencyAmount, "Receiver and feeCollector received more than expected");

        assertEq(token.balanceOf(tokenReceiver), _tokenBuyAmount, "tokenReceiver received no tokens");
    }

    function testRoundUp0() public {
        // buy one token bit with price 1 currency bit per full token
        // -> would have to pay 10^-18 currency bits, which is not possible
        // we expect to round up to 1 currency bit
        ensureCostIsRoundedUp(1, 1);
    }

    function testRoundFixedExample0() public {
        ensureCostIsRoundedUp(583 * 10 ** token.decimals(), 82742);
    }

    function testRoundFixedExample1() public {
        ensureCostIsRoundedUp(583 * 10 ** token.decimals(), 82742);
    }

    function testRoundUpAnything(uint256 _tokenBuyAmount, uint256 _tokenPrice) public {
        vm.assume(_tokenBuyAmount > 0);
        vm.assume(_tokenPrice > 0);
        vm.assume(UINT256_MAX / _tokenPrice > _tokenBuyAmount);
        // vm.assume(UINT256_MAX / _tokenPrice > 10 ** token.decimals());
        // vm.assume(
        //     UINT256_MAX / _tokenBuyAmount > _tokenPrice * 10 ** token.decimals()
        // ); // amount * price *10**18 < UINT256_MAX
        //vm.assume(_tokenPrice < UINT256_MAX / (100 * 10 ** token.decimals()));
        ensureCostIsRoundedUp(_tokenBuyAmount, _tokenPrice);
    }

    function ensureReverts(uint256 _tokenBuyAmount, uint256 _nominalPrice) public {
        bytes32 salt = bytes32(uint256(8));

        uint256 expiration = block.timestamp + 1000;

        PrivateOfferFixedArguments memory fixedArguments = PrivateOfferFixedArguments(
            currencyReceiver,
            address(0),
            _tokenBuyAmount,
            _tokenBuyAmount,
            _nominalPrice,
            expiration,
            currency,
            token
        );

        PrivateOfferVariableArguments memory variableArguments = PrivateOfferVariableArguments(
            currencyPayer,
            tokenReceiver,
            _tokenBuyAmount
        );

        address expectedAddress = factory.predictCloneAddress(salt, fixedArguments);

        vm.startPrank(admin);
        console.log("expectedAddress: %s", token.mintingAllowance(expectedAddress));
        token.increaseMintingAllowance(expectedAddress, _tokenBuyAmount);
        vm.stopPrank();

        uint maxCurrencyAmount = UINT256_MAX;

        vm.prank(paymentTokenProvider);
        currency.mint(currencyPayer, maxCurrencyAmount);
        vm.prank(currencyPayer);
        currency.approve(expectedAddress, maxCurrencyAmount);

        vm.expectRevert("panic: arithmetic underflow or overflow (0x11)");
        factory.createPrivateOfferClone(salt, fixedArguments, variableArguments);
    }

    function testRevertOnOverflow(uint256 _tokenBuyAmount, uint256 _tokenPrice) public {
        vm.assume(_tokenBuyAmount > 0);
        vm.assume(_tokenPrice > 0);

        vm.assume(UINT256_MAX / _tokenPrice < _tokenBuyAmount);
        ensureReverts(_tokenBuyAmount, _tokenPrice);
    }

    function testInvalidCurrency(uint256 _attributes) public {
        vm.assume(_attributes != TRUSTED_CURRENCY);

        // remove trusted currency from allowlist
        list.set(address(currency), _attributes);

        uint256 _tokenBuyAmount = 200e18;
        uint256 _nominalPrice = 3e6;
        bytes32 salt = bytes32(uint256(8));

        uint256 expiration = block.timestamp + 1000;

        PrivateOfferFixedArguments memory fixedArguments = PrivateOfferFixedArguments(
            currencyReceiver,
            address(0),
            _tokenBuyAmount,
            _tokenBuyAmount,
            _nominalPrice,
            expiration,
            currency,
            token
        );

        PrivateOfferVariableArguments memory variableArguments = PrivateOfferVariableArguments(
            currencyPayer,
            tokenReceiver,
            _tokenBuyAmount
        );

        address expectedAddress = factory.predictCloneAddress(salt, fixedArguments);

        vm.startPrank(admin);
        console.log("expectedAddress: %s", token.mintingAllowance(expectedAddress));
        token.increaseMintingAllowance(expectedAddress, _tokenBuyAmount);
        vm.stopPrank();

        uint maxCurrencyAmount = UINT256_MAX;

        vm.prank(paymentTokenProvider);
        currency.mint(currencyPayer, maxCurrencyAmount);
        vm.prank(currencyPayer);
        currency.approve(expectedAddress, maxCurrencyAmount);

        vm.prank(tokenReceiver);
        currency.approve(expectedAddress, maxCurrencyAmount);

        vm.expectRevert("currency needs to be on the allowlist with TRUSTED_CURRENCY attribute");
        factory.createPrivateOfferClone(salt, fixedArguments, variableArguments);

        // restore trusted currency on allowlist and make sure it works again
        list.set(address(currency), TRUSTED_CURRENCY);
        factory.createPrivateOfferClone(salt, fixedArguments, variableArguments);
    }

    function testAcceptWithDifferentTokenReceiver(uint256 rawSalt) public {
        //uint rawSalt = 0;
        bytes32 salt = bytes32(rawSalt);

        //bytes memory creationCode = type(PrivateOffer).creationCode;
        uint256 tokenAmount = 20000000000000;
        uint256 expiration = block.timestamp + 1000;
        uint256 tokenDecimals = token.decimals();
        uint256 currencyAmount = (tokenAmount * price) / 10 ** tokenDecimals;

        PrivateOfferFixedArguments memory fixedArguments = PrivateOfferFixedArguments(
            currencyReceiver,
            address(0),
            tokenAmount,
            tokenAmount,
            price,
            expiration,
            currency,
            token
        );

        PrivateOfferVariableArguments memory variableArguments = PrivateOfferVariableArguments(
            currencyPayer,
            tokenReceiver,
            tokenAmount
        );

        address expectedAddress = factory.predictCloneAddress(salt, fixedArguments);

        vm.prank(admin);
        token.increaseMintingAllowance(expectedAddress, tokenAmount);

        vm.prank(paymentTokenProvider);
        currency.mint(currencyPayer, currencyAmount);

        vm.prank(currencyPayer);
        currency.approve(expectedAddress, currencyAmount);

        // make sure balances are as expected before deployment

        assertEq(currency.balanceOf(currencyPayer), currencyAmount);
        assertEq(currency.balanceOf(currencyReceiver), 0);
        assertEq(currency.balanceOf(tokenReceiver), 0);
        assertEq(token.balanceOf(tokenReceiver), 0);
        assertEq(
            currency.balanceOf(token.feeSettings().privateOfferFeeCollector(address(token))),
            0,
            "privateOfferFeeCollector currency balance is not correct"
        );
        assertEq(
            token.balanceOf(token.feeSettings().tokenFeeCollector(address(token))),
            0,
            "tokenFeeCollector token balance is not correct"
        );

        address inviteAddress = factory.createPrivateOfferClone(salt, fixedArguments, variableArguments);

        assertEq(inviteAddress, expectedAddress, "deployed contract address is not correct");

        console.log("payer balance: %s", currency.balanceOf(currencyPayer));
        console.log("receiver balance: %s", currency.balanceOf(currencyReceiver));
        console.log("tokenReceiver token balance: %s", token.balanceOf(tokenReceiver));
        uint256 len;
        assembly {
            len := extcodesize(expectedAddress)
        }
        console.log("Deployed contract size: %s", len);
        assertEq(currency.balanceOf(currencyPayer), 0);

        assertEq(
            currency.balanceOf(currencyReceiver),
            currencyAmount - token.feeSettings().privateOfferFee(currencyAmount, address(token))
        );

        assertEq(
            currency.balanceOf(token.feeSettings().privateOfferFeeCollector(address(token))),
            token.feeSettings().privateOfferFee(currencyAmount, address(token)),
            "feeCollector currency balance is not correct"
        );

        assertEq(token.balanceOf(tokenReceiver), tokenAmount);

        assertEq(
            token.balanceOf(token.feeSettings().tokenFeeCollector(address(token))),
            token.feeSettings().tokenFee(tokenAmount, address(token))
        );
    }

    function testRevertsWithInsufficientAllowances(uint256 rawSalt) public {
        bytes32 salt = bytes32(rawSalt);

        uint256 amount = 20000000000000;
        uint256 expiration = block.timestamp + 1000;

        PrivateOfferFixedArguments memory fixedArguments = PrivateOfferFixedArguments(
            currencyReceiver,
            tokenHolder,
            amount,
            amount,
            price,
            expiration,
            currency,
            token
        );

        PrivateOfferVariableArguments memory variableArguments = PrivateOfferVariableArguments(
            tokenReceiver,
            tokenReceiver,
            amount
        );

        address expectedAddress = factory.predictCloneAddress(salt, fixedArguments);

        uint256 tokenDecimals = token.decimals();

        vm.startPrank(paymentTokenProvider);
        currency.mint(tokenReceiver, (amount * price) / 10 ** tokenDecimals);
        vm.stopPrank();

        vm.startPrank(admin);
        token.increaseMintingAllowance(admin, amount);
        token.mint(tokenHolder, amount);
        vm.stopPrank();

        // Case 1: Token allowance too low
        vm.startPrank(tokenHolder);
        token.approve(expectedAddress, amount - 1); // Approve less than required
        vm.stopPrank();

        vm.prank(tokenReceiver);
        currency.approve(expectedAddress, (amount * price) / 10 ** tokenDecimals);

        vm.expectRevert("ERC20: insufficient allowance");
        factory.createPrivateOfferClone(salt, fixedArguments, variableArguments);

        // Case 2: Payment token allowance too low
        vm.startPrank(tokenHolder);
        token.approve(expectedAddress, amount); // Reset token allowance to sufficient
        vm.stopPrank();

        vm.prank(tokenReceiver);
        currency.approve(expectedAddress, (amount * price) / 10 ** tokenDecimals - 1); // Approve less than required

        vm.expectRevert("ERC20: insufficient allowance");
        factory.createPrivateOfferClone(salt, fixedArguments, variableArguments);

        // Verify balances remain unchanged after reverts
        uint currencyAmount = (amount * price) / 10 ** tokenDecimals;
        assertEq(currency.balanceOf(tokenReceiver), currencyAmount);
        assertEq(currency.balanceOf(currencyReceiver), 0);
        assertEq(token.balanceOf(tokenReceiver), 0);
        assertEq(token.balanceOf(tokenHolder), amount);
        uint256 expectedTotalTokenSupply = amount +
            FeeSettings(address(token.feeSettings())).tokenFee(amount, address(token));
        assertEq(token.totalSupply(), expectedTotalTokenSupply, "token supply is not as expected");
        assertEq(
            currency.balanceOf(FeeSettings(address(token.feeSettings())).privateOfferFeeCollector(address(token))),
            0,
            "privateOfferFeeCollector currency balance is not correct"
        );
        assertEq(
            token.balanceOf(FeeSettings(address(token.feeSettings())).tokenFeeCollector(address(token))),
            FeeSettings(address(token.feeSettings())).tokenFee(amount, address(token)),
            "tokenFeeCollector currency balance is not correct"
        );
    }

    function testRevertsIfBuyAmountTooHighOrLow(uint256 rawSalt) public {
        bytes32 salt = bytes32(rawSalt);

        uint256 minAmount = 20000000000000;
        uint256 maxAmount = minAmount * 100;
        uint256 expiration = block.timestamp + 1000;

        PrivateOfferFixedArguments memory fixedArguments = PrivateOfferFixedArguments(
            currencyReceiver,
            tokenHolder,
            minAmount,
            maxAmount,
            price,
            expiration,
            currency,
            token
        );

        address expectedAddress = factory.predictCloneAddress(salt, fixedArguments);

        uint256 tokenDecimals = token.decimals();
        uint256 currencyAmount = (maxAmount * price) / 10 ** tokenDecimals;

        vm.startPrank(paymentTokenProvider);
        currency.mint(tokenReceiver, currencyAmount);
        vm.stopPrank();

        vm.startPrank(admin);
        token.increaseMintingAllowance(admin, maxAmount);
        token.mint(tokenHolder, maxAmount);
        vm.stopPrank();

        vm.startPrank(tokenHolder);
        token.approve(expectedAddress, maxAmount);
        vm.stopPrank();

        vm.prank(tokenReceiver);
        currency.approve(expectedAddress, currencyAmount);

        // Case 1: Buy amount too high
        PrivateOfferVariableArguments memory variableArgumentsTooHigh = PrivateOfferVariableArguments(
            tokenReceiver,
            tokenReceiver,
            maxAmount + 1 // Exceeds maxAmount
        );

        vm.expectRevert("tokenAmount is greater than maxTokenAmount");
        factory.createPrivateOfferClone(salt, fixedArguments, variableArgumentsTooHigh);

        // Case 2: Buy amount too low
        PrivateOfferVariableArguments memory variableArgumentsTooLow = PrivateOfferVariableArguments(
            tokenReceiver,
            tokenReceiver,
            minAmount - 1 // Less than minAmount
        );

        vm.expectRevert("tokenAmount is less than minTokenAmount");
        factory.createPrivateOfferClone(salt, fixedArguments, variableArgumentsTooLow);

        // Case 3: successfull execution
        PrivateOfferVariableArguments memory variableArgumentsSuccess = PrivateOfferVariableArguments(
            tokenReceiver,
            tokenReceiver,
            maxAmount
        );
        factory.createPrivateOfferClone(salt, fixedArguments, variableArgumentsSuccess);

        // Verify balances are correct after successful execution
        assertEq(currency.balanceOf(tokenReceiver), 0, "tokenReceiver currency balance is not correct");
        assertEq(
            currency.balanceOf(currencyReceiver),
            currencyAmount - token.feeSettings().privateOfferFee(currencyAmount, address(token)),
            "currencyReceiver currency balance is not correct"
        );
        assertEq(token.balanceOf(tokenReceiver), maxAmount, "tokenReceiver token balance is not correct");
        assertEq(token.balanceOf(tokenHolder), 0, "tokenHolder token balance is not correct");
        assertEq(
            token.balanceOf(token.feeSettings().tokenFeeCollector(address(token))),
            token.feeSettings().tokenFee(maxAmount, address(token)),
            "tokenFeeCollector token balance is not correct"
        );
    }
}
