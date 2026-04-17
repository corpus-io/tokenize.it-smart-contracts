// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "../contracts/factories/CrowdinvestingCloneFactory.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/FeeSettingsCloneFactory.sol";
import "../contracts/common/IFeeSettings.sol";
import "./resources/ERC2771Helper.sol";
import "./resources/CloneCreators.sol";

contract CrowdinvestingCloneFactoryTest is Test {
    using ECDSA for bytes32;

    AllowList allowList;
    FeeSettings feeSettings;
    TokenProxyFactory tokenFactory;
    Crowdinvesting fundraisingImplementation;
    CrowdinvestingCloneFactory fundraisingFactory;
    address public constant TRUSTED_FORWARDER = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;
    address public constant ADMIN = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant REQUIRER = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant MINT_ALLOWER = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant MINTER = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant BURNER = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;
    address public constant TRANSFERER_ADMIN = 0x5109709EcFA91a80626ff3989d68f67F5B1dD125;
    address public constant TRANSFERER = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant PAUSER = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant FEE_SETTINGS_AND_ALLOW_LIST_OWNER = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;

    uint256 requirements = 0;

    // these are defined globally to make some tests work in spite of compiler limitations
    bytes32 public constant EXAMPLE_RAW_SALT = 0x00000000;
    address public constant EXAMPLE_TRUSTED_FORWARDER = address(52);
    address public constant EXAMPLE_OWNER = address(53);
    address public constant EXAMPLE_CURRENCY_RECEIVER = address(54);
    uint256 public constant EXAMPLE_MIN_AMOUNT_PER_BUYER = 1;
    uint256 public constant EXAMPLE_MAX_AMOUNT_PER_BUYER = type(uint256).max;
    uint256 public constant EXAMPLE_TOKEN_PRICE = 2;
    uint256 public constant EXAMPLE_MIN_TOKEN_PRICE = 1;
    uint256 public constant EXAMPLE_MAX_TOKEN_PRICE = type(uint256).max;
    uint256 public constant EXAMPLE_MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD = 82398479821374;
    IERC20 public constant EXAMPLE_CURRENCY = IERC20(address(1));
    Token exampleToken;
    uint256 public constant EXAMPLE_LAST_BUY_DATE = 0;
    address public constant EXAMPLE_PRICE_ORACLE = address(3);

    event RequirementsChanged(uint256 newRequirements);

    function setUp() public {
        vm.startPrank(FEE_SETTINGS_AND_ALLOW_LIST_OWNER);
        allowList = createAllowList(TRUSTED_FORWARDER, FEE_SETTINGS_AND_ALLOW_LIST_OWNER);

        FeeSettings feeSettingsLogicContract = new FeeSettings(TRUSTED_FORWARDER);
        FeeSettingsCloneFactory feeSettingsCloneFactory = new FeeSettingsCloneFactory(
            address(feeSettingsLogicContract)
        );
        {
            FeeSettings.FeeTypeInit[] memory feeTypes = new FeeSettings.FeeTypeInit[](4);
            feeTypes[0] = FeeSettings.FeeTypeInit(FeeTypes.TOKEN, 500, 100, FEE_SETTINGS_AND_ALLOW_LIST_OWNER);
            feeTypes[1] = FeeSettings.FeeTypeInit(
                FeeTypes.CROWDINVESTING,
                1000,
                100,
                FEE_SETTINGS_AND_ALLOW_LIST_OWNER
            );
            feeTypes[2] = FeeSettings.FeeTypeInit(FeeTypes.PRIVATE_OFFER, 500, 100, FEE_SETTINGS_AND_ALLOW_LIST_OWNER);
            feeTypes[3] = FeeSettings.FeeTypeInit(FeeTypes.SECONDARY_MARKET, 500, 0, FEE_SETTINGS_AND_ALLOW_LIST_OWNER);
            feeSettings = FeeSettings(
                feeSettingsCloneFactory.createFeeSettingsClone(
                    0,
                    TRUSTED_FORWARDER,
                    FEE_SETTINGS_AND_ALLOW_LIST_OWNER,
                    feeTypes
                )
            );
        }
        vm.stopPrank();

        vm.prank(FEE_SETTINGS_AND_ALLOW_LIST_OWNER);
        allowList.set(address(EXAMPLE_CURRENCY), TRUSTED_CURRENCY);

        Token tokenImplementation = new Token(TRUSTED_FORWARDER);
        tokenFactory = new TokenProxyFactory(address(tokenImplementation));

        exampleToken = Token(
            tokenFactory.createTokenProxy(
                "2",
                TRUSTED_FORWARDER,
                feeSettings,
                address(this),
                allowList,
                0,
                "Test Token",
                "TST"
            )
        );

        fundraisingImplementation = new Crowdinvesting(TRUSTED_FORWARDER);
        fundraisingFactory = new CrowdinvestingCloneFactory(address(fundraisingImplementation));
    }

    function testAddressPrediction1(
        uint256 _maxAmountPerBuyer,
        uint256 _tokenPrice,
        uint256 _tokenPriceMin,
        uint256 _tokenPriceMax,
        uint256 _maxAmountOfTokenToBeSold,
        IERC20 _currency,
        uint256 _lastBuyDate,
        address _priceOracle
    ) public {
        vm.assume(address(_currency) != address(0));
        vm.assume(EXAMPLE_MIN_AMOUNT_PER_BUYER > 0);
        vm.assume(_maxAmountPerBuyer >= EXAMPLE_MIN_AMOUNT_PER_BUYER);
        vm.assume(_tokenPrice > 0);
        vm.assume(_tokenPriceMin <= _tokenPrice);
        vm.assume(_tokenPriceMax >= _tokenPrice);
        vm.assume(_maxAmountOfTokenToBeSold > _maxAmountPerBuyer);
        vm.assume(_lastBuyDate > block.timestamp || _lastBuyDate == 0);

        vm.prank(FEE_SETTINGS_AND_ALLOW_LIST_OWNER);
        allowList.set(address(_currency), TRUSTED_CURRENCY);

        Token _token = Token(
            tokenFactory.createTokenProxy(
                0,
                TRUSTED_FORWARDER,
                feeSettings,
                address(this),
                allowList,
                0,
                "Test Token",
                "TST"
            )
        );

        // create new clone factory so we can use the local forwarder
        fundraisingImplementation = new Crowdinvesting(EXAMPLE_TRUSTED_FORWARDER);
        fundraisingFactory = new CrowdinvestingCloneFactory(address(fundraisingImplementation));

        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            EXAMPLE_OWNER,
            EXAMPLE_CURRENCY_RECEIVER,
            EXAMPLE_MIN_AMOUNT_PER_BUYER,
            _maxAmountPerBuyer,
            _tokenPrice,
            _tokenPriceMin,
            _tokenPriceMax,
            _maxAmountOfTokenToBeSold,
            _currency,
            _token,
            _lastBuyDate,
            _priceOracle,
            address(0)
        );

        address expected1 = fundraisingFactory.predictCloneAddress(
            keccak256(abi.encode(EXAMPLE_RAW_SALT, EXAMPLE_TRUSTED_FORWARDER, arguments))
        );

        address expected2 = fundraisingFactory.predictCloneAddress(
            EXAMPLE_RAW_SALT,
            EXAMPLE_TRUSTED_FORWARDER,
            arguments
        );

        assertEq(expected1, expected2, "address prediction with salt and params not equal");

        address actual = fundraisingFactory.createCrowdinvestingClone(
            EXAMPLE_RAW_SALT,
            EXAMPLE_TRUSTED_FORWARDER,
            arguments
        );
        assertEq(expected1, actual, "address prediction failed");
    }

    function testAddressPrediction2(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        address _currencyReceiver,
        uint256 _minAmountPerBuyer
    ) public {
        vm.assume(_trustedForwarder != address(0));
        vm.assume(_owner != address(0));
        vm.assume(_currencyReceiver != address(0));
        vm.assume(_minAmountPerBuyer > 0);

        // create new clone factory so we can use the local forwarder
        fundraisingImplementation = new Crowdinvesting(_trustedForwarder);
        fundraisingFactory = new CrowdinvestingCloneFactory(address(fundraisingImplementation));

        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            _owner,
            _currencyReceiver,
            _minAmountPerBuyer,
            EXAMPLE_MAX_AMOUNT_PER_BUYER,
            EXAMPLE_TOKEN_PRICE,
            EXAMPLE_MIN_TOKEN_PRICE,
            EXAMPLE_MAX_TOKEN_PRICE,
            EXAMPLE_MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD,
            EXAMPLE_CURRENCY,
            exampleToken,
            EXAMPLE_LAST_BUY_DATE,
            EXAMPLE_PRICE_ORACLE,
            address(0)
        );

        bytes32 salt = keccak256(abi.encode(_rawSalt, _trustedForwarder, arguments));

        address expected1 = fundraisingFactory.predictCloneAddress(salt);
        address expected2 = fundraisingFactory.predictCloneAddress(_rawSalt, _trustedForwarder, arguments);

        assertEq(expected1, expected2, "address prediction with salt and params not equal");

        address actual = fundraisingFactory.createCrowdinvestingClone(_rawSalt, _trustedForwarder, arguments);
        assertEq(expected1, actual, "address prediction failed");
    }

    function testChangingOneValueInStructChangesAddress(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        address _currencyReceiver,
        uint256 _minAmountPerBuyer
    ) public {
        vm.assume(_trustedForwarder != address(0));
        vm.assume(_owner != address(0));
        vm.assume(_currencyReceiver != address(0));
        vm.assume(_minAmountPerBuyer > 0);

        // create new clone factory so we can use the local forwarder
        fundraisingImplementation = new Crowdinvesting(_trustedForwarder);
        fundraisingFactory = new CrowdinvestingCloneFactory(address(fundraisingImplementation));

        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            _owner,
            _currencyReceiver,
            _minAmountPerBuyer,
            EXAMPLE_MAX_AMOUNT_PER_BUYER,
            EXAMPLE_TOKEN_PRICE,
            EXAMPLE_MIN_TOKEN_PRICE,
            EXAMPLE_MAX_TOKEN_PRICE,
            EXAMPLE_MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD,
            EXAMPLE_CURRENCY,
            exampleToken,
            EXAMPLE_LAST_BUY_DATE,
            EXAMPLE_PRICE_ORACLE,
            address(0)
        );

        address expected1 = fundraisingFactory.predictCloneAddress(_rawSalt, _trustedForwarder, arguments);

        arguments.maxAmountPerBuyer = EXAMPLE_MAX_AMOUNT_PER_BUYER - 1;

        address expected2 = fundraisingFactory.predictCloneAddress(_rawSalt, _trustedForwarder, arguments);

        assertFalse(expected1 == expected2, "these addresses can not be equal");
    }

    function testSecondDeploymentFails(
        bytes32 _rawSalt,
        address _owner,
        address _currencyReceiver,
        uint256 _minAmountPerBuyer,
        uint256 _maxAmountPerBuyer,
        uint256 _priceBase,
        uint256 _tokenPriceMin,
        uint256 _tokenPriceMax,
        uint256 _maxAmountOfTokenToBeSold,
        IERC20 _currency
    ) public {
        vm.assume(_owner != address(0));
        vm.assume(address(_currency) != address(0));
        vm.assume(_currencyReceiver != address(0));
        vm.assume(_minAmountPerBuyer > 0);
        vm.assume(_maxAmountPerBuyer >= _minAmountPerBuyer);
        vm.assume(_priceBase > 0);
        vm.assume(_tokenPriceMin <= _priceBase);
        vm.assume(_tokenPriceMax >= _priceBase);
        vm.assume(_maxAmountOfTokenToBeSold > _maxAmountPerBuyer);

        vm.prank(FEE_SETTINGS_AND_ALLOW_LIST_OWNER);
        allowList.set(address(_currency), TRUSTED_CURRENCY);

        Token _token = Token(
            tokenFactory.createTokenProxy(
                0,
                TRUSTED_FORWARDER,
                feeSettings,
                address(this),
                allowList,
                0,
                "Test Token",
                "TST"
            )
        );

        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            _owner,
            _currencyReceiver,
            _minAmountPerBuyer,
            _maxAmountPerBuyer,
            _priceBase,
            _tokenPriceMin,
            _tokenPriceMax,
            _maxAmountOfTokenToBeSold,
            _currency,
            _token,
            EXAMPLE_LAST_BUY_DATE,
            EXAMPLE_PRICE_ORACLE,
            address(0)
        );

        // deploy once
        fundraisingFactory.createCrowdinvestingClone(_rawSalt, TRUSTED_FORWARDER, arguments);

        // deploy again
        vm.expectRevert("ERC1167: create2 failed");
        fundraisingFactory.createCrowdinvestingClone(_rawSalt, TRUSTED_FORWARDER, arguments);
    }

    function testInitialization1(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        address _currencyReceiver,
        uint256 _minAmountPerBuyer,
        uint256 _maxAmountPerBuyer
    ) public {
        vm.assume(_trustedForwarder != address(0));
        vm.assume(_owner != address(0));
        vm.assume(_currencyReceiver != address(0));
        vm.assume(_minAmountPerBuyer > 0);
        vm.assume(_maxAmountPerBuyer >= _minAmountPerBuyer);

        // create new clone factory so we can use the local forwarder
        fundraisingImplementation = new Crowdinvesting(_trustedForwarder);
        fundraisingFactory = new CrowdinvestingCloneFactory(address(fundraisingImplementation));

        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            _owner,
            _currencyReceiver,
            _minAmountPerBuyer,
            _maxAmountPerBuyer,
            EXAMPLE_TOKEN_PRICE,
            EXAMPLE_MIN_TOKEN_PRICE,
            EXAMPLE_MAX_TOKEN_PRICE,
            EXAMPLE_MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD,
            EXAMPLE_CURRENCY,
            exampleToken,
            EXAMPLE_LAST_BUY_DATE,
            EXAMPLE_PRICE_ORACLE,
            address(0)
        );

        Crowdinvesting crowdinvesting = Crowdinvesting(
            fundraisingFactory.createCrowdinvestingClone(_rawSalt, _trustedForwarder, arguments)
        );

        assertTrue(crowdinvesting.isTrustedForwarder(_trustedForwarder), "TRUSTED_FORWARDER not set");
        assertEq(crowdinvesting.owner(), _owner, "owner not set");
        assertEq(crowdinvesting.currencyReceiver(), _currencyReceiver, "currencyReceiver not set");
        assertEq(crowdinvesting.minAmountPerBuyer(), _minAmountPerBuyer, "minAmountPerBuyer not set");
        assertEq(crowdinvesting.maxAmountPerBuyer(), _maxAmountPerBuyer, "maxAmountPerBuyer not set");
    }

    function testInitialization2(
        uint256 _maxAmountPerBuyer,
        uint256 _priceBase,
        uint256 _priceMin,
        uint256 _priceMax,
        uint256 _maxAmountOfTokenToBeSold,
        IERC20 _currency,
        uint256 _lastBuyDate,
        address _priceOracle
    ) public {
        vm.assume(address(_currency) != address(0));
        vm.assume(_priceBase > 0);
        vm.assume(_priceMin <= _priceBase);
        vm.assume(_priceMax >= _priceBase);
        vm.assume(_maxAmountOfTokenToBeSold > _maxAmountPerBuyer);
        vm.assume(_maxAmountPerBuyer > 0);
        vm.assume(_lastBuyDate > block.timestamp || _lastBuyDate == 0);

        vm.prank(FEE_SETTINGS_AND_ALLOW_LIST_OWNER);
        allowList.set(address(_currency), TRUSTED_CURRENCY);

        Token _token = Token(
            tokenFactory.createTokenProxy(
                0,
                TRUSTED_FORWARDER,
                feeSettings,
                address(this),
                allowList,
                0,
                "Test Token",
                "TST"
            )
        );

        // create new clone factory so we can use the local forwarder
        fundraisingImplementation = new Crowdinvesting(EXAMPLE_TRUSTED_FORWARDER);
        fundraisingFactory = new CrowdinvestingCloneFactory(address(fundraisingImplementation));

        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            EXAMPLE_OWNER,
            EXAMPLE_CURRENCY_RECEIVER,
            EXAMPLE_MIN_AMOUNT_PER_BUYER,
            _maxAmountPerBuyer,
            _priceBase,
            _priceMin,
            _priceMax,
            _maxAmountOfTokenToBeSold,
            _currency,
            _token,
            _lastBuyDate,
            _priceOracle,
            address(0)
        );

        Crowdinvesting crowdinvesting = Crowdinvesting(
            fundraisingFactory.createCrowdinvestingClone(EXAMPLE_RAW_SALT, EXAMPLE_TRUSTED_FORWARDER, arguments)
        );

        assertEq(crowdinvesting.maxAmountPerBuyer(), _maxAmountPerBuyer, "maxAmountPerBuyer not set");
        assertEq(crowdinvesting.priceBase(), _priceBase, "priceBase not set");

        assertEq(
            crowdinvesting.maxAmountOfTokenToBeSold(),
            _maxAmountOfTokenToBeSold,
            "maxAmountOfTokenToBeSold not set"
        );
        assertEq(address(crowdinvesting.currency()), address(_currency), "currency not set");
        assertEq(address(crowdinvesting.token()), address(_token), "token not set");
        assertEq(crowdinvesting.lastBuyDate(), _lastBuyDate, "lastBuyDate not set");
        assertEq(address(crowdinvesting.priceOracle()), _priceOracle, "priceOracle not set");

        if (_priceOracle != address(0)) {
            assertEq(crowdinvesting.priceMin(), _priceMin, "priceMin not set");
            assertEq(crowdinvesting.priceMax(), _priceMax, "priceMax not set");
        } else {
            assertEq(crowdinvesting.priceMin(), 0, "priceMin wrong");
            assertEq(crowdinvesting.priceMax(), 0, "priceMax wrong");
        }
    }

    function testInitializationRevertsWithUntrustedCurrency(address someCurrency, uint256 currencyAttributes) public {
        vm.assume(someCurrency != address(0));
        vm.assume(currencyAttributes != TRUSTED_CURRENCY);
        vm.prank(FEE_SETTINGS_AND_ALLOW_LIST_OWNER);
        allowList.set(someCurrency, currencyAttributes);

        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            EXAMPLE_OWNER,
            EXAMPLE_CURRENCY_RECEIVER,
            EXAMPLE_MIN_AMOUNT_PER_BUYER,
            EXAMPLE_MAX_AMOUNT_PER_BUYER,
            EXAMPLE_TOKEN_PRICE,
            EXAMPLE_MIN_TOKEN_PRICE,
            EXAMPLE_MAX_TOKEN_PRICE,
            EXAMPLE_MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD,
            IERC20(someCurrency),
            exampleToken,
            EXAMPLE_LAST_BUY_DATE,
            EXAMPLE_PRICE_ORACLE,
            address(0)
        );

        vm.expectRevert("currency needs to be on the allowlist with TRUSTED_CURRENCY attribute");
        fundraisingFactory.createCrowdinvestingClone("salt", TRUSTED_FORWARDER, arguments);

        // test deployment succeeds with trusted currency
        vm.prank(FEE_SETTINGS_AND_ALLOW_LIST_OWNER);
        allowList.set(someCurrency, TRUSTED_CURRENCY);
        fundraisingFactory.createCrowdinvestingClone("salt", TRUSTED_FORWARDER, arguments);
    }

    /*
        pausing and unpausing
    */
    function testPausing(address _admin, address rando) public {
        vm.assume(_admin != address(0));
        vm.assume(rando != address(0));
        vm.assume(rando != _admin);

        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            _admin,
            _admin,
            EXAMPLE_MIN_AMOUNT_PER_BUYER,
            EXAMPLE_MAX_AMOUNT_PER_BUYER,
            EXAMPLE_TOKEN_PRICE,
            EXAMPLE_MIN_TOKEN_PRICE,
            EXAMPLE_MAX_TOKEN_PRICE,
            EXAMPLE_MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD,
            EXAMPLE_CURRENCY,
            exampleToken,
            EXAMPLE_LAST_BUY_DATE,
            EXAMPLE_PRICE_ORACLE,
            address(0)
        );

        Crowdinvesting crowdinvesting = Crowdinvesting(
            fundraisingFactory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, arguments)
        );

        vm.prank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        crowdinvesting.pause();

        assertFalse(crowdinvesting.paused());
        vm.prank(_admin);
        crowdinvesting.pause();
        assertTrue(crowdinvesting.paused());

        vm.prank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        crowdinvesting.unpause();

        // can't buy when paused
        vm.prank(rando);
        vm.expectRevert("Pausable: paused");
        crowdinvesting.buy(1, type(uint256).max, address(this));

        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(_admin);
        crowdinvesting.unpause();
    }
}
