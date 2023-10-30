// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/TokenCloneFactory.sol";
import "../contracts/FeeSettings.sol";
import "../contracts/PublicFundraisingCloneFactory.sol";
import "../contracts/PriceLinearTime.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/MaliciousPaymentToken.sol";

contract PublicFundraisingTest is Test {
    event CurrencyReceiverChanged(address indexed);
    event MinAmountPerBuyerChanged(uint256);
    event MaxAmountPerBuyerChanged(uint256);
    event TokenPriceAndCurrencyChanged(uint256, IERC20 indexed);
    event MaxAmountOfTokenToBeSoldChanged(uint256);
    event TokensBought(address indexed buyer, uint256 tokenAmount, uint256 currencyAmount);

    PublicFundraisingCloneFactory factory;
    PublicFundraising raise;
    AllowList list;
    IFeeSettingsV2 feeSettings;

    TokenCloneFactory tokenCloneFactory;
    Token token;
    FakePaymentToken paymentToken;

    address public constant companyAdmin = address(1);
    address public constant buyer = address(2);
    address public constant mintAllower = address(3);
    address public constant minter = address(4);
    address public constant owner = address(5);
    address public constant receiver = address(6);
    address public constant paymentTokenProvider = address(7);
    address public constant trustedForwarder = address(8);
    address public constant platformAdmin = address(9);

    uint8 public constant paymentTokenDecimals = 6;
    uint256 public constant paymentTokenAmount = 1000 * 10 ** paymentTokenDecimals;

    uint256 public constant price = 7 * 10 ** paymentTokenDecimals; // 7 payment tokens per token

    uint256 public constant maxAmountOfTokenToBeSold = 20 * 10 ** 18; // 20 token
    uint256 public constant maxAmountPerBuyer = maxAmountOfTokenToBeSold / 2; // 10 token
    uint256 public constant minAmountPerBuyer = maxAmountOfTokenToBeSold / 200; // 0.1 token

    function setUp() public {
        // set up currency
        vm.prank(paymentTokenProvider);
        paymentToken = new FakePaymentToken(paymentTokenAmount, paymentTokenDecimals); // 1000 tokens with 6 decimals
        // transfer currency to buyer
        vm.prank(paymentTokenProvider);
        paymentToken.transfer(buyer, paymentTokenAmount);
        assertTrue(paymentToken.balanceOf(buyer) == paymentTokenAmount);

        // set up platform
        vm.startPrank(platformAdmin);
        list = new AllowList();
        Fees memory fees = Fees(100, 100, 100, 100);
        feeSettings = new FeeSettings(fees, platformAdmin, platformAdmin, platformAdmin);

        // create token
        address tokenLogicContract = address(new Token(trustedForwarder));
        tokenCloneFactory = new TokenCloneFactory(tokenLogicContract);
        token = Token(
            tokenCloneFactory.createTokenClone(
                0,
                trustedForwarder,
                feeSettings,
                companyAdmin,
                list,
                0x0,
                "TESTTOKEN",
                "TEST"
            )
        );

        // create fundraising
        factory = new PublicFundraisingCloneFactory(address(new PublicFundraising(trustedForwarder)));

        raise = PublicFundraising(
            factory.createPublicFundraisingClone(
                0,
                trustedForwarder,
                companyAdmin,
                payable(receiver),
                minAmountPerBuyer,
                maxAmountPerBuyer,
                price,
                maxAmountOfTokenToBeSold,
                paymentToken,
                token
            )
        );

        vm.stopPrank();

        // allow raise contract to mint
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(companyAdmin);
        token.grantRole(roleMintAllower, mintAllower);
        vm.prank(mintAllower);
        token.increaseMintingAllowance(address(raise), maxAmountOfTokenToBeSold);

        // give raise contract allowance
        vm.prank(buyer);
        paymentToken.approve(address(raise), paymentTokenAmount);
    }

    function testDynamicPricingLinearTime(uint128 timeShift) public {
        vm.assume(timeShift > 1 days);

        vm.startPrank(companyAdmin);

        // set up price oracle to increase the price by 1 payment token per second
        PriceLinearTime priceOracle = new PriceLinearTime(trustedForwarder);
        priceOracle.initialize(companyAdmin, 1e6, 1, uint64(block.timestamp + 1 days + 1));

        // configure raise to use oracle
        raise.pause();
        uint256 startTime = block.timestamp + 1 days + 1;
        raise.activateDynamicPricing(IPriceDynamic(priceOracle), raise.priceBase(), raise.priceBase() * 2);
        vm.warp(startTime);
        raise.unpause();

        // check time and price
        console.log("Timestamp matches tomorrow: %s", block.timestamp == startTime);
        uint256 currentPrice = raise.getPrice();
        console.log("Price: %s", currentPrice);
        assertTrue(currentPrice == price);

        // check price 1 second later
        vm.warp(startTime + 1);
        currentPrice = raise.getPrice();
        console.log("Price: %s", currentPrice);
        assertTrue(currentPrice == price + 1e6);

        // check price 1 day later
        vm.warp(startTime + 1 days);
        currentPrice = raise.getPrice();
        console.log("Price: %s", currentPrice);
        assertTrue(currentPrice == price + 1e6 * 1 days);

        // check price timeShift later
        vm.warp(startTime + timeShift);
        currentPrice = raise.getPrice();
        console.log("Price: %s", currentPrice);
        assertTrue(currentPrice == price + 1e6 * uint256(timeShift));
    }
}
