// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "../contracts/factories/TokenSwapCloneFactory.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/FeeSettingsCloneFactory.sol";
import "./resources/ERC2771Helper.sol";
import "./resources/CloneCreators.sol";

contract TokenSwapCloneFactoryTest is Test {
    using ECDSA for bytes32;

    AllowList allowList;
    FeeSettings feeSettings;
    TokenProxyFactory tokenFactory;
    TokenSwap tokenSwapImplementation;
    TokenSwapCloneFactory tokenSwapFactory;
    address public constant trustedForwarder = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;
    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant requirer = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant mintAllower = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant minter = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant burner = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;
    address public constant transfererAdmin = 0x5109709EcFA91a80626ff3989d68f67F5B1dD125;
    address public constant transferer = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant pauser = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant feeSettingsAndAllowListOwner = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;

    uint256 requirements = 0;

    // these are defined globally to make some tests work in spite of compiler limitations
    bytes32 public constant exampleRawSalt = 0x00000000;
    address public constant exampleTrustedForwarder = address(52);
    address public constant exampleOwner = address(53);
    address public constant exampleReceiver = address(54);
    uint256 public constant exampleMinAmountPerTransaction = 1;
    uint256 public constant exampleTokenPrice = 2;
    IERC20 public constant exampleCurrency = IERC20(address(1));
    Token exampleToken;
    address public constant exampleHolder = address(55);

    event RequirementsChanged(uint256 newRequirements);

    function setUp() public {
        vm.startPrank(feeSettingsAndAllowListOwner);
        allowList = createAllowList(trustedForwarder, feeSettingsAndAllowListOwner);

        Fees memory fees = Fees(100, 100, 100, 0);
        FeeSettings feeSettingsLogicContract = new FeeSettings(trustedForwarder);
        FeeSettingsCloneFactory feeSettingsCloneFactory = new FeeSettingsCloneFactory(
            address(feeSettingsLogicContract)
        );
        feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone(
                0,
                trustedForwarder,
                feeSettingsAndAllowListOwner,
                fees,
                feeSettingsAndAllowListOwner,
                feeSettingsAndAllowListOwner,
                feeSettingsAndAllowListOwner
            )
        );
        vm.stopPrank();

        vm.prank(feeSettingsAndAllowListOwner);
        allowList.set(address(exampleCurrency), TRUSTED_CURRENCY);

        Token tokenImplementation = new Token(trustedForwarder);
        tokenFactory = new TokenProxyFactory(address(tokenImplementation));

        exampleToken = Token(
            tokenFactory.createTokenProxy(
                "2",
                trustedForwarder,
                feeSettings,
                address(this),
                allowList,
                0,
                "Test Token",
                "TST"
            )
        );

        tokenSwapImplementation = new TokenSwap(trustedForwarder);
        tokenSwapFactory = new TokenSwapCloneFactory(address(tokenSwapImplementation));
    }

    function testAddressPrediction1(
        uint256 _tokenPrice,
        IERC20 _currency
    ) public {
        vm.assume(address(_currency) != address(0));
        vm.assume(_tokenPrice > 0);

        vm.prank(feeSettingsAndAllowListOwner);
        allowList.set(address(_currency), TRUSTED_CURRENCY);

        Token _token = Token(
            tokenFactory.createTokenProxy(
                0,
                trustedForwarder,
                feeSettings,
                address(this),
                allowList,
                0,
                "Test Token",
                "TST"
            )
        );

        // create new clone factory so we can use the local forwarder
        tokenSwapImplementation = new TokenSwap(exampleTrustedForwarder);
        tokenSwapFactory = new TokenSwapCloneFactory(address(tokenSwapImplementation));

        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            exampleOwner,
            exampleReceiver,
            exampleMinAmountPerTransaction,
            _tokenPrice,
            _currency,
            _token,
            exampleHolder
        );

        address expected1 = tokenSwapFactory.predictCloneAddress(
            keccak256(abi.encode(exampleRawSalt, exampleTrustedForwarder, arguments))
        );

        address expected2 = tokenSwapFactory.predictCloneAddress(exampleRawSalt, exampleTrustedForwarder, arguments);

        assertEq(expected1, expected2, "address prediction with salt and params not equal");

        address actual = tokenSwapFactory.createTokenSwapClone(
            exampleRawSalt,
            exampleTrustedForwarder,
            arguments
        );
        assertEq(expected1, actual, "address prediction failed");
    }

    function testAddressPrediction2(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        address _receiver,
        uint256 _minAmountPerTransaction
    ) public {
        vm.assume(_trustedForwarder != address(0));
        vm.assume(_owner != address(0));
        vm.assume(_receiver != address(0));
        vm.assume(_minAmountPerTransaction > 0);

        // create new clone factory so we can use the local forwarder
        tokenSwapImplementation = new TokenSwap(_trustedForwarder);
        tokenSwapFactory = new TokenSwapCloneFactory(address(tokenSwapImplementation));

        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            _owner,
            _receiver,
            _minAmountPerTransaction,
            exampleTokenPrice,
            exampleCurrency,
            exampleToken,
            exampleHolder
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
        uint256 _minAmountPerTransaction
    ) public {
        vm.assume(_trustedForwarder != address(0));
        vm.assume(_owner != address(0));
        vm.assume(_receiver != address(0));
        vm.assume(_minAmountPerTransaction > 1);

        // create new clone factory so we can use the local forwarder
        tokenSwapImplementation = new TokenSwap(_trustedForwarder);
        tokenSwapFactory = new TokenSwapCloneFactory(address(tokenSwapImplementation));

        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            _owner,
            _receiver,
            _minAmountPerTransaction,
            exampleTokenPrice,
            exampleCurrency,
            exampleToken,
            exampleHolder
        );

        address expected1 = tokenSwapFactory.predictCloneAddress(_rawSalt, _trustedForwarder, arguments);

        arguments.minAmountPerTransaction = _minAmountPerTransaction - 1;

        address expected2 = tokenSwapFactory.predictCloneAddress(_rawSalt, _trustedForwarder, arguments);

        assertFalse(expected1 == expected2, "these addresses can not be equal");
    }

    function testSecondDeploymentFails(
        bytes32 _rawSalt,
        address _owner,
        address _receiver,
        uint256 _minAmountPerTransaction,
        uint256 _tokenPrice,
        IERC20 _currency,
        address _holder
    ) public {
        vm.assume(_owner != address(0));
        vm.assume(address(_currency) != address(0));
        vm.assume(_receiver != address(0));
        vm.assume(_minAmountPerTransaction > 0);
        vm.assume(_tokenPrice > 0);
        vm.assume(_holder != address(0));

        vm.prank(feeSettingsAndAllowListOwner);
        allowList.set(address(_currency), TRUSTED_CURRENCY);

        Token _token = Token(
            tokenFactory.createTokenProxy(
                0,
                trustedForwarder,
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
            _minAmountPerTransaction,
            _tokenPrice,
            _currency,
            _token,
            _holder
        );

        // deploy once
        tokenSwapFactory.createTokenSwapClone(_rawSalt, trustedForwarder, arguments);

        // deploy again
        vm.expectRevert("ERC1167: create2 failed");
        tokenSwapFactory.createTokenSwapClone(_rawSalt, trustedForwarder, arguments);
    }

    function testInitialization1(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        address _receiver,
        uint256 _minAmountPerTransaction,
        address _holder
    ) public {
        vm.assume(_trustedForwarder != address(0));
        vm.assume(_owner != address(0));
        vm.assume(_receiver != address(0));
        vm.assume(_minAmountPerTransaction > 0);
        vm.assume(_holder != address(0));

        // create new clone factory so we can use the local forwarder
        tokenSwapImplementation = new TokenSwap(_trustedForwarder);
        tokenSwapFactory = new TokenSwapCloneFactory(address(tokenSwapImplementation));

        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            _owner,
            _receiver,
            _minAmountPerTransaction,
            exampleTokenPrice,
            exampleCurrency,
            exampleToken,
            _holder
        );

        TokenSwap tokenSwap = TokenSwap(
            tokenSwapFactory.createTokenSwapClone(_rawSalt, _trustedForwarder, arguments)
        );

        assertTrue(tokenSwap.isTrustedForwarder(_trustedForwarder), "trustedForwarder not set");
        assertEq(tokenSwap.owner(), _owner, "owner not set");
        assertEq(tokenSwap.receiver(), _receiver, "receiver not set");
        assertEq(tokenSwap.minAmountPerTransaction(), _minAmountPerTransaction, "minAmountPerTransaction not set");
        assertEq(tokenSwap.holder(), _holder, "holder not set");
    }

    function testInitialization2(
        uint256 _tokenPrice,
        IERC20 _currency
    ) public {
        vm.assume(address(_currency) != address(0));
        vm.assume(_tokenPrice > 0);

        vm.prank(feeSettingsAndAllowListOwner);
        allowList.set(address(_currency), TRUSTED_CURRENCY);

        Token _token = Token(
            tokenFactory.createTokenProxy(
                0,
                trustedForwarder,
                feeSettings,
                address(this),
                allowList,
                0,
                "Test Token",
                "TST"
            )
        );

        // create new clone factory so we can use the local forwarder
        tokenSwapImplementation = new TokenSwap(exampleTrustedForwarder);
        tokenSwapFactory = new TokenSwapCloneFactory(address(tokenSwapImplementation));

        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            exampleOwner,
            exampleReceiver,
            exampleMinAmountPerTransaction,
            _tokenPrice,
            _currency,
            _token,
            exampleHolder
        );

        TokenSwap tokenSwap = TokenSwap(
            tokenSwapFactory.createTokenSwapClone(exampleRawSalt, exampleTrustedForwarder, arguments)
        );

        assertEq(tokenSwap.tokenPrice(), _tokenPrice, "tokenPrice not set");
        assertEq(address(tokenSwap.currency()), address(_currency), "currency not set");
        assertEq(address(tokenSwap.token()), address(_token), "token not set");
    }

    function testInitializationRevertsWithUntrustedCurrency(address someCurrency, uint256 currencyAttributes) public {
        vm.assume(someCurrency != address(0));
        vm.assume(currencyAttributes != TRUSTED_CURRENCY);
        vm.prank(feeSettingsAndAllowListOwner);
        allowList.set(someCurrency, currencyAttributes);

        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            exampleOwner,
            exampleReceiver,
            exampleMinAmountPerTransaction,
            exampleTokenPrice,
            IERC20(someCurrency),
            exampleToken,
            exampleHolder
        );

        vm.expectRevert("currency needs to be on the allowlist with TRUSTED_CURRENCY attribute");
        tokenSwapFactory.createTokenSwapClone("salt", trustedForwarder, arguments);

        // test deployment succeeds with trusted currency
        vm.prank(feeSettingsAndAllowListOwner);
        allowList.set(someCurrency, TRUSTED_CURRENCY);
        tokenSwapFactory.createTokenSwapClone("salt", trustedForwarder, arguments);
    }

    /*
        pausing and unpausing
    */
    function testPausing(address _admin, address rando) public {
        vm.assume(_admin != address(0));
        vm.assume(rando != address(0));
        vm.assume(rando != _admin);

        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            _admin,
            _admin,
            exampleMinAmountPerTransaction,
            exampleTokenPrice,
            exampleCurrency,
            exampleToken,
            exampleHolder
        );

        TokenSwap tokenSwap = TokenSwap(
            tokenSwapFactory.createTokenSwapClone(0, trustedForwarder, arguments)
        );

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
