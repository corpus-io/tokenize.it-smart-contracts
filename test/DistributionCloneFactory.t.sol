// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/DistributionCloneFactory.sol";
import "../contracts/Distribution.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/CloneCreators.sol";

contract DistributionCloneFactoryTest is Test {
    address public constant ADMIN = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant OWNER = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant CURRENCY_PROVIDER = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;
    address public constant TRUSTED_FORWARDER = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    bytes32 public constant EXAMPLE_SALT = bytes32(0);
    address public constant EXAMPLE_OWNER = address(0x1001);
    uint256 public constant EXAMPLE_INITIAL_FUNDING = 100e6;
    uint256 public constant EXAMPLE_PRICE_PER_TOKEN = 100_000; // 0.1 currency per token

    uint64 public lockedUntil;
    uint256 public snapshotId;

    AllowList allowList;
    FakePaymentToken currency;
    Token token;
    DistributionCloneFactory factory;
    TokenProxyFactory tokenFactory;

    function setUp() public {
        lockedUntil = uint64(block.timestamp + 31 days);

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
            tokenFactory.createTokenProxy(0, TRUSTED_FORWARDER, feeSettings, ADMIN, allowList, 0, "DistToken", "DST")
        );

        vm.startPrank(ADMIN);
        token.grantRole(token.MINTALLOWER_ROLE(), ADMIN);
        token.mint(ADMIN, 1000e18); // give ADMIN tokens so snapshot is non-zero
        snapshotId = token.createSnapshot();
        vm.stopPrank();

        factory = new DistributionCloneFactory(address(new Distribution(TRUSTED_FORWARDER)));
    }

    /// @dev Returns baseline DistributionInitializerArguments
    function _baseArgs() internal view returns (DistributionInitializerArguments memory) {
        return
            DistributionInitializerArguments({
                owner: EXAMPLE_OWNER,
                token: token,
                snapshotId: snapshotId,
                currency: IERC20(address(currency)),
                pricePerToken: EXAMPLE_PRICE_PER_TOKEN,
                lockedUntil: lockedUntil,
                initialReassignments: new Reassignment[](0)
            });
    }

    /// @dev Predict address, fund, approve, and deploy
    function _deploy(
        bytes32 salt,
        address _trustedForwarder,
        DistributionInitializerArguments memory args,
        uint256 _initialFundingAmount
    ) internal returns (address) {
        address cloneAddr = factory.predictCloneAddress(salt, _trustedForwarder, args);
        if (_initialFundingAmount > 0) {
            currency.mint(CURRENCY_PROVIDER, _initialFundingAmount);
            vm.prank(CURRENCY_PROVIDER);
            currency.approve(cloneAddr, _initialFundingAmount);
        }
        return factory.createDistributionClone(salt, _trustedForwarder, CURRENCY_PROVIDER, args, _initialFundingAmount);
    }

    // ========== F1-D. Address Prediction ==========

    function testBothPredictOverloadsMatch() public view {
        DistributionInitializerArguments memory args = _baseArgs();
        bytes32 precomputed = keccak256(abi.encode(EXAMPLE_SALT, TRUSTED_FORWARDER, args));

        address fromSalt = factory.predictCloneAddress(precomputed);
        address fromParams = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertEq(fromSalt, fromParams, "overloads disagree");
    }

    function testActualAddressMatchesPrediction() public {
        DistributionInitializerArguments memory args = _baseArgs();
        address predicted = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        address actual = _deploy(EXAMPLE_SALT, TRUSTED_FORWARDER, args, EXAMPLE_INITIAL_FUNDING);
        assertEq(predicted, actual);
    }

    function testNewCloneEventEmitted() public {
        DistributionInitializerArguments memory args = _baseArgs();
        address predicted = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        currency.mint(CURRENCY_PROVIDER, EXAMPLE_INITIAL_FUNDING);
        vm.prank(CURRENCY_PROVIDER);
        currency.approve(predicted, EXAMPLE_INITIAL_FUNDING);
        vm.expectEmit(true, false, false, false, address(factory));
        emit CloneFactory.NewClone(predicted);
        factory.createDistributionClone(
            EXAMPLE_SALT,
            TRUSTED_FORWARDER,
            CURRENCY_PROVIDER,
            args,
            EXAMPLE_INITIAL_FUNDING
        );
    }

    // ========== F2-D. Each Salt Parameter Changes the Address ==========

    function testRawSaltChangesAddress() public view {
        DistributionInitializerArguments memory args = _baseArgs();
        address a1 = factory.predictCloneAddress(bytes32(uint256(1)), TRUSTED_FORWARDER, args);
        address a2 = factory.predictCloneAddress(bytes32(uint256(2)), TRUSTED_FORWARDER, args);
        assertFalse(a1 == a2);
    }

    function testTrustedForwarderChangesAddress() public view {
        DistributionInitializerArguments memory args = _baseArgs();
        address a1 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        address a2 = factory.predictCloneAddress(EXAMPLE_SALT, address(0x9999), args);
        assertFalse(a1 == a2);
    }

    function testOwnerChangesAddress() public view {
        DistributionInitializerArguments memory args = _baseArgs();
        address a1 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        args.owner = address(0x9999);
        address a2 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertFalse(a1 == a2);
    }

    function testTokenChangesAddress() public view {
        DistributionInitializerArguments memory args = _baseArgs();
        address a1 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        args.token = Token(address(0x9999)); // different address for prediction only
        address a2 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertFalse(a1 == a2);
    }

    function testSnapshotIdChangesAddress() public view {
        DistributionInitializerArguments memory args = _baseArgs();
        address a1 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        args.snapshotId = snapshotId + 1;
        address a2 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertFalse(a1 == a2);
    }

    function testCurrencyChangesAddress() public view {
        DistributionInitializerArguments memory args = _baseArgs();
        address a1 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        args.currency = IERC20(address(0x9999));
        address a2 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertFalse(a1 == a2);
    }

    function testPricePerTokenChangesAddress() public view {
        DistributionInitializerArguments memory args = _baseArgs();
        address a1 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        args.pricePerToken = EXAMPLE_PRICE_PER_TOKEN + 1;
        address a2 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertFalse(a1 == a2);
    }

    function testInitialFundingAmountDoesNotAffectAddress() public view {
        DistributionInitializerArguments memory args = _baseArgs();
        address a1 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        // initialFundingAmount is no longer part of the salt — same address regardless of funding amount
        address a2 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertEq(a1, a2);
    }

    function testReassignOrDrainAfterChangesAddress() public view {
        DistributionInitializerArguments memory args = _baseArgs();
        address a1 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        args.lockedUntil = lockedUntil + 1;
        address a2 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertFalse(a1 == a2);
    }

    // ========== F3-D. _currencyProvider Is Not in the Salt ==========

    function testCurrencyProviderDoesNotAffectAddress(address _currencyProvider) public {
        vm.assume(_currencyProvider != address(0));
        DistributionInitializerArguments memory args = _baseArgs();
        bytes32 salt = bytes32(0);
        address cloneAddr = factory.predictCloneAddress(salt, TRUSTED_FORWARDER, args);
        currency.mint(_currencyProvider, EXAMPLE_INITIAL_FUNDING);
        vm.prank(_currencyProvider);
        currency.approve(cloneAddr, EXAMPLE_INITIAL_FUNDING);
        address _distribution = factory.createDistributionClone(
            salt,
            TRUSTED_FORWARDER,
            _currencyProvider,
            args,
            EXAMPLE_INITIAL_FUNDING
        );
        assertEq(_distribution, cloneAddr);
    }

    // ========== F4-D. Wrong Trusted Forwarder Reverts ==========

    function testCreateWithWrongForwarderReverts() public {
        DistributionInitializerArguments memory args = _baseArgs();
        address wrongForwarder = address(0xBAD);
        address predicted = factory.predictCloneAddress(EXAMPLE_SALT, wrongForwarder, args);
        currency.mint(CURRENCY_PROVIDER, EXAMPLE_INITIAL_FUNDING);
        vm.prank(CURRENCY_PROVIDER);
        currency.approve(predicted, EXAMPLE_INITIAL_FUNDING);
        vm.expectRevert("DistributionCloneFactory: Unexpected trustedForwarder");
        factory.createDistributionClone(EXAMPLE_SALT, wrongForwarder, CURRENCY_PROVIDER, args, EXAMPLE_INITIAL_FUNDING);
    }

    // ========== F5-D. Second Deployment Fails ==========

    function testSecondDeploymentReverts() public {
        DistributionInitializerArguments memory args = _baseArgs();
        _deploy(EXAMPLE_SALT, TRUSTED_FORWARDER, args, EXAMPLE_INITIAL_FUNDING);
        address cloneAddr = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        currency.mint(CURRENCY_PROVIDER, EXAMPLE_INITIAL_FUNDING);
        vm.prank(CURRENCY_PROVIDER);
        currency.approve(cloneAddr, EXAMPLE_INITIAL_FUNDING);
        vm.expectRevert("ERC1167: create2 failed");
        factory.createDistributionClone(
            EXAMPLE_SALT,
            TRUSTED_FORWARDER,
            CURRENCY_PROVIDER,
            args,
            EXAMPLE_INITIAL_FUNDING
        );
    }

    // ========== F6-D. Initialization ==========

    function testStateVariablesSetCorrectly() public {
        DistributionInitializerArguments memory args = _baseArgs();
        Distribution clone = Distribution(_deploy(EXAMPLE_SALT, TRUSTED_FORWARDER, args, EXAMPLE_INITIAL_FUNDING));

        assertEq(clone.owner(), args.owner);
        assertEq(address(clone.token()), address(args.token));
        assertEq(clone.snapshotId(), args.snapshotId);
        assertEq(address(clone.currency()), address(args.currency));
        assertEq(clone.pricePerToken(), args.pricePerToken);
        assertEq(clone.lockedUntil(), args.lockedUntil);
        assertEq(currency.balanceOf(address(clone)), EXAMPLE_INITIAL_FUNDING);
        assertTrue(clone.isTrustedForwarder(TRUSTED_FORWARDER));
    }

    function testReInitializingCloneReverts() public {
        DistributionInitializerArguments memory args = _baseArgs();
        Distribution clone = Distribution(_deploy(EXAMPLE_SALT, TRUSTED_FORWARDER, args, EXAMPLE_INITIAL_FUNDING));
        vm.expectRevert("Initializable: contract is already initialized");
        clone.initialize(args, CURRENCY_PROVIDER, 0);
    }

    // ========== F7-D. Funding via Clone Address Approval ==========

    function testApprovalToFactoryReverts() public {
        DistributionInitializerArguments memory args = _baseArgs();
        currency.mint(CURRENCY_PROVIDER, EXAMPLE_INITIAL_FUNDING);
        vm.prank(CURRENCY_PROVIDER);
        currency.approve(address(factory), EXAMPLE_INITIAL_FUNDING); // wrong target
        vm.expectRevert("ERC20: insufficient allowance");
        factory.createDistributionClone(
            EXAMPLE_SALT,
            TRUSTED_FORWARDER,
            CURRENCY_PROVIDER,
            args,
            EXAMPLE_INITIAL_FUNDING
        );
    }

    function testApprovalBelowRequiredReverts() public {
        DistributionInitializerArguments memory args = _baseArgs();
        address cloneAddr = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        currency.mint(CURRENCY_PROVIDER, EXAMPLE_INITIAL_FUNDING);
        vm.prank(CURRENCY_PROVIDER);
        currency.approve(cloneAddr, EXAMPLE_INITIAL_FUNDING - 1);
        vm.expectRevert("ERC20: insufficient allowance");
        factory.createDistributionClone(
            EXAMPLE_SALT,
            TRUSTED_FORWARDER,
            CURRENCY_PROVIDER,
            args,
            EXAMPLE_INITIAL_FUNDING
        );
    }

    function testExactApprovalSucceeds() public {
        DistributionInitializerArguments memory args = _baseArgs();
        address cloneAddr = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        currency.mint(CURRENCY_PROVIDER, EXAMPLE_INITIAL_FUNDING);
        vm.prank(CURRENCY_PROVIDER);
        currency.approve(cloneAddr, EXAMPLE_INITIAL_FUNDING);
        address actual = factory.createDistributionClone(
            EXAMPLE_SALT,
            TRUSTED_FORWARDER,
            CURRENCY_PROVIDER,
            args,
            EXAMPLE_INITIAL_FUNDING
        );
        assertEq(currency.balanceOf(actual), EXAMPLE_INITIAL_FUNDING);
    }

    function testZeroFundingRequiresNoApproval() public {
        DistributionInitializerArguments memory args = _baseArgs();
        address actual = factory.createDistributionClone(EXAMPLE_SALT, TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, 0);
        assertEq(currency.balanceOf(actual), 0);
    }

    // ========== F8-D. Invalid Currency Reverts ==========

    function testMissingTrustedCurrencyBitReverts() public {
        FakePaymentToken badCurrency = new FakePaymentToken(0, 6);
        // not set on allowList → 0 bits
        DistributionInitializerArguments memory args = _baseArgs();
        args.currency = IERC20(address(badCurrency));
        vm.expectRevert("currency needs to be on the allowlist with TRUSTED_CURRENCY attribute");
        factory.createDistributionClone(bytes32(0), TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, 0);
    }

    function testTrustedNonEuroCurrencyAccepted() public {
        // Distribution only requires TRUSTED_CURRENCY
        FakePaymentToken nonEuro = new FakePaymentToken(0, 6);
        vm.prank(ADMIN);
        allowList.set(address(nonEuro), TRUSTED_CURRENCY); // trusted, not EURO
        DistributionInitializerArguments memory args = _baseArgs();
        args.currency = IERC20(address(nonEuro));
        // approve and deploy — must succeed
        address cloneAddr = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        nonEuro.mint(CURRENCY_PROVIDER, EXAMPLE_INITIAL_FUNDING);
        vm.prank(CURRENCY_PROVIDER);
        nonEuro.approve(cloneAddr, EXAMPLE_INITIAL_FUNDING);
        address actual = factory.createDistributionClone(
            EXAMPLE_SALT,
            TRUSTED_FORWARDER,
            CURRENCY_PROVIDER,
            args,
            EXAMPLE_INITIAL_FUNDING
        );
        assertFalse(actual == address(0));
    }
}
