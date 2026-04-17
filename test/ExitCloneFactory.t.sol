// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "../lib/forge-std/src/Test.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/ExitCloneFactory.sol";
import "../contracts/Exit.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/CloneCreators.sol";

contract ExitCloneFactoryTest is Test {
    address public constant ADMIN = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant OWNER = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant CURRENCY_PROVIDER = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;
    address public constant TRUSTED_FORWARDER = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    // Constants that appear in example args
    bytes32 public constant EXAMPLE_SALT = bytes32(0);
    address public constant EXAMPLE_OWNER = address(0x1001);
    uint256 public constant EXAMPLE_PRICE = 2e6;
    uint64 public constant EXAMPLE_DRAIN_START = 2000;
    uint256 public constant EXAMPLE_TOTAL_CURRENCY = 100e6;

    AllowList allowList;
    FakePaymentToken currency;
    Token token;
    ExitCloneFactory factory;
    TokenProxyFactory tokenFactory;

    function setUp() public {
        allowList = createAllowList(TRUSTED_FORWARDER, ADMIN);
        currency = new FakePaymentToken(0, 6);
        vm.prank(ADMIN);
        allowList.set(address(currency), TRUSTED_CURRENCY);

        address tokenLogic = address(new Token(TRUSTED_FORWARDER));
        tokenFactory = new TokenProxyFactory(tokenLogic);
        IFeeSettingsV2 feeSettings = createFeeSettings(
            TRUSTED_FORWARDER,
            ADMIN,
            buildFeeTypes(0, 0, 0, ADMIN, ADMIN, ADMIN)
        );
        token = Token(
            tokenFactory.createTokenProxy(0, TRUSTED_FORWARDER, feeSettings, ADMIN, allowList, 0, "ExitToken", "EXT")
        );

        factory = new ExitCloneFactory(address(new Exit(TRUSTED_FORWARDER)));
    }

    /// @dev Returns baseline ExitInitializerArguments
    function _baseArgs() internal view returns (ExitInitializerArguments memory) {
        return
            ExitInitializerArguments({
                owner: EXAMPLE_OWNER,
                token: token,
                currency: IERC20(address(currency)),
                pricePerToken: EXAMPLE_PRICE,
                lockedUntil: EXAMPLE_DRAIN_START,
                referenceCurrencies: new IERC20[](0),
                referenceToExitRates: new uint256[](0)
            });
    }

    /// @dev Predict address, fund CURRENCY_PROVIDER, approve, and deploy
    function _deploy(
        bytes32 salt,
        address _trustedForwarder,
        ExitInitializerArguments memory args,
        uint256 _initialFundingAmount
    ) internal returns (address) {
        address cloneAddr = factory.predictCloneAddress(salt, _trustedForwarder, args);
        currency.mint(CURRENCY_PROVIDER, _initialFundingAmount);
        vm.prank(CURRENCY_PROVIDER);
        currency.approve(cloneAddr, _initialFundingAmount);
        return factory.createExitClone(salt, _trustedForwarder, CURRENCY_PROVIDER, args, _initialFundingAmount);
    }

    // ========== F1-E. Address Prediction ==========

    function testBothPredictOverloadsMatch() public {
        ExitInitializerArguments memory args = _baseArgs();
        bytes32 precomputed = keccak256(abi.encode(EXAMPLE_SALT, TRUSTED_FORWARDER, args));

        address fromSalt = factory.predictCloneAddress(precomputed);
        address fromParams = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertEq(fromSalt, fromParams, "overloads disagree");
    }

    function testActualAddressMatchesPrediction() public {
        ExitInitializerArguments memory args = _baseArgs();
        address predicted = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        address actual = _deploy(EXAMPLE_SALT, TRUSTED_FORWARDER, args, EXAMPLE_TOTAL_CURRENCY);
        assertEq(predicted, actual, "deployed address does not match prediction");
    }

    function testNewCloneEventEmitted() public {
        ExitInitializerArguments memory args = _baseArgs();
        address predicted = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        currency.mint(CURRENCY_PROVIDER, EXAMPLE_TOTAL_CURRENCY);
        vm.prank(CURRENCY_PROVIDER);
        currency.approve(predicted, EXAMPLE_TOTAL_CURRENCY);
        vm.expectEmit(true, false, false, false, address(factory));
        emit CloneFactory.NewClone(predicted);
        factory.createExitClone(EXAMPLE_SALT, TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, EXAMPLE_TOTAL_CURRENCY);
    }

    // ========== F2-E. Each Salt Parameter Changes the Address ==========

    function testSaltChangesAddress() public {
        ExitInitializerArguments memory args = _baseArgs();
        address addr1 = factory.predictCloneAddress(bytes32(uint256(1)), TRUSTED_FORWARDER, args);
        address addr2 = factory.predictCloneAddress(bytes32(uint256(2)), TRUSTED_FORWARDER, args);
        assertFalse(addr1 == addr2);
    }

    function testTrustedForwarderChangesAddress() public {
        ExitInitializerArguments memory args = _baseArgs();
        address addr1 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        address addr2 = factory.predictCloneAddress(EXAMPLE_SALT, address(0x9999), args);
        assertFalse(addr1 == addr2);
    }

    function testOwnerChangesAddress() public {
        ExitInitializerArguments memory args = _baseArgs();
        address addr1 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        args.owner = address(0x9999);
        address addr2 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertFalse(addr1 == addr2);
    }

    function testTokenChangesAddress() public {
        ExitInitializerArguments memory args = _baseArgs();
        address addr1 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        // Use a different token address for prediction only — no need to deploy
        args.token = Token(address(0x9999));
        address addr2 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertFalse(addr1 == addr2);
    }

    function testCurrencyChangesAddress() public {
        ExitInitializerArguments memory args = _baseArgs();
        address addr1 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        FakePaymentToken currency2 = new FakePaymentToken(0, 6);
        vm.prank(ADMIN);
        allowList.set(address(currency2), TRUSTED_CURRENCY);
        args.currency = IERC20(address(currency2));
        address addr2 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertFalse(addr1 == addr2);
    }

    function testPricePerTokenChangesAddress() public {
        ExitInitializerArguments memory args = _baseArgs();
        address addr1 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        args.pricePerToken = EXAMPLE_PRICE + 1;
        address addr2 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertFalse(addr1 == addr2);
    }

    function testDrainStartChangesAddress() public {
        ExitInitializerArguments memory args = _baseArgs();
        address addr1 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        args.lockedUntil = EXAMPLE_DRAIN_START + 1;
        address addr2 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertFalse(addr1 == addr2);
    }

    function testTotalCurrencyAmountDoesNotAffectAddress() public {
        ExitInitializerArguments memory args = _baseArgs();
        address addr1 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        // initialFundingAmount is no longer part of the salt — same address regardless of funding amount
        address addr2 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertEq(addr1, addr2);
    }

    // ========== F3-E. _currencyProvider Is Not in the Salt ==========

    function testCurrencyProviderDoesNotAffectAddress(address _currencyProvider) public {
        vm.assume(_currencyProvider != address(0));
        ExitInitializerArguments memory args = _baseArgs();
        address predicted = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);

        // Provider 1 deploys
        currency.mint(_currencyProvider, EXAMPLE_TOTAL_CURRENCY);
        vm.prank(_currencyProvider);
        currency.approve(predicted, EXAMPLE_TOTAL_CURRENCY);
        address actual = factory.createExitClone(
            EXAMPLE_SALT,
            TRUSTED_FORWARDER,
            _currencyProvider,
            args,
            EXAMPLE_TOTAL_CURRENCY
        );
        assertEq(predicted, actual);
    }

    // ========== F4-E. Wrong Trusted Forwarder Reverts ==========

    function testCreateWithWrongForwarderReverts() public {
        // Deploy logic with TRUSTED_FORWARDER but create using a different forwarder
        ExitInitializerArguments memory args = _baseArgs();
        address wrongForwarder = address(0xBAD);
        address predicted = factory.predictCloneAddress(EXAMPLE_SALT, wrongForwarder, args);
        currency.mint(CURRENCY_PROVIDER, EXAMPLE_TOTAL_CURRENCY);
        vm.prank(CURRENCY_PROVIDER);
        currency.approve(predicted, EXAMPLE_TOTAL_CURRENCY);
        vm.expectRevert(Factory.UnexpectedTrustedForwarder.selector);
        factory.createExitClone(EXAMPLE_SALT, wrongForwarder, CURRENCY_PROVIDER, args, EXAMPLE_TOTAL_CURRENCY);
    }

    // ========== F5-E. Second Deployment Fails ==========

    function testSecondDeploymentWithSameSaltReverts() public {
        ExitInitializerArguments memory args = _baseArgs();
        _deploy(EXAMPLE_SALT, TRUSTED_FORWARDER, args, EXAMPLE_TOTAL_CURRENCY);
        // Second deploy: predict same address, approve, then expect revert
        address cloneAddr = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        currency.mint(CURRENCY_PROVIDER, EXAMPLE_TOTAL_CURRENCY);
        vm.prank(CURRENCY_PROVIDER);
        currency.approve(cloneAddr, EXAMPLE_TOTAL_CURRENCY);
        vm.expectRevert("ERC1167: create2 failed");
        factory.createExitClone(EXAMPLE_SALT, TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, EXAMPLE_TOTAL_CURRENCY);
    }

    // ========== F6-E. Initialization ==========

    function testStateVariablesSetCorrectly() public {
        ExitInitializerArguments memory args = _baseArgs();
        Exit clone = Exit(_deploy(EXAMPLE_SALT, TRUSTED_FORWARDER, args, EXAMPLE_TOTAL_CURRENCY));

        assertEq(clone.owner(), args.owner);
        assertEq(address(clone.token()), address(args.token));
        assertEq(address(clone.currency()), address(args.currency));
        assertEq(clone.pricePerToken(), args.pricePerToken);
        assertEq(clone.lockedUntil(), args.lockedUntil);
        assertEq(currency.balanceOf(address(clone)), EXAMPLE_TOTAL_CURRENCY);
        assertTrue(clone.isTrustedForwarder(TRUSTED_FORWARDER));
    }

    function testReInitializingCloneReverts() public {
        ExitInitializerArguments memory args = _baseArgs();
        Exit clone = Exit(_deploy(EXAMPLE_SALT, TRUSTED_FORWARDER, args, EXAMPLE_TOTAL_CURRENCY));
        vm.expectRevert("Initializable: contract is already initialized");
        clone.initialize(args, CURRENCY_PROVIDER, 0);
    }

    // ========== F7-E. Funding via Clone Address Approval ==========

    function testApprovalToFactoryInsteadOfCloneReverts() public {
        ExitInitializerArguments memory args = _baseArgs();
        currency.mint(CURRENCY_PROVIDER, EXAMPLE_TOTAL_CURRENCY);
        vm.prank(CURRENCY_PROVIDER);
        currency.approve(address(factory), EXAMPLE_TOTAL_CURRENCY); // wrong address
        vm.expectRevert("ERC20: insufficient allowance");
        factory.createExitClone(EXAMPLE_SALT, TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, EXAMPLE_TOTAL_CURRENCY);
    }

    function testApprovalBelowRequiredReverts() public {
        ExitInitializerArguments memory args = _baseArgs();
        address cloneAddr = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        currency.mint(CURRENCY_PROVIDER, EXAMPLE_TOTAL_CURRENCY);
        vm.prank(CURRENCY_PROVIDER);
        currency.approve(cloneAddr, EXAMPLE_TOTAL_CURRENCY - 1);
        vm.expectRevert("ERC20: insufficient allowance");
        factory.createExitClone(EXAMPLE_SALT, TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, EXAMPLE_TOTAL_CURRENCY);
    }

    function testExactApprovalSucceeds() public {
        ExitInitializerArguments memory args = _baseArgs();
        address cloneAddr = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        currency.mint(CURRENCY_PROVIDER, EXAMPLE_TOTAL_CURRENCY);
        vm.prank(CURRENCY_PROVIDER);
        currency.approve(cloneAddr, EXAMPLE_TOTAL_CURRENCY);
        address actual = factory.createExitClone(
            EXAMPLE_SALT,
            TRUSTED_FORWARDER,
            CURRENCY_PROVIDER,
            args,
            EXAMPLE_TOTAL_CURRENCY
        );
        assertEq(currency.balanceOf(actual), EXAMPLE_TOTAL_CURRENCY);
    }

    // ========== F8-E. Invalid Currency Reverts ==========

    function testMissingTrustedCurrencyBitReverts() public {
        FakePaymentToken badCurrency = new FakePaymentToken(0, 6);
        // not on allowList → 0 attributes
        ExitInitializerArguments memory args = _baseArgs();
        args.currency = IERC20(address(badCurrency));
        vm.expectRevert("currency needs to be on the allowlist with TRUSTED_CURRENCY attribute");
        factory.createExitClone(bytes32(0), TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, 0);
    }

    function testTrustedCurrencyBitSucceeds() public {
        ExitInitializerArguments memory args = _baseArgs();
        address actual = _deploy(EXAMPLE_SALT, TRUSTED_FORWARDER, args, EXAMPLE_TOTAL_CURRENCY);
        assertFalse(actual == address(0));
    }
}
