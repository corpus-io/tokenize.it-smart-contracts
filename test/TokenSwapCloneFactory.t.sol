// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "../contracts/factories/TokenSwapCloneFactory.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/FeeSettingsCloneFactory.sol";
import "../contracts/common/IFeeSettings.sol";
import "./resources/ERC2771Helper.sol";
import "./resources/CloneCreators.sol";

contract TokenSwapCloneFactoryTest is Test {
    using ECDSA for bytes32;

    AllowList allowList;
    FeeSettings feeSettings;
    TokenProxyFactory tokenFactory;
    TokenSwap tokenSwapImplementation;
    TokenSwapCloneFactory tokenSwapFactory;
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
    address public constant EXAMPLE_RECEIVER = address(54);
    uint256 public constant EXAMPLE_TOKEN_PRICE = 2;
    IERC20 public constant EXAMPLE_CURRENCY = IERC20(address(1));
    Token exampleToken;
    address public constant EXAMPLE_HOLDER = address(55);

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
            feeTypes[1] = FeeSettings.FeeTypeInit(FeeTypes.CROWDINVESTING, 1000, 100, FEE_SETTINGS_AND_ALLOW_LIST_OWNER);
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

        tokenSwapImplementation = new TokenSwap(TRUSTED_FORWARDER);
        tokenSwapFactory = new TokenSwapCloneFactory(address(tokenSwapImplementation));
    }

    function testAddressPrediction1(uint256 _tokenPrice, IERC20 _currency) public {
        vm.assume(address(_currency) != address(0));
        vm.assume(_tokenPrice > 0);

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
        tokenSwapImplementation = new TokenSwap(EXAMPLE_TRUSTED_FORWARDER);
        tokenSwapFactory = new TokenSwapCloneFactory(address(tokenSwapImplementation));

        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            EXAMPLE_OWNER,
            EXAMPLE_RECEIVER,
            EXAMPLE_HOLDER,
            _tokenPrice,
            _currency,
            _token
        );

        address expected1 = tokenSwapFactory.predictCloneAddress(
            keccak256(abi.encode(EXAMPLE_RAW_SALT, EXAMPLE_TRUSTED_FORWARDER, arguments))
        );

        address expected2 = tokenSwapFactory.predictCloneAddress(EXAMPLE_RAW_SALT, EXAMPLE_TRUSTED_FORWARDER, arguments);

        assertEq(expected1, expected2, "address prediction with salt and params not equal");

        address actual = tokenSwapFactory.createTokenSwapClone(EXAMPLE_RAW_SALT, EXAMPLE_TRUSTED_FORWARDER, arguments);
        assertEq(expected1, actual, "address prediction failed");
    }

    function testAddressPrediction2(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        address _receiver
    ) public {
        vm.assume(_trustedForwarder != address(0));
        vm.assume(_owner != address(0));
        vm.assume(_receiver != address(0));

        // create new clone factory so we can use the local forwarder
        tokenSwapImplementation = new TokenSwap(_trustedForwarder);
        tokenSwapFactory = new TokenSwapCloneFactory(address(tokenSwapImplementation));

        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            _owner,
            _receiver,
            EXAMPLE_HOLDER,
            EXAMPLE_TOKEN_PRICE,
            EXAMPLE_CURRENCY,
            exampleToken
        );

        bytes32 salt = keccak256(abi.encode(_rawSalt, _trustedForwarder, arguments));

        address expected1 = tokenSwapFactory.predictCloneAddress(salt);
        address expected2 = tokenSwapFactory.predictCloneAddress(_rawSalt, _trustedForwarder, arguments);

        assertEq(expected1, expected2, "address prediction with salt and params not equal");

        address actual = tokenSwapFactory.createTokenSwapClone(_rawSalt, _trustedForwarder, arguments);
        assertEq(expected1, actual, "address prediction failed");
    }

    function testChangingOneValueInStructChangesAddress(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        address _receiver,
        uint256 _tokenPrice
    ) public {
        vm.assume(_trustedForwarder != address(0));
        vm.assume(_owner != address(0));
        vm.assume(_receiver != address(0));
        vm.assume(_tokenPrice > 1);

        // create new clone factory so we can use the local forwarder
        tokenSwapImplementation = new TokenSwap(_trustedForwarder);
        tokenSwapFactory = new TokenSwapCloneFactory(address(tokenSwapImplementation));

        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            _owner,
            _receiver,
            EXAMPLE_HOLDER,
            _tokenPrice,
            EXAMPLE_CURRENCY,
            exampleToken
        );

        address expected1 = tokenSwapFactory.predictCloneAddress(_rawSalt, _trustedForwarder, arguments);

        arguments.tokenPrice = _tokenPrice - 1;

        address expected2 = tokenSwapFactory.predictCloneAddress(_rawSalt, _trustedForwarder, arguments);

        assertFalse(expected1 == expected2, "these addresses can not be equal");
    }

    function testSecondDeploymentFails(
        bytes32 _rawSalt,
        address _owner,
        address _receiver,
        uint256 _tokenPrice,
        IERC20 _currency,
        address _holder
    ) public {
        vm.assume(_owner != address(0));
        vm.assume(address(_currency) != address(0));
        vm.assume(_receiver != address(0));
        vm.assume(_tokenPrice > 0);
        vm.assume(_holder != address(0));

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

        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            _owner,
            _receiver,
            _holder,
            _tokenPrice,
            _currency,
            _token
        );

        // deploy once
        tokenSwapFactory.createTokenSwapClone(_rawSalt, TRUSTED_FORWARDER, arguments);

        // deploy again
        vm.expectRevert("ERC1167: create2 failed");
        tokenSwapFactory.createTokenSwapClone(_rawSalt, TRUSTED_FORWARDER, arguments);
    }

    function testInitialization1(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        address _receiver,
        address _holder
    ) public {
        vm.assume(_trustedForwarder != address(0));
        vm.assume(_owner != address(0));
        vm.assume(_receiver != address(0));
        vm.assume(_holder != address(0));

        // create new clone factory so we can use the local forwarder
        tokenSwapImplementation = new TokenSwap(_trustedForwarder);
        tokenSwapFactory = new TokenSwapCloneFactory(address(tokenSwapImplementation));

        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            _owner,
            _receiver,
            _holder,
            EXAMPLE_TOKEN_PRICE,
            EXAMPLE_CURRENCY,
            exampleToken
        );

        TokenSwap tokenSwap = TokenSwap(tokenSwapFactory.createTokenSwapClone(_rawSalt, _trustedForwarder, arguments));

        assertTrue(tokenSwap.isTrustedForwarder(_trustedForwarder), "TRUSTED_FORWARDER not set");
        assertEq(tokenSwap.owner(), _owner, "owner not set");
        assertEq(tokenSwap.receiver(), _receiver, "receiver not set");
        assertEq(tokenSwap.holder(), _holder, "holder not set");
    }

    function testInitialization2(uint256 _tokenPrice, IERC20 _currency) public {
        vm.assume(address(_currency) != address(0));
        vm.assume(_tokenPrice > 0);

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
        tokenSwapImplementation = new TokenSwap(EXAMPLE_TRUSTED_FORWARDER);
        tokenSwapFactory = new TokenSwapCloneFactory(address(tokenSwapImplementation));

        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            EXAMPLE_OWNER,
            EXAMPLE_RECEIVER,
            EXAMPLE_HOLDER,
            _tokenPrice,
            _currency,
            _token
        );

        TokenSwap tokenSwap = TokenSwap(
            tokenSwapFactory.createTokenSwapClone(EXAMPLE_RAW_SALT, EXAMPLE_TRUSTED_FORWARDER, arguments)
        );

        assertEq(tokenSwap.tokenPrice(), _tokenPrice, "tokenPrice not set");
        assertEq(address(tokenSwap.currency()), address(_currency), "currency not set");
        assertEq(address(tokenSwap.token()), address(_token), "token not set");
    }

    function testInitializationRevertsWithUntrustedCurrency(address someCurrency, uint256 currencyAttributes) public {
        vm.assume(someCurrency != address(0));
        vm.assume(currencyAttributes != TRUSTED_CURRENCY);
        vm.prank(FEE_SETTINGS_AND_ALLOW_LIST_OWNER);
        allowList.set(someCurrency, currencyAttributes);

        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            EXAMPLE_OWNER,
            EXAMPLE_RECEIVER,
            EXAMPLE_HOLDER,
            EXAMPLE_TOKEN_PRICE,
            IERC20(someCurrency),
            exampleToken
        );

        vm.expectRevert("currency needs to be on the allowlist with TRUSTED_CURRENCY attribute");
        tokenSwapFactory.createTokenSwapClone("salt", TRUSTED_FORWARDER, arguments);

        // test deployment succeeds with trusted currency
        vm.prank(FEE_SETTINGS_AND_ALLOW_LIST_OWNER);
        allowList.set(someCurrency, TRUSTED_CURRENCY);
        tokenSwapFactory.createTokenSwapClone("salt", TRUSTED_FORWARDER, arguments);
    }

    /*
        pausing and unpausing
    */
    function testPausing(address _admin, address rando) public {
        vm.assume(_admin != address(0));
        vm.assume(_admin != TRUSTED_FORWARDER);
        vm.assume(rando != address(0));
        vm.assume(rando != _admin);
        vm.assume(rando != TRUSTED_FORWARDER);

        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            _admin,
            _admin,
            EXAMPLE_HOLDER,
            EXAMPLE_TOKEN_PRICE,
            EXAMPLE_CURRENCY,
            exampleToken
        );

        TokenSwap tokenSwap = TokenSwap(tokenSwapFactory.createTokenSwapClone(0, TRUSTED_FORWARDER, arguments));

        vm.prank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        tokenSwap.pause();

        assertFalse(tokenSwap.paused());
        vm.prank(_admin);
        tokenSwap.pause();
        assertTrue(tokenSwap.paused());

        vm.prank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        tokenSwap.unpause();

        // can't buy when paused
        vm.prank(rando);
        vm.expectRevert("Pausable: paused");
        tokenSwap.buy(1, type(uint256).max, address(this));

        vm.prank(_admin);
        tokenSwap.unpause();
    }
}
