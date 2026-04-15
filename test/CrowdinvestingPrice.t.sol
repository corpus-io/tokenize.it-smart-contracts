// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/CrowdinvestingCloneFactory.sol";
import "../contracts/factories/PriceLinearCloneFactory.sol";
import "../contracts/PriceLinear.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/MaliciousPaymentToken.sol";
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

    PriceLinear priceLinearLogicContract = new PriceLinear(TRUSTED_FORWARDER);
    PriceLinearCloneFactory priceLinearCloneFactory = new PriceLinearCloneFactory(address(priceLinearLogicContract));

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

    uint256 public constant PRICE = 7 * 10 ** PAYMENT_TOKEN_DECIMALS;
    uint256 public constant PRICE_MIN = 1 * 10 ** PAYMENT_TOKEN_DECIMALS;
    uint256 public constant PRICE_MAX = 100 * 10 ** PAYMENT_TOKEN_DECIMALS;

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

    function testActivateDynamicPricingAndEnforceMaxPrice(
        uint64 priceIncreasePerDuration,
        uint64 duration,
        uint64 startDate,
        uint64 testDate
    ) public {
        vm.assume(priceIncreasePerDuration > 0);
        vm.assume(duration > 0);
        vm.assume(startDate > 1 hours + 1);
        vm.assume(testDate > 0);
        // create oracle
        vm.warp(1 hours + 1); // otherwise, PRICE linear thinks it has to cool down
        PriceLinear priceLinear = PriceLinear(
            priceLinearCloneFactory.createPriceLinearClone(
                0,
                TRUSTED_FORWARDER,
                OWNER,
                priceIncreasePerDuration,
                duration,
                startDate,
                1,
                false,
                true
            )
        );
        // check cooldown start
        assertEq(crowdinvesting.coolDownStart(), 0, "Cooldown start not set correctly");

        // activate dynamic pricing
        vm.startPrank(OWNER);
        crowdinvesting.pause();
        crowdinvesting.activateDynamicPricing(priceLinear, PRICE_MIN, PRICE_MAX);
        assertEq(crowdinvesting.coolDownStart(), block.timestamp, "Cooldown start not set correctly");

        vm.warp(block.timestamp + crowdinvesting.delay() + 1);
        crowdinvesting.unpause();
        vm.stopPrank();

        // check dynamic pricing
        if (block.timestamp < startDate) {
            console.log("Start date not reached yet: ", startDate);
            console.log("Current PRICE: ", crowdinvesting.getPrice());
            assertEq(crowdinvesting.getPrice(), PRICE, "Price should not have changed yet");
        } else {
            console.log("Current PRICE: ", crowdinvesting.getPrice());
            console.log("Max PRICE: ", PRICE_MAX);
            console.log("PRICE plus increase: ", PRICE + priceIncreasePerDuration);
            assertTrue(crowdinvesting.getPrice() <= PRICE_MAX, "Price too high!");
            assertTrue(crowdinvesting.getPrice() >= PRICE_MIN, "Price too low!");
        }

        // check if the PRICE actually changed
        vm.warp(uint256(startDate) + duration);
        console.log("Current PRICE: ", crowdinvesting.getPrice());
        assertTrue(crowdinvesting.getPrice() > PRICE, "Price should have changed!");
    }

    function testActivateDynamicPricingWithAddress0Reverts() public {
        // activate dynamic pricing
        vm.startPrank(OWNER);
        crowdinvesting.pause();
        vm.expectRevert("_priceOracle can not be zero address");
        crowdinvesting.activateDynamicPricing(IPriceDynamic(address(0)), PRICE_MIN, PRICE_MAX);
    }

    function testDeactivateDynamicPricing() public {
        // create oracle
        vm.warp(1 hours + 1); // otherwise, PRICE linear thinks it has to cool down
        PriceLinear priceLinear = PriceLinear(
            priceLinearCloneFactory.createPriceLinearClone(
                0,
                TRUSTED_FORWARDER,
                OWNER,
                1e5,
                1,
                2 hours,
                1,
                false,
                true // PRICE will fall
            )
        );

        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            OWNER,
            payable(RECEIVER),
            MIN_AMOUNT_PER_BUYER,
            MAX_AMOUNT_PER_BUYER,
            PRICE,
            PRICE_MIN,
            PRICE_MAX,
            MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD,
            paymentToken,
            token,
            0,
            address(priceLinear),
            address(0)
        );

        crowdinvesting = Crowdinvesting(factory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, arguments));

        vm.warp(100 days);

        // check that PRICE is changed by oracle
        assertTrue(crowdinvesting.getPrice() > PRICE, "Price should have changed!");

        // disable dynamic pricing
        vm.startPrank(OWNER);
        crowdinvesting.pause();
        crowdinvesting.deactivateDynamicPricing();
        vm.warp(block.timestamp + crowdinvesting.delay() + 1);
        crowdinvesting.unpause();

        // check that PRICE is not changed anymore
        assertTrue(crowdinvesting.getPrice() == PRICE, "Price should not have changed!");
    }

    function testActivateDynamicPricingOnDeployAndEnforceMinPrice(
        uint64 priceChangePerDuration,
        uint64 duration,
        uint64 startDate,
        uint64 testDate
    ) public {
        vm.assume(priceChangePerDuration > 0);
        vm.assume(duration > 0);
        vm.assume(startDate > 1 hours + 1);
        vm.assume(testDate > 0);

        // create oracle
        vm.warp(1 hours + 1); // otherwise, PRICE linear thinks it has to cool down
        PriceLinear priceLinear = PriceLinear(
            priceLinearCloneFactory.createPriceLinearClone(
                0,
                TRUSTED_FORWARDER,
                OWNER,
                priceChangePerDuration,
                duration,
                startDate,
                1,
                false,
                false // PRICE will fall
            )
        );

        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            OWNER,
            payable(RECEIVER),
            MIN_AMOUNT_PER_BUYER,
            MAX_AMOUNT_PER_BUYER,
            PRICE,
            PRICE_MIN,
            PRICE_MAX,
            MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD,
            paymentToken,
            token,
            0,
            address(priceLinear),
            address(0)
        );

        crowdinvesting = Crowdinvesting(factory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, arguments));

        // check dynamic pricing
        if (block.timestamp < startDate) {
            // PRICE can not change before start date
            console.log("Start date not reached yet: ", startDate);
            console.log("Current PRICE: ", crowdinvesting.getPrice());
            assertEq(crowdinvesting.getPrice(), PRICE, "Price should not have changed yet");
        } else {
            // PRICE can never exceed bounds
            console.log("Current PRICE: ", crowdinvesting.getPrice());
            console.log("Min PRICE: ", PRICE_MIN);
            console.log("PRICE plus increase: ", PRICE + priceChangePerDuration);
            assertTrue(crowdinvesting.getPrice() >= PRICE_MIN, "Price too low!");
            assertTrue(crowdinvesting.getPrice() <= PRICE_MAX, "Price too high!");
        }

        // check if the PRICE actually changed
        vm.warp(uint256(startDate) + duration);
        console.log("Current PRICE: ", crowdinvesting.getPrice());
        assertTrue(crowdinvesting.getPrice() < PRICE, "Price should have changed!");
    }

    function testActivateDynamicPricingOnDeployFixed() public {
        uint64 priceChangePerDuration = uint64(1 * 10 ** PAYMENT_TOKEN_DECIMALS);
        uint64 duration = 1 days;
        uint64 startDate = 2000000000; // Wednesday, 18. May 2033 03:33:20
        uint32 stepWidth = 1 hours;

        // with these parameters, the PRICE should change every hour for 93 days until it reaches 100e6

        // create oracle
        PriceLinear priceLinear = PriceLinear(
            priceLinearCloneFactory.createPriceLinearClone(
                0,
                TRUSTED_FORWARDER,
                OWNER,
                priceChangePerDuration,
                duration,
                startDate,
                stepWidth,
                false,
                true // PRICE will rise
            )
        );

        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            OWNER,
            payable(RECEIVER),
            MIN_AMOUNT_PER_BUYER,
            MAX_AMOUNT_PER_BUYER,
            PRICE,
            PRICE_MIN,
            PRICE_MAX,
            MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD,
            paymentToken,
            token,
            0,
            address(priceLinear),
            address(0)
        );

        crowdinvesting = Crowdinvesting(factory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, arguments));

        // check dynamic pricing
        vm.warp(uint256(startDate));
        assertEq(crowdinvesting.getPrice(), PRICE, "Price should not have changed yet 1");

        vm.warp(uint256(startDate) + stepWidth - 1);
        assertEq(crowdinvesting.getPrice(), PRICE, "Price should not have changed yet 2");

        vm.warp(uint256(startDate) + stepWidth);
        assertEq(
            crowdinvesting.getPrice(),
            PRICE + (priceChangePerDuration * stepWidth) / duration,
            "Price should have changed by 1 step 1"
        );

        vm.warp(uint256(startDate) + stepWidth + 45 minutes);
        assertEq(
            crowdinvesting.getPrice(),
            PRICE + (priceChangePerDuration * stepWidth) / duration,
            "Price should have changed by 1 step 2"
        );

        vm.warp(uint256(startDate) + 3 * stepWidth);
        assertEq(
            crowdinvesting.getPrice(),
            PRICE + (3 * (priceChangePerDuration * stepWidth)) / duration,
            "Price should have changed by 3 steps"
        );

        vm.warp(uint256(startDate) + 100 * stepWidth - 1);
        assertEq(
            crowdinvesting.getPrice(),
            PRICE + (99 * (priceChangePerDuration * stepWidth)) / duration,
            "Price should have changed by 99 steps"
        );

        vm.warp(uint256(startDate) + duration); // after 1 day, PRICE changed by priceChangePerDuration
        assertEq(
            crowdinvesting.getPrice(),
            PRICE + priceChangePerDuration,
            "Price should have changed by 10 * 24 steps"
        );

        // I need to check manually, too
        assertEq(crowdinvesting.getPrice(), 8e6, "Price should be 8e6 now");

        vm.warp(uint256(startDate) + 93 * duration - 1); // after 93 days, PRICE changed by 93 * priceChangePerDuration
        assertEq(
            crowdinvesting.getPrice(),
            PRICE + ((92 * 24 + 23) * (priceChangePerDuration * stepWidth)) / duration,
            "This should be the last second with a slightly cheaper PRICE 1"
        );
        assertTrue(
            crowdinvesting.getPrice() < PRICE_MAX,
            "This should be the last second with a slightly cheaper PRICE 2"
        );

        vm.warp(uint256(startDate) + 93 * duration); // after 93 days, PRICE is limited by PRICE_MAX
        assertEq(crowdinvesting.getPrice(), PRICE_MAX, "Price should be PRICE_MAX now");

        vm.warp(uint256(startDate) + 3000 days); // after 93 days, PRICE is limited by PRICE_MAX
        assertEq(crowdinvesting.getPrice(), PRICE_MAX, "Price should be PRICE_MAX now");

        vm.warp(type(uint64).max);
        assertEq(crowdinvesting.getPrice(), PRICE_MAX, "Price should be PRICE_MAX now");
    }

    function testChangingPriceDisablesPriceDynamic() public {
        // create oracle
        vm.warp(1 hours + 1); // otherwise, PRICE linear thinks it has to cool down
        PriceLinear priceLinear = PriceLinear(
            priceLinearCloneFactory.createPriceLinearClone(
                0,
                TRUSTED_FORWARDER,
                OWNER,
                1e10,
                1,
                2 hours,
                1,
                false,
                true // PRICE will rise
            )
        );

        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            OWNER,
            payable(RECEIVER),
            MIN_AMOUNT_PER_BUYER,
            MAX_AMOUNT_PER_BUYER,
            PRICE,
            PRICE_MIN,
            PRICE_MAX,
            MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD,
            paymentToken,
            token,
            0,
            address(priceLinear),
            address(0)
        );

        crowdinvesting = Crowdinvesting(factory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, arguments));

        vm.warp(200 days);

        console.log("Oracle address: ", address(crowdinvesting.priceOracle()));
        console.log("Price through oracle: ", priceLinear.getPrice(PRICE));
        console.log("Price through crowdinvesting: ", crowdinvesting.getPrice());
        // check that PRICE is changed by oracle
        assertTrue(crowdinvesting.priceBase() == PRICE, "Price not as expected");
        assertTrue(crowdinvesting.getPrice() > PRICE, "Price should have changed!");

        IERC20 newCurrency = IERC20(address(20));
        vm.prank(OWNER);
        list.set(address(newCurrency), TRUSTED_CURRENCY);

        // change PRICE
        vm.startPrank(OWNER);
        crowdinvesting.pause();
        crowdinvesting.setCurrencyAndTokenPrice(newCurrency, PRICE / 2);
        vm.warp(201 days);
        crowdinvesting.unpause();

        // check that PRICE is not changed anymore
        assertTrue(crowdinvesting.getPrice() == PRICE / 2, "Price should not have changed!");
        assertTrue(crowdinvesting.priceBase() == PRICE / 2, "Token PRICE should have changed!");
    }
}
