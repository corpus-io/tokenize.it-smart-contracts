// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/PrivateOffer.sol";
import "../contracts/factories/PrivateOfferFactory.sol";
import "../contracts/factories/TimeLockCloneFactory.sol";
import "../contracts/TimeLock.sol";
import "./resources/CloneCreators.sol";
import "../contracts/common/IFeeSettings.sol";
import "./resources/FakePaymentToken.sol";

contract PrivateOfferTest is Test {
    event Deal(
        address indexed CURRENCY_PAYER,
        address indexed TOKEN_RECEIVER,
        uint256 tokenAmount,
        uint256 tokenPrice,
        IERC20 currency,
        Token indexed token
    );

    PrivateOfferFactory factory;

    AllowList list;
    FeeSettings feeSettings;
    Token token;
    FakePaymentToken currency;

    address wrongFeeReceiver = address(5);

    uint256 MAX_INT = type(uint256).max;

    address public constant ADMIN = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant TOKEN_RECEIVER = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant MINT_ALLOWER = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant CURRENCY_PAYER = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant OWNER = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant CURRENCY_RECEIVER = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant PAYMENT_TOKEN_PROVIDER = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant TRUSTED_FORWARDER = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;
    address public constant TOKEN_HOLDER = 0xa109709ecfA91A80626ff3989D68F67F5b1dD12a;

    uint256 public constant PRICE = 10000000;

    uint256 requirements = 92785934;

    function setUp() public {
        TimeLock timeLockImplementation = new TimeLock(TRUSTED_FORWARDER);
        TimeLockCloneFactory timeLockCloneFactory = new TimeLockCloneFactory(address(timeLockImplementation));
        factory = new PrivateOfferFactory(timeLockCloneFactory);

        vm.prank(PAYMENT_TOKEN_PROVIDER);
        currency = new FakePaymentToken(0, 18);

        list = createAllowList(TRUSTED_FORWARDER, address(this));
        list.set(TOKEN_RECEIVER, requirements);
        list.set(TOKEN_HOLDER, requirements);
        list.set(address(currency), TRUSTED_CURRENCY);

        feeSettings = createFeeSettings(
            TRUSTED_FORWARDER,
            address(this),
            buildFeeTypes(100, 100, 100, wrongFeeReceiver, wrongFeeReceiver, ADMIN)
        );

        Token implementation = new Token(TRUSTED_FORWARDER);
        TokenProxyFactory tokenCloneFactory = new TokenProxyFactory(address(implementation));
        token = Token(
            tokenCloneFactory.createTokenProxy(
                0,
                TRUSTED_FORWARDER,
                feeSettings,
                ADMIN,
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

        PrivateOfferArguments memory arguments = PrivateOfferArguments(
            TOKEN_RECEIVER,
            TOKEN_RECEIVER,
            CURRENCY_RECEIVER,
            amount,
            PRICE,
            expiration,
            currency,
            token,
            address(0)
        );
        address expectedAddress = factory.predictPrivateOfferAddress(salt, arguments);

        uint256 tokenDecimals = token.decimals();

        vm.startPrank(PAYMENT_TOKEN_PROVIDER);
        currency.mint(TOKEN_RECEIVER, (amount * PRICE) / 10 ** tokenDecimals);
        vm.stopPrank();

        vm.prank(ADMIN);
        token.increaseMintingAllowance(expectedAddress, amount);

        vm.prank(TOKEN_RECEIVER);
        currency.approve(expectedAddress, (amount * PRICE) / 10 ** tokenDecimals);

        // make sure balances are as expected before deployment

        uint currencyAmount = (amount * PRICE) / 10 ** tokenDecimals;
        assertEq(currency.balanceOf(TOKEN_RECEIVER), currencyAmount);
        assertEq(currency.balanceOf(CURRENCY_RECEIVER), 0);
        assertEq(token.balanceOf(TOKEN_RECEIVER), 0);
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

        // make sure balances are as expected after deployment
        uint256 feeCollectorCurrencyBalanceBefore = currency.balanceOf(
            FeeSettings(address(token.feeSettings())).feeCollector()
        );
        vm.expectEmit(true, true, true, true, address(expectedAddress));
        emit Deal(TOKEN_RECEIVER, TOKEN_RECEIVER, amount, PRICE, currency, token);

        address inviteAddress = factory.deployPrivateOffer(salt, arguments);

        console.log(
            "feeCollector currency balance after deployment: %s",
            currency.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector())
        );

        assertEq(inviteAddress, expectedAddress, "deployed contract address is not correct");

        console.log("buyer balance: %s", currency.balanceOf(TOKEN_RECEIVER));
        console.log("receiver balance: %s", currency.balanceOf(CURRENCY_RECEIVER));
        console.log("buyer token balance: %s", token.balanceOf(TOKEN_RECEIVER));
        uint256 len;
        assembly {
            len := extcodesize(expectedAddress)
        }
        console.log("Deployed contract size: %s", len);
        assertEq(currency.balanceOf(TOKEN_RECEIVER), 0);

        assertEq(
            currency.balanceOf(CURRENCY_RECEIVER),
            currencyAmount - FeeSettings(address(token.feeSettings())).privateOfferFee(currencyAmount, address(token))
        );

        assertEq(
            currency.balanceOf(FeeSettings(address(token.feeSettings())).privateOfferFeeCollector(address(token))),
            feeCollectorCurrencyBalanceBefore +
                FeeSettings(address(token.feeSettings())).privateOfferFee(currencyAmount, address(token)),
            "feeCollector currency balance is not correct"
        );

        assertEq(token.balanceOf(TOKEN_RECEIVER), amount);

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

        PrivateOfferArguments memory arguments = PrivateOfferArguments(
            TOKEN_RECEIVER,
            TOKEN_RECEIVER,
            CURRENCY_RECEIVER,
            amount,
            PRICE,
            expiration,
            currency,
            token,
            TOKEN_HOLDER
        );
        address expectedAddress = factory.predictPrivateOfferAddress(salt, arguments);

        uint256 tokenDecimals = token.decimals();

        vm.startPrank(PAYMENT_TOKEN_PROVIDER);
        currency.mint(TOKEN_RECEIVER, (amount * PRICE) / 10 ** tokenDecimals);
        vm.stopPrank();

        vm.startPrank(ADMIN);
        token.increaseMintingAllowance(ADMIN, amount);
        token.mint(TOKEN_HOLDER, amount);
        vm.stopPrank();

        vm.startPrank(TOKEN_HOLDER);
        token.approve(expectedAddress, amount);
        vm.stopPrank();

        vm.prank(TOKEN_RECEIVER);
        currency.approve(expectedAddress, (amount * PRICE) / 10 ** tokenDecimals);

        // make sure balances are as expected before deployment

        uint currencyAmount = (amount * PRICE) / 10 ** tokenDecimals;
        assertEq(currency.balanceOf(TOKEN_RECEIVER), currencyAmount);
        assertEq(currency.balanceOf(CURRENCY_RECEIVER), 0);
        assertEq(token.balanceOf(TOKEN_RECEIVER), 0);
        assertEq(token.balanceOf(TOKEN_HOLDER), amount);
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
        emit Deal(TOKEN_RECEIVER, TOKEN_RECEIVER, amount, PRICE, currency, token);

        address inviteAddress = factory.deployPrivateOffer(salt, arguments);

        console.log(
            "feeCollector currency balance after deployment: %s",
            currency.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector())
        );

        assertEq(inviteAddress, expectedAddress, "deployed contract address is not correct");

        console.log("buyer balance: %s", currency.balanceOf(TOKEN_RECEIVER));
        console.log("receiver balance: %s", currency.balanceOf(CURRENCY_RECEIVER));
        console.log("buyer token balance: %s", token.balanceOf(TOKEN_RECEIVER));
        uint256 len;
        assembly {
            len := extcodesize(expectedAddress)
        }
        console.log("Deployed contract size: %s", len);
        assertEq(currency.balanceOf(TOKEN_RECEIVER), 0);

        assertEq(
            currency.balanceOf(CURRENCY_RECEIVER),
            currencyAmount - FeeSettings(address(token.feeSettings())).privateOfferFee(currencyAmount, address(token))
        );

        assertEq(
            currency.balanceOf(FeeSettings(address(token.feeSettings())).privateOfferFeeCollector(address(token))),
            feeCollectorCurrencyBalanceBefore +
                FeeSettings(address(token.feeSettings())).privateOfferFee(currencyAmount, address(token)),
            "feeCollector currency balance is not correct"
        );

        assertEq(token.balanceOf(TOKEN_RECEIVER), amount, "TOKEN_RECEIVER received wrong amount of tokens");
        assertEq(token.balanceOf(TOKEN_HOLDER), 0, "TOKEN_HOLDER still has tokens");
        assertEq(token.totalSupply(), expectedTotalTokenSupply, "token supply changed during deployment");

        assertEq(
            token.balanceOf(FeeSettings(address(token.feeSettings())).tokenFeeCollector(address(token))),
            FeeSettings(address(token.feeSettings())).tokenFee(amount, address(token))
        );
    }

    function _buildBaseArguments() internal view returns (PrivateOfferArguments memory) {
        return
            PrivateOfferArguments(
                CURRENCY_PAYER,
                TOKEN_RECEIVER,
                CURRENCY_RECEIVER,
                1e18,
                PRICE,
                block.timestamp + 1000,
                currency,
                token,
                address(0)
            );
    }

    function testRevertZeroCurrencyPayer() public {
        PrivateOfferArguments memory args = _buildBaseArguments();
        args.currencyPayer = address(0);
        vm.expectRevert("_arguments.currencyPayer can not be zero address");
        new PrivateOffer(args);
    }

    function testRevertZeroTokenReceiver() public {
        PrivateOfferArguments memory args = _buildBaseArguments();
        args.tokenReceiver = address(0);
        vm.expectRevert("_arguments.tokenReceiver can not be zero address");
        new PrivateOffer(args);
    }

    function testRevertZeroCurrencyReceiver() public {
        PrivateOfferArguments memory args = _buildBaseArguments();
        args.currencyReceiver = address(0);
        vm.expectRevert("_arguments.currencyReceiver can not be zero address");
        new PrivateOffer(args);
    }

    function testRevertZeroTokenPrice() public {
        PrivateOfferArguments memory args = _buildBaseArguments();
        args.tokenPrice = 0;
        vm.expectRevert("_arguments.tokenPrice can not be zero");
        new PrivateOffer(args);
    }

    function testRevertExpiredDeal() public {
        vm.warp(1000);
        PrivateOfferArguments memory args = _buildBaseArguments();
        args.expiration = block.timestamp - 1;
        vm.expectRevert("Deal expired");
        new PrivateOffer(args);
    }

    function testRevertZeroToken() public {
        PrivateOfferArguments memory args = _buildBaseArguments();
        args.token = Token(address(0));
        vm.expectRevert("_arguments.token can not be zero address");
        new PrivateOffer(args);
    }

    function testRevertZeroCurrency() public {
        PrivateOfferArguments memory args = _buildBaseArguments();
        args.currency = IERC20(address(0));
        vm.expectRevert("_arguments.currency can not be zero address");
        new PrivateOffer(args);
    }

    function testRevertZeroTokenAmount() public {
        PrivateOfferArguments memory args = _buildBaseArguments();
        args.tokenAmount = 0;
        vm.expectRevert("_arguments.tokenAmount can not be zero");
        new PrivateOffer(args);
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

        PrivateOfferArguments memory arguments = PrivateOfferArguments(
            CURRENCY_PAYER,
            TOKEN_RECEIVER,
            CURRENCY_RECEIVER,
            _tokenBuyAmount,
            _nominalPrice,
            expiration,
            currency,
            token,
            address(0)
        );
        address expectedAddress = factory.predictPrivateOfferAddress(salt, arguments);

        // set fees to 0, otherwise extra tokens are minted which causes an overflow
        FeeSettings _feeSettings = FeeSettings(address(token.feeSettings()));
        _feeSettings.planFeeChange(FeeTypes.CROWDINVESTING, 0, uint64(block.timestamp));
        _feeSettings.planFeeChange(FeeTypes.PRIVATE_OFFER, 0, uint64(block.timestamp));
        _feeSettings.planFeeChange(FeeTypes.TOKEN, 0, uint64(block.timestamp));
        _feeSettings.executeFeeChange(FeeTypes.TOKEN);
        _feeSettings.executeFeeChange(FeeTypes.CROWDINVESTING);
        _feeSettings.executeFeeChange(FeeTypes.PRIVATE_OFFER);

        vm.prank(ADMIN);
        token.increaseMintingAllowance(expectedAddress, _tokenBuyAmount);

        uint minCurrencyAmount = (_tokenBuyAmount * _nominalPrice) / 10 ** token.decimals();
        console.log("minCurrencyAmount: %s", minCurrencyAmount);
        uint maxCurrencyAmount = minCurrencyAmount + 1;
        console.log("maxCurrencyAmount: %s", maxCurrencyAmount);

        vm.prank(PAYMENT_TOKEN_PROVIDER);
        currency.mint(CURRENCY_PAYER, maxCurrencyAmount);

        vm.prank(CURRENCY_PAYER);
        currency.approve(expectedAddress, maxCurrencyAmount);

        // make sure balances are as expected before deployment

        console.log(
            "feeCollector currency balance: %s",
            currency.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector())
        );

        assertEq(currency.balanceOf(CURRENCY_PAYER), maxCurrencyAmount, "CurrencyPayer has wrong balance");
        assertEq(currency.balanceOf(CURRENCY_RECEIVER), 0, "CurrencyReceiver has wrong balance");
        assertEq(
            token.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector()),
            0,
            "feeCollector token balance is not correct"
        );
        assertEq(token.balanceOf(TOKEN_RECEIVER), 0);

        console.log(
            "feeCollector currency balance before deployment: %s",
            currency.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector())
        );
        // make sure balances are as expected after deployment
        uint256 currencyReceiverBalanceBefore = currency.balanceOf(CURRENCY_RECEIVER);

        address inviteAddress = factory.deployPrivateOffer(salt, arguments);

        console.log(
            "feeCollector currency balance after deployment: %s",
            currency.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector())
        );

        assertEq(inviteAddress, expectedAddress, "deployed contract address is not correct");

        console.log("CURRENCY_PAYER balance: %s", currency.balanceOf(CURRENCY_PAYER));
        console.log("CURRENCY_RECEIVER balance: %s", currency.balanceOf(CURRENCY_RECEIVER));
        console.log("TOKEN_RECEIVER token balance: %s", token.balanceOf(TOKEN_RECEIVER));
        uint256 len;
        assembly {
            len := extcodesize(expectedAddress)
        }
        console.log("Deployed contract size: %s", len);
        assertTrue(currency.balanceOf(CURRENCY_PAYER) <= 1, "CURRENCY_PAYER has too much currency left");

        assertTrue(
            currency.balanceOf(CURRENCY_RECEIVER) > currencyReceiverBalanceBefore,
            "CURRENCY_RECEIVER received no payment"
        );

        console.log(
            "feeCollector currency balance: %s",
            currency.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector())
        );

        assertTrue(maxCurrencyAmount - currency.balanceOf(CURRENCY_PAYER) >= 1, "CURRENCY_PAYER paid nothing");
        uint totalCurrencyReceived = currency.balanceOf(CURRENCY_RECEIVER) +
            currency.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector());
        console.log("totalCurrencyReceived: %s", totalCurrencyReceived);
        assertTrue(totalCurrencyReceived >= minCurrencyAmount, "Receiver and feeCollector received less than expected");

        assertTrue(totalCurrencyReceived <= maxCurrencyAmount, "Receiver and feeCollector received more than expected");

        assertEq(token.balanceOf(TOKEN_RECEIVER), _tokenBuyAmount, "TOKEN_RECEIVER received no tokens");
    }

    function testRoundUp0() public {
        // buy one token bit with PRICE 1 currency bit per full token
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
        // ); // amount * PRICE *10**18 < UINT256_MAX
        //vm.assume(_tokenPrice < UINT256_MAX / (100 * 10 ** token.decimals()));
        ensureCostIsRoundedUp(_tokenBuyAmount, _tokenPrice);
    }

    function ensureReverts(uint256 _tokenBuyAmount, uint256 _nominalPrice) public {
        bytes32 salt = bytes32(uint256(8));

        uint256 expiration = block.timestamp + 1000;

        PrivateOfferArguments memory arguments = PrivateOfferArguments(
            CURRENCY_PAYER,
            TOKEN_RECEIVER,
            CURRENCY_RECEIVER,
            _tokenBuyAmount,
            _nominalPrice,
            expiration,
            currency,
            token,
            address(0)
        );
        address expectedAddress = factory.predictPrivateOfferAddress(salt, arguments);

        vm.startPrank(ADMIN);
        console.log("expectedAddress: %s", token.mintingAllowance(expectedAddress));
        token.increaseMintingAllowance(expectedAddress, _tokenBuyAmount);
        vm.stopPrank();

        uint maxCurrencyAmount = UINT256_MAX;

        vm.prank(PAYMENT_TOKEN_PROVIDER);
        currency.mint(CURRENCY_PAYER, maxCurrencyAmount);
        vm.prank(CURRENCY_PAYER);
        currency.approve(expectedAddress, maxCurrencyAmount);

        vm.expectRevert("Create2: Failed on deploy");
        factory.deployPrivateOffer(salt, arguments);
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

        PrivateOfferArguments memory arguments = PrivateOfferArguments(
            CURRENCY_PAYER,
            TOKEN_RECEIVER,
            CURRENCY_RECEIVER,
            _tokenBuyAmount,
            _nominalPrice,
            expiration,
            currency,
            token,
            address(0)
        );
        address expectedAddress = factory.predictPrivateOfferAddress(salt, arguments);

        vm.startPrank(ADMIN);
        console.log("expectedAddress: %s", token.mintingAllowance(expectedAddress));
        token.increaseMintingAllowance(expectedAddress, _tokenBuyAmount);
        vm.stopPrank();

        uint maxCurrencyAmount = UINT256_MAX;

        vm.prank(PAYMENT_TOKEN_PROVIDER);
        currency.mint(CURRENCY_PAYER, maxCurrencyAmount);
        vm.prank(CURRENCY_PAYER);
        currency.approve(expectedAddress, maxCurrencyAmount);

        vm.prank(TOKEN_RECEIVER);
        currency.approve(expectedAddress, maxCurrencyAmount);

        vm.expectRevert("Create2: Failed on deploy");
        factory.deployPrivateOffer(salt, arguments);

        // restore trusted currency on allowlist and make sure it works again
        list.set(address(currency), TRUSTED_CURRENCY);
        factory.deployPrivateOffer(salt, arguments);
    }

    function testAcceptWithDifferentTokenReceiver(uint256 rawSalt) public {
        //uint rawSalt = 0;
        bytes32 salt = bytes32(rawSalt);

        //bytes memory creationCode = type(PrivateOffer).creationCode;
        uint256 tokenAmount = 20000000000000;
        uint256 expiration = block.timestamp + 1000;
        uint256 tokenDecimals = token.decimals();
        uint256 currencyAmount = (tokenAmount * PRICE) / 10 ** tokenDecimals;

        PrivateOfferArguments memory arguments = PrivateOfferArguments(
            CURRENCY_PAYER,
            TOKEN_RECEIVER,
            CURRENCY_RECEIVER,
            tokenAmount,
            PRICE,
            expiration,
            currency,
            token,
            address(0)
        );
        address expectedAddress = factory.predictPrivateOfferAddress(salt, arguments);

        vm.prank(ADMIN);
        token.increaseMintingAllowance(expectedAddress, tokenAmount);

        vm.prank(PAYMENT_TOKEN_PROVIDER);
        currency.mint(CURRENCY_PAYER, currencyAmount);

        vm.prank(CURRENCY_PAYER);
        currency.approve(expectedAddress, currencyAmount);

        // make sure balances are as expected before deployment

        assertEq(currency.balanceOf(CURRENCY_PAYER), currencyAmount);
        assertEq(currency.balanceOf(CURRENCY_RECEIVER), 0);
        assertEq(currency.balanceOf(TOKEN_RECEIVER), 0);
        assertEq(token.balanceOf(TOKEN_RECEIVER), 0);
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

        address inviteAddress = factory.deployPrivateOffer(salt, arguments);

        assertEq(inviteAddress, expectedAddress, "deployed contract address is not correct");

        console.log("payer balance: %s", currency.balanceOf(CURRENCY_PAYER));
        console.log("receiver balance: %s", currency.balanceOf(CURRENCY_RECEIVER));
        console.log("TOKEN_RECEIVER token balance: %s", token.balanceOf(TOKEN_RECEIVER));
        uint256 len;
        assembly {
            len := extcodesize(expectedAddress)
        }
        console.log("Deployed contract size: %s", len);
        assertEq(currency.balanceOf(CURRENCY_PAYER), 0);

        assertEq(
            currency.balanceOf(CURRENCY_RECEIVER),
            currencyAmount - token.feeSettings().privateOfferFee(currencyAmount, address(token))
        );

        assertEq(
            currency.balanceOf(token.feeSettings().privateOfferFeeCollector(address(token))),
            token.feeSettings().privateOfferFee(currencyAmount, address(token)),
            "feeCollector currency balance is not correct"
        );

        assertEq(token.balanceOf(TOKEN_RECEIVER), tokenAmount);

        assertEq(
            token.balanceOf(token.feeSettings().tokenFeeCollector(address(token))),
            token.feeSettings().tokenFee(tokenAmount, address(token))
        );
    }
}
