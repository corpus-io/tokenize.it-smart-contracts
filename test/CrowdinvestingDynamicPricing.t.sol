// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/FeeSettingsCloneFactory.sol";
import "../contracts/factories/CrowdinvestingCloneFactory.sol";
import "../contracts/factories/PriceLinearCloneFactory.sol";
import "../contracts/common/IFeeSettings.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/MaliciousPaymentToken.sol";
import "./resources/CloneCreators.sol";

/// fixture that always returns max PRICE
contract MaxPriceOracle is IPriceDynamic {
    uint256 nonsensePrice; // this only exists to silence compiler warnings

    constructor() {
        nonsensePrice = 7;
    }

    // solhint-disable-next-line
    function getPrice(uint256 basePrice) external view returns (uint256) {
        // this always returns 0
        basePrice = nonsensePrice > basePrice ? nonsensePrice : basePrice;
        return basePrice < type(uint256).max ? type(uint256).max : basePrice;
    }
}

/// fixture that always returns max PRICE
contract MinPriceOracle is IPriceDynamic {
    uint256 nonsensePrice; // this only exists to silence compiler warnings

    constructor() {
        nonsensePrice = 7;
    }

    // solhint-disable-next-line
    function getPrice(uint256 basePrice) external view returns (uint256) {
        // this always returns type(uint256).max
        basePrice = nonsensePrice > basePrice ? nonsensePrice : basePrice;
        return basePrice > 0 ? 0 : basePrice;
    }
}

contract CrowdinvestingDynamicPricingTest is Test {
    event CurrencyReceiverChanged(address indexed);
    event MinAmountPerReceiverChanged(uint256);
    event MaxAmountPerReceiverChanged(uint256);
    event TokenPriceAndCurrencyChanged(uint256, IERC20 indexed);
    event MaxAmountOfTokenToBeSoldChanged(uint256);
    event TokensBought(address indexed BUYER, uint256 tokenAmount, uint256 currencyAmount);

    CrowdinvestingCloneFactory factory;
    Crowdinvesting crowdinvesting;
    AllowList list;
    IFeeSettingsV2 feeSettings;

    TokenProxyFactory tokenCloneFactory;
    Token token;
    FakePaymentToken paymentToken;
    PriceLinearCloneFactory priceLinearCloneFactory;

    address public constant COMPANY_ADMIN = address(1);
    address public constant BUYER = address(2);
    address public constant MINT_ALLOWER = address(3);
    address public constant MINTER = address(4);
    address public constant OWNER = address(5);
    address public constant RECEIVER = address(6);
    address public constant PAYMENT_TOKEN_PROVIDER = address(7);
    address public constant TRUSTED_FORWARDER = address(8);
    address public constant PLATFORM_ADMIN = address(9);

    uint8 public constant PAYMENT_TOKEN_DECIMALS = 6;
    uint256 public constant PAYMENT_TOKEN_AMOUNT = 1000 * 10 ** PAYMENT_TOKEN_DECIMALS;

    uint256 public constant PRICE = 7 * 10 ** PAYMENT_TOKEN_DECIMALS; // 7 payment tokens per token

    uint256 public constant MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD = 20 * 10 ** 18; // 20 token
    uint256 public constant MAX_AMOUNT_PER_RECEIVER = MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 2; // 10 token
    uint256 public constant MIN_AMOUNT_PER_RECEIVER = MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 200; // 0.1 token

    function setUp() public {
        // set up currency
        vm.prank(PAYMENT_TOKEN_PROVIDER);
        paymentToken = new FakePaymentToken(PAYMENT_TOKEN_AMOUNT, PAYMENT_TOKEN_DECIMALS); // 1000 tokens with 6 decimals
        // transfer currency to BUYER
        vm.prank(PAYMENT_TOKEN_PROVIDER);
        paymentToken.transfer(BUYER, PAYMENT_TOKEN_AMOUNT);
        assertTrue(paymentToken.balanceOf(BUYER) == PAYMENT_TOKEN_AMOUNT);

        // set up platform
        vm.prank(PLATFORM_ADMIN);
        list = createAllowList(TRUSTED_FORWARDER, OWNER);
        vm.prank(OWNER);
        list.set(address(paymentToken), TRUSTED_CURRENCY);

        vm.startPrank(PLATFORM_ADMIN);
        FeeSettings feeLogic = new FeeSettings(TRUSTED_FORWARDER);
        FeeSettingsCloneFactory feeSettingsCloneFactory = new FeeSettingsCloneFactory(address(feeLogic));
        {
            FeeSettings.FeeTypeInit[] memory feeTypes = new FeeSettings.FeeTypeInit[](4);
            feeTypes[0] = FeeSettings.FeeTypeInit(FeeTypes.TOKEN, 500, 100, PLATFORM_ADMIN);
            feeTypes[1] = FeeSettings.FeeTypeInit(FeeTypes.CROWDINVESTING, 1000, 100, PLATFORM_ADMIN);
            feeTypes[2] = FeeSettings.FeeTypeInit(FeeTypes.PRIVATE_OFFER, 500, 100, PLATFORM_ADMIN);
            feeTypes[3] = FeeSettings.FeeTypeInit(FeeTypes.SECONDARY_MARKET, 500, 0, PLATFORM_ADMIN);
            feeSettings = IFeeSettingsV2(
                feeSettingsCloneFactory.createFeeSettingsClone(0, TRUSTED_FORWARDER, PLATFORM_ADMIN, feeTypes)
            );
        }

        // create token
        address tokenLogicContract = address(new Token(TRUSTED_FORWARDER));
        tokenCloneFactory = new TokenProxyFactory(tokenLogicContract);
        token = Token(
            tokenCloneFactory.createTokenProxy(
                0,
                TRUSTED_FORWARDER,
                feeSettings,
                COMPANY_ADMIN,
                list,
                0x0,
                "TESTTOKEN",
                "TEST"
            )
        );

        // create fundraising
        factory = new CrowdinvestingCloneFactory(address(new Crowdinvesting(TRUSTED_FORWARDER)));
        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            COMPANY_ADMIN,
            payable(RECEIVER),
            MIN_AMOUNT_PER_RECEIVER,
            MAX_AMOUNT_PER_RECEIVER,
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

        vm.stopPrank();

        // allow crowdinvesting contract to mint
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(COMPANY_ADMIN);
        token.grantRole(roleMintAllower, MINT_ALLOWER);
        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(address(crowdinvesting), MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD);

        // give crowdinvesting contract allowance
        vm.prank(BUYER);
        paymentToken.approve(address(crowdinvesting), PAYMENT_TOKEN_AMOUNT);

        // set up PRICE oracle factory
        PriceLinear priceLinearLogicContract = new PriceLinear(TRUSTED_FORWARDER);
        priceLinearCloneFactory = new PriceLinearCloneFactory(address(priceLinearLogicContract));
    }

    function testDynamicPricingLinearTime(uint64 timeShift) public {
        vm.assume(timeShift > 1 days);
        vm.warp(0);
        uint256 startTime = 1 days + 1;

        vm.startPrank(COMPANY_ADMIN);

        // set up PRICE oracle to increase the PRICE by 1 payment token per second
        PriceLinear priceOracle = PriceLinear(
            priceLinearCloneFactory.createPriceLinearClone(
                0,
                TRUSTED_FORWARDER,
                COMPANY_ADMIN,
                1e6,
                1,
                uint64(startTime),
                1,
                false,
                true
            )
        );

        // configure crowdinvesting to use oracle
        crowdinvesting.pause();
        crowdinvesting.activateDynamicPricing(
            IPriceDynamic(priceOracle),
            crowdinvesting.priceBase(),
            crowdinvesting.priceBase() * 2
        );
        vm.warp(startTime);
        crowdinvesting.unpause();

        vm.stopPrank();

        // check time and PRICE
        console.log("Timestamp matches tomorrow: %s", block.timestamp == startTime);
        uint256 currentPrice = crowdinvesting.getPrice();
        console.log("Price: %s", currentPrice);
        assertTrue(currentPrice == PRICE, "Price should be equal to base PRICE before start time");

        // check PRICE 1 second later
        vm.warp(startTime + 1);
        currentPrice = crowdinvesting.getPrice();
        console.log("Price: %s", currentPrice);
        assertTrue(currentPrice == PRICE + 1e6, "Price should be equal to base PRICE + 1 payment token");

        // buy now and make sure this PRICE was used
        assertEq(token.balanceOf(BUYER), 0, "Buyer should have 0 tokens before");
        uint256 buyerPaymentTokenBalanceBefore = paymentToken.balanceOf(BUYER);
        vm.prank(BUYER);
        crowdinvesting.buy(1e18, type(uint256).max, BUYER);
        assertTrue(token.balanceOf(BUYER) == 1e18, "Buyer should have 1 token");
        assertEq(
            paymentToken.balanceOf(BUYER),
            buyerPaymentTokenBalanceBefore - currentPrice,
            "Buyer should have paid currentPrice"
        );

        // check PRICE 4 seconds later
        vm.warp(startTime + 4);
        currentPrice = crowdinvesting.getPrice();
        console.log("Price: %s", currentPrice);
        assertTrue(currentPrice == PRICE + 4 * 1e6, "Price should be equal to base PRICE + 4 payment token");

        // check PRICE much later
        vm.warp(startTime + 1 days);
        currentPrice = crowdinvesting.getPrice();
        console.log("Price: %s", currentPrice);
        assertTrue(currentPrice == PRICE * 2, "Price should be equal to max PRICE");

        // check PRICE timeShift later
        vm.warp(startTime + timeShift);
        currentPrice = crowdinvesting.getPrice();
        console.log("Price: %s", currentPrice);
        assertTrue(currentPrice == PRICE * 2, "Price should be equal to max PRICE after timeShift");
    }

    function testMaxPrice(uint256 maxPrice) public {
        vm.assume(maxPrice >= PRICE);
        vm.warp(0);

        // deploy max PRICE oracle
        MaxPriceOracle maxPriceOracle = new MaxPriceOracle();

        // configure crowdinvesting to use oracle
        vm.startPrank(COMPANY_ADMIN);
        crowdinvesting.pause();
        crowdinvesting.activateDynamicPricing(IPriceDynamic(maxPriceOracle), crowdinvesting.priceBase(), maxPrice);
        vm.warp(1 days + 1);
        crowdinvesting.unpause();

        vm.stopPrank();

        // check PRICE
        uint256 currentPrice = crowdinvesting.getPrice();
        console.log("Price: %s", currentPrice);
        assertTrue(currentPrice == maxPrice, "Price should be equal to max PRICE");
    }

    function testMinPrice(uint256 minPrice) public {
        vm.assume(minPrice <= PRICE);
        vm.warp(0);

        // deploy max PRICE oracle
        MinPriceOracle maxPriceOracle = new MinPriceOracle();

        // configure crowdinvesting to use oracle
        vm.startPrank(COMPANY_ADMIN);
        crowdinvesting.pause();
        crowdinvesting.activateDynamicPricing(IPriceDynamic(maxPriceOracle), minPrice, crowdinvesting.priceBase());
        vm.warp(1 days + 1);
        crowdinvesting.unpause();

        vm.stopPrank();

        // check PRICE
        uint256 currentPrice = crowdinvesting.getPrice();
        console.log("Price: %s", currentPrice);
        assertTrue(currentPrice == minPrice, "Price should be equal to min PRICE");
    }
}
