// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "../lib/forge-std/src/Test.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/CoinvestedPositionCloneFactory.sol";
import "../contracts/CoinvestedPosition.sol";
import "../contracts/GlobalTokenExitRegistry.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/CloneCreators.sol";

contract CoinvestedPositionCloneFactoryTest is Test {
    address public constant ADMIN = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant OWNER = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant RECEIVER = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant LEAD_A = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant LEAD_B = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;
    address public constant TRUSTED_FORWARDER = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    bytes32 public constant EXAMPLE_SALT = bytes32(0);
    uint256 public constant EXAMPLE_BASE_PRICE = 100e6;

    AllowList allowList;
    FakePaymentToken currency;
    Token token;
    GlobalTokenExitRegistry tokenExitRegistry;
    CoinvestedPositionCloneFactory factory;
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
            tokenFactory.createTokenProxy(0, TRUSTED_FORWARDER, feeSettings, ADMIN, allowList, 0, "CPToken", "CPT")
        );

        factory = new CoinvestedPositionCloneFactory(address(new CoinvestedPosition(TRUSTED_FORWARDER)));

        tokenExitRegistry = new GlobalTokenExitRegistry(TRUSTED_FORWARDER);
    }

    /// @dev Returns baseline arguments with two lead investors.
    ///     We use a function instead of a variable because the array needs to be in memory
    function _baseArgs() internal view returns (CoinvestedPositionInitializerArguments memory) {
        LeadInvestor[] memory leads = new LeadInvestor[](2);
        leads[0] = LeadInvestor({account: LEAD_A, profitFraction: type(uint64).max / 10}); // 10%
        leads[1] = LeadInvestor({account: LEAD_B, profitFraction: type(uint64).max / 20}); // 5%
        return
            CoinvestedPositionInitializerArguments({
                owner: OWNER,
                receiver: RECEIVER,
                leadInvestors: leads,
                basePrice: EXAMPLE_BASE_PRICE,
                baseCurrency: IERC20(address(currency)),
                token: token,
                lockedUntil: 0,
                tokenExitRegistry: tokenExitRegistry
            });
    }

    function _deploy(
        bytes32 salt,
        address _trustedForwarder,
        CoinvestedPositionInitializerArguments memory args
    ) internal returns (CoinvestedPosition) {
        return CoinvestedPosition(factory.createCoinvestedPositionClone(salt, _trustedForwarder, args));
    }

    // ========== F1-CP. Address Prediction ==========

    function testBothPredictOverloadsMatch() public view {
        CoinvestedPositionInitializerArguments memory args = _baseArgs();
        bytes32 precomputed = keccak256(abi.encode(EXAMPLE_SALT, TRUSTED_FORWARDER, args));

        address fromSalt = factory.predictCloneAddress(precomputed);
        address fromParams = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertEq(fromSalt, fromParams);
    }

    function testActualAddressMatchesPrediction() public {
        CoinvestedPositionInitializerArguments memory args = _baseArgs();
        address predicted = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        address actual = factory.createCoinvestedPositionClone(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertEq(predicted, actual);
    }

    function testNewCloneEventEmitted() public {
        CoinvestedPositionInitializerArguments memory args = _baseArgs();
        address predicted = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        vm.expectEmit(true, false, false, false, address(factory));
        emit CloneFactory.NewClone(predicted);
        factory.createCoinvestedPositionClone(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
    }

    // ========== F2-CP. Each Salt Parameter Changes the Address ==========

    function testRawSaltChangesAddress() public view {
        CoinvestedPositionInitializerArguments memory args = _baseArgs();
        address a1 = factory.predictCloneAddress(bytes32(uint256(1)), TRUSTED_FORWARDER, args);
        address a2 = factory.predictCloneAddress(bytes32(uint256(2)), TRUSTED_FORWARDER, args);
        assertFalse(a1 == a2);
    }

    function testTrustedForwarderChangesAddress() public view {
        CoinvestedPositionInitializerArguments memory args = _baseArgs();
        address a1 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        address a2 = factory.predictCloneAddress(EXAMPLE_SALT, address(0x9999), args);
        assertFalse(a1 == a2);
    }

    function testOwnerChangesAddress() public view {
        CoinvestedPositionInitializerArguments memory args = _baseArgs();
        address a1 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        args.owner = address(0x9999);
        address a2 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertFalse(a1 == a2);
    }

    function testReceiverChangesAddress() public view {
        CoinvestedPositionInitializerArguments memory args = _baseArgs();
        address a1 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        args.receiver = address(0x9999);
        address a2 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertFalse(a1 == a2);
    }

    function testBasePriceChangesAddress() public view {
        CoinvestedPositionInitializerArguments memory args = _baseArgs();
        address a1 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        args.basePrice = EXAMPLE_BASE_PRICE + 1;
        address a2 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertFalse(a1 == a2);
    }

    function testBaseCurrencyChangesAddress() public view {
        CoinvestedPositionInitializerArguments memory args = _baseArgs();
        address a1 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        args.baseCurrency = IERC20(address(0x9999));
        address a2 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertFalse(a1 == a2);
    }

    function testTokenChangesAddress() public view {
        CoinvestedPositionInitializerArguments memory args = _baseArgs();
        address a1 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        args.token = Token(address(0x9999));
        address a2 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertFalse(a1 == a2);
    }

    function testLeadInvestorsCarryFractionChangesAddress() public view {
        CoinvestedPositionInitializerArguments memory args = _baseArgs();
        address a1 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        args.leadInvestors[0].profitFraction = type(uint64).max / 10 + 1;
        address a2 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertFalse(a1 == a2);
    }

    function testLeadInvestorsLengthChangesAddress() public view {
        CoinvestedPositionInitializerArguments memory args = _baseArgs();
        address a1 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);

        LeadInvestor[] memory threeLeads = new LeadInvestor[](3);
        threeLeads[0] = args.leadInvestors[0];
        threeLeads[1] = args.leadInvestors[1];
        threeLeads[2] = LeadInvestor({account: address(0xBBB), profitFraction: 1});
        args.leadInvestors = threeLeads;
        address a2 = factory.predictCloneAddress(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertFalse(a1 == a2);
    }

    // ========== F3-CP. Wrong Trusted Forwarder Reverts ==========

    function testCreateWithWrongForwarderReverts() public {
        CoinvestedPositionInitializerArguments memory args = _baseArgs();
        vm.expectRevert("CoinvestedPositionCloneFactory: Unexpected trustedForwarder");
        factory.createCoinvestedPositionClone(EXAMPLE_SALT, address(0xBAD), args);
    }

    // ========== F4-CP. Second Deployment Fails ==========

    function testSecondDeploymentReverts() public {
        CoinvestedPositionInitializerArguments memory args = _baseArgs();
        factory.createCoinvestedPositionClone(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        vm.expectRevert("ERC1167: create2 failed");
        factory.createCoinvestedPositionClone(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
    }

    // ========== F5-CP. Initialization ==========

    function testStateVariablesSetCorrectly() public {
        CoinvestedPositionInitializerArguments memory args = _baseArgs();
        CoinvestedPosition cp = _deploy(EXAMPLE_SALT, TRUSTED_FORWARDER, args);

        assertEq(cp.owner(), args.owner);
        assertEq(cp.receiver(), args.receiver);
        assertEq(address(cp.currency()), address(args.baseCurrency));
        assertEq(address(cp.token()), address(args.token));
        assertEq(cp.basePrice(), args.basePrice);
        assertEq(cp.getLeadInvestorsCount(), 2);
        assertTrue(cp.paused()); // starts paused
        assertEq(cp.tokenPrice(), 0);
    }

    function testLeadInvestorsStoredCorrectly() public {
        CoinvestedPositionInitializerArguments memory args = _baseArgs();
        CoinvestedPosition cp = _deploy(EXAMPLE_SALT, TRUSTED_FORWARDER, args);

        (address accA, uint64 fracA) = cp.leadInvestors(0);
        (address accB, uint64 fracB) = cp.leadInvestors(1);
        assertEq(accA, LEAD_A);
        assertEq(fracA, type(uint64).max / 10);
        assertEq(accB, LEAD_B);
        assertEq(fracB, type(uint64).max / 20);
    }

    function testFuzzLeadInvestorsStoredCorrectly(
        address[100] calldata accounts,
        uint64[100] calldata fractions,
        uint8 count
    ) public {
        vm.assume(count > 0 && count <= 100);

        // build a valid lead investors array: non-zero accounts, non-zero fractions, sum fits uint64
        LeadInvestor[] memory leads = new LeadInvestor[](count);
        uint256 usedSlots = 0;
        uint64 runningSum = 0;
        for (uint256 i = 0; i < count; i++) {
            address acc = accounts[i];
            uint64 frac = fractions[i];
            if (acc == address(0)) continue;
            if (frac == 0) continue;
            if (uint256(runningSum) + uint256(frac) > type(uint64).max) break;
            leads[usedSlots] = LeadInvestor({account: acc, profitFraction: frac});
            runningSum += frac;
            usedSlots++;
        }
        vm.assume(usedSlots > 0);

        // trim array to usedSlots
        LeadInvestor[] memory trimmed = new LeadInvestor[](usedSlots);
        for (uint256 i = 0; i < usedSlots; i++) {
            trimmed[i] = leads[i];
        }

        CoinvestedPositionInitializerArguments memory args = _baseArgs();
        args.leadInvestors = trimmed;

        CoinvestedPosition cp = _deploy(bytes32(uint256(1)), TRUSTED_FORWARDER, args);

        assertEq(cp.getLeadInvestorsCount(), usedSlots);
        for (uint256 i = 0; i < usedSlots; i++) {
            (address acc, uint64 frac) = cp.leadInvestors(i);
            assertEq(acc, trimmed[i].account);
            assertEq(frac, trimmed[i].profitFraction);
        }
    }

    function testTrustedForwarderSetCorrectly() public {
        CoinvestedPositionInitializerArguments memory args = _baseArgs();
        CoinvestedPosition cp = _deploy(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertTrue(cp.isTrustedForwarder(TRUSTED_FORWARDER));
    }

    function testReInitializingCloneReverts() public {
        CoinvestedPositionInitializerArguments memory args = _baseArgs();
        CoinvestedPosition cp = _deploy(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        vm.expectRevert("Initializable: contract is already initialized");
        cp.initialize(args);
    }

    // ========== F6-CP. Invalid Currency Reverts ==========

    function testMissingTrustedCurrencyBitReverts() public {
        FakePaymentToken badCurrency = new FakePaymentToken(0, 6);
        // not on allowList → 0 attributes, no TRUSTED_CURRENCY bit
        CoinvestedPositionInitializerArguments memory args = _baseArgs();
        args.baseCurrency = IERC20(address(badCurrency));
        vm.expectRevert(UntrustedCurrency.selector);
        factory.createCoinvestedPositionClone(bytes32(0), TRUSTED_FORWARDER, args);
    }

    function testTrustedCurrencyBitSucceeds() public {
        CoinvestedPositionInitializerArguments memory args = _baseArgs();
        address actual = factory.createCoinvestedPositionClone(EXAMPLE_SALT, TRUSTED_FORWARDER, args);
        assertFalse(actual == address(0));
    }
}
