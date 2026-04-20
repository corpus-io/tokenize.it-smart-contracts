// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "../contracts/Token.sol";
import "../contracts/factories/FeeSettingsCloneFactory.sol";
import "../contracts/common/IFeeSettings.sol";
import "../contracts/factories/CrowdinvestingCloneFactory.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/PrivateOfferFactory.sol";
import "../contracts/factories/TimeLockCloneFactory.sol";
import "../contracts/factories/CoinvestedPositionCloneFactory.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/CloneCreators.sol";

contract FeeSettingsIntegrationTest is Test {
    FeeSettings feeSettings;
    uint32 customTokenFeeNumerator;
    uint32 customCrowdinvestingFeeNumerator;
    uint32 customPrivateOfferFeeNumerator;
    uint64 customFeeValidity;
    Token token;
    FakePaymentToken currency;
    PrivateOfferFactory privateOfferFactory;
    CrowdinvestingCloneFactory crowdinvestingCloneFactory;

    uint256 MAX_INT = type(uint256).max;

    address public constant PLATFORM_ADMIN = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant INVESTOR = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant COMPANY_ADMIN = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant PAYMENT_TOKEN_ADMIN = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant OWNER = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant RECEIVER = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant PAYMENT_TOKEN_PROVIDER = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant TRUSTED_FORWARDER = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    uint256 public constant PRICE = 3e18;

    uint256 public constant TOKEN_AMOUNT = 1000e18;
    uint256 public constant CURRENCY_AMOUNT = 3000e18;

    address public constant EXAMPLE_TOKEN_ADDRESS = address(74);

    function setUp() public {
        FeeSettings feeSettingsLogic = new FeeSettings(TRUSTED_FORWARDER);
        FeeSettingsCloneFactory feeSettingsCloneFactory = new FeeSettingsCloneFactory(address(feeSettingsLogic));
        customTokenFeeNumerator = 10;
        customCrowdinvestingFeeNumerator = 20;
        customPrivateOfferFeeNumerator = 30;
        customFeeValidity = uint64(101 * 365 days);
        FeeSettings.FeeTypeInit[] memory feeTypes = new FeeSettings.FeeTypeInit[](4);
        feeTypes[0] = FeeSettings.FeeTypeInit(FeeTypes.TOKEN, 500, 101, PLATFORM_ADMIN);
        feeTypes[1] = FeeSettings.FeeTypeInit(FeeTypes.CROWDINVESTING, 1000, 102, PLATFORM_ADMIN);
        feeTypes[2] = FeeSettings.FeeTypeInit(FeeTypes.PRIVATE_OFFER, 500, 103, PLATFORM_ADMIN);
        feeTypes[3] = FeeSettings.FeeTypeInit(FeeTypes.SECONDARY_MARKET, 500, 0, PLATFORM_ADMIN);
        vm.prank(PLATFORM_ADMIN);
        feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone("salt", TRUSTED_FORWARDER, PLATFORM_ADMIN, feeTypes)
        );

        vm.startPrank(PAYMENT_TOKEN_PROVIDER);
        currency = new FakePaymentToken(CURRENCY_AMOUNT, 18);
        currency.transfer(INVESTOR, CURRENCY_AMOUNT);
        vm.stopPrank();

        AllowList allowList = createAllowList(TRUSTED_FORWARDER, OWNER);
        vm.prank(OWNER);
        allowList.set(address(currency), TRUSTED_CURRENCY);

        Token tokenLogic = new Token(TRUSTED_FORWARDER);
        TokenProxyFactory tokenProxyFactory = new TokenProxyFactory(address(tokenLogic));
        token = Token(
            tokenProxyFactory.createTokenProxy(
                "salt",
                TRUSTED_FORWARDER,
                feeSettings,
                COMPANY_ADMIN,
                allowList,
                0,
                "Test Token",
                "TST"
            )
        );

        Crowdinvesting crowdinvestingLogic = new Crowdinvesting(TRUSTED_FORWARDER);
        crowdinvestingCloneFactory = new CrowdinvestingCloneFactory(address(crowdinvestingLogic));

        // using a fake vesting clone factory here because we don't need this functionality for this test
        privateOfferFactory = new PrivateOfferFactory(
            TimeLockCloneFactory(address(294)),
            CoinvestedPositionCloneFactory(address(1))
        );
    }

    function testMintUsesCustomFeeAndCollector(address _customFeeCollector) public {
        vm.assume(_customFeeCollector != address(0));
        vm.assume(_customFeeCollector != PLATFORM_ADMIN);
        vm.assume(_customFeeCollector != INVESTOR);
        vm.assume(_customFeeCollector != COMPANY_ADMIN);

        vm.warp(100 * 365 days);

        assertEq(token.balanceOf(INVESTOR), 0, "token.balanceOf(INVESTOR) != 0 before");
        assertEq(token.balanceOf(_customFeeCollector), 0, "token.balanceOf(customFeeCollector) != 0 before");

        vm.startPrank(PLATFORM_ADMIN);
        feeSettings.setCustomFee(FeeTypes.TOKEN, address(token), customTokenFeeNumerator, customFeeValidity);
        feeSettings.setCustomFeeCollector(FeeTypes.TOKEN, address(token), _customFeeCollector);
        vm.stopPrank();
        vm.prank(COMPANY_ADMIN);
        token.mint(INVESTOR, TOKEN_AMOUNT);

        assertEq(token.balanceOf(INVESTOR), TOKEN_AMOUNT, "token.balanceOf(INVESTOR) != 100e18 after");
        assertEq(
            token.balanceOf(_customFeeCollector),
            (TOKEN_AMOUNT * 10) / 10000,
            "token.balanceOf(customFeeCollector) != 3e18 after"
        );
    }

    function testPrivateOfferUsesCustomFeeAndCollector(address _customFeeCollector) public {
        vm.assume(_customFeeCollector != address(0));
        vm.assume(_customFeeCollector != INVESTOR);
        vm.assume(_customFeeCollector != PLATFORM_ADMIN);
        vm.assume(_customFeeCollector != COMPANY_ADMIN);
        vm.warp(100 * 365 days);

        vm.startPrank(PLATFORM_ADMIN);
        feeSettings.setCustomFee(FeeTypes.TOKEN, address(token), customTokenFeeNumerator, customFeeValidity);
        feeSettings.setCustomFee(
            FeeTypes.PRIVATE_OFFER,
            address(token),
            customPrivateOfferFeeNumerator,
            customFeeValidity
        );
        feeSettings.setCustomFeeCollector(FeeTypes.PRIVATE_OFFER, address(token), _customFeeCollector);
        vm.stopPrank();

        assertEq(token.balanceOf(INVESTOR), 0, "token.balanceOf(INVESTOR) != 0 before");
        assertEq(currency.balanceOf(_customFeeCollector), 0, "currency.balanceOf(customFeeCollector) != 0 before");

        // get private offer address
        address expectedPrivateOfferAddress = privateOfferFactory.predictPrivateOfferAddress(
            "salt",
            PrivateOfferArguments(
                INVESTOR,
                INVESTOR,
                COMPANY_ADMIN,
                TOKEN_AMOUNT,
                PRICE,
                block.timestamp + 1000,
                currency,
                token,
                address(0)
            )
        );

        // grant allowances
        vm.prank(COMPANY_ADMIN);
        token.increaseMintingAllowance(expectedPrivateOfferAddress, TOKEN_AMOUNT);

        vm.prank(INVESTOR);
        currency.increaseAllowance(expectedPrivateOfferAddress, CURRENCY_AMOUNT);

        // create private offer
        privateOfferFactory.deployPrivateOffer(
            "salt",
            PrivateOfferArguments(
                INVESTOR,
                INVESTOR,
                COMPANY_ADMIN,
                TOKEN_AMOUNT,
                PRICE,
                block.timestamp + 1000,
                currency,
                token,
                address(0)
            )
        );

        // check balances
        console.log("token.balanceOf(INVESTOR)", token.balanceOf(INVESTOR));
        assertEq(token.balanceOf(INVESTOR), TOKEN_AMOUNT, "token.balanceOf(INVESTOR) != 1000e18 after");
        console.log("token.balanceOf(PLATFORM_ADMIN)", token.balanceOf(PLATFORM_ADMIN));
        // hint: token fees are paid to platform admin because we do not set a custom token fee receiver
        assertEq(
            token.balanceOf(PLATFORM_ADMIN),
            (TOKEN_AMOUNT * 10) / 10000,
            "token.balanceOf(customFeeCollector) != 2e18 after"
        );

        console.log("currency.balanceOf(INVESTOR)", currency.balanceOf(INVESTOR));
        assertEq(currency.balanceOf(INVESTOR), 0, "currency.balanceOf(INVESTOR) != 0 after");
        console.log("currency.balanceOf(_customFeeCollector)", currency.balanceOf(_customFeeCollector));
        assertEq(
            currency.balanceOf(_customFeeCollector),
            (CURRENCY_AMOUNT * 30) / 10000,
            "currency.balanceOf(customFeeCollector) wrong after"
        );
    }

    function testCrowdinvestingUsesCustomFeeAndCollector(address _customFeeCollector) public {
        vm.assume(_customFeeCollector != address(0));
        vm.assume(_customFeeCollector != PLATFORM_ADMIN);
        vm.assume(_customFeeCollector != COMPANY_ADMIN);
        vm.assume(_customFeeCollector != INVESTOR);

        vm.warp(100 * 365 days);

        vm.startPrank(PLATFORM_ADMIN);
        feeSettings.setCustomFee(FeeTypes.TOKEN, address(token), customTokenFeeNumerator, customFeeValidity);
        feeSettings.setCustomFee(
            FeeTypes.CROWDINVESTING,
            address(token),
            customCrowdinvestingFeeNumerator,
            customFeeValidity
        );
        feeSettings.setCustomFeeCollector(FeeTypes.CROWDINVESTING, address(token), _customFeeCollector);
        vm.stopPrank();

        assertEq(token.balanceOf(INVESTOR), 0, "token.balanceOf(INVESTOR) != 0 before");
        assertEq(currency.balanceOf(_customFeeCollector), 0, "currency.balanceOf(customFeeCollector) != 0 before");
        assertEq(token.balanceOf(PLATFORM_ADMIN), 0, "token.balanceOf(PLATFORM_ADMIN) != 0 before");

        // set up crowdinvesting
        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            COMPANY_ADMIN,
            COMPANY_ADMIN,
            1,
            type(uint256).max,
            PRICE,
            PRICE,
            PRICE,
            type(uint256).max,
            IERC20(address(currency)),
            token,
            101 * 365 days,
            address(0),
            address(0)
        );

        Crowdinvesting crowdinvesting = Crowdinvesting(
            crowdinvestingCloneFactory.createCrowdinvestingClone("salt", TRUSTED_FORWARDER, arguments)
        );

        // grant allowances
        vm.prank(COMPANY_ADMIN);
        token.increaseMintingAllowance(address(crowdinvesting), TOKEN_AMOUNT);

        vm.prank(INVESTOR);
        currency.increaseAllowance(address(crowdinvesting), CURRENCY_AMOUNT);

        // buy
        vm.prank(INVESTOR);
        crowdinvesting.buy(TOKEN_AMOUNT, type(uint256).max, INVESTOR);

        // check balances
        console.log("token.balanceOf(INVESTOR)", token.balanceOf(INVESTOR));
        assertEq(token.balanceOf(INVESTOR), TOKEN_AMOUNT, "token.balanceOf(INVESTOR) != 1000e18 after");
        console.log("token.balanceOf(PLATFORM_ADMIN)", token.balanceOf(PLATFORM_ADMIN));
        // hint: token fees are paid to platform admin because we do not set a custom token fee receiver
        assertEq(
            token.balanceOf(PLATFORM_ADMIN),
            (TOKEN_AMOUNT) / 1000,
            "token.balanceOf(customFeeCollector) != 2e18 after"
        );

        console.log("currency.balanceOf(INVESTOR)", currency.balanceOf(INVESTOR));
        assertEq(currency.balanceOf(INVESTOR), 0, "currency.balanceOf(INVESTOR) != 0 after");
        console.log("currency.balanceOf(_customFeeCollector)", currency.balanceOf(_customFeeCollector));
        assertEq(
            currency.balanceOf(_customFeeCollector),
            (CURRENCY_AMOUNT * 2) / 1000,
            "currency.balanceOf(customFeeCollector) wrong after"
        );
    }
}
