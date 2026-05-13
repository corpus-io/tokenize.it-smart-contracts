// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "../lib/forge-std/src/Test.sol";

import "../contracts/FeeDistributor.sol";
import "../contracts/CoinvestedPosition.sol";
import "../contracts/common/Errors.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/CoinvestedPositionCloneFactory.sol";
import "../contracts/FeeSettings.sol";
import "../contracts/GlobalTokenExitRegistry.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/CloneCreators.sol";

/**
 * @dev Minimal stand-in for CoinvestedPosition that lets tests control the lead-investor
 *      list freely, including the zero-investors edge case that the real contract forbids.
 *      Function selectors must match those on CoinvestedPosition exactly.
 */
contract MockCoinvestedPosition {
    LeadInvestor[] private _investors;

    function addLeadInvestor(address account, uint64 profitFraction) external {
        _investors.push(LeadInvestor({account: account, profitFraction: profitFraction}));
    }

    function clearLeadInvestors() external {
        delete _investors;
    }

    function getLeadInvestorsCount() external view returns (uint256) {
        return _investors.length;
    }

    /// @dev Matches the auto-generated getter for the public `LeadInvestor[] public leadInvestors` array.
    function leadInvestors(uint256 index) external view returns (address account, uint64 profitFraction) {
        return (_investors[index].account, _investors[index].profitFraction);
    }
}

contract FeeDistributorTest is Test {
    event FeeDistributed(address indexed feePayer, address indexed currency, uint256 feeAmount);

    // ── Well-known addresses ──────────────────────────────────────────────────
    address public constant ADMIN = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant OWNER = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant RECEIVER = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant LEAD_A = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant LEAD_B = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant LEAD_C = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;
    address public constant FEE_PAYER = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant TRUSTED_FORWARDER = 0xa109709ecfA91A80626ff3989D68F67F5b1dD12a;

    // ── Test constants ────────────────────────────────────────────────────────
    // 10 % of uint64.max (floor)
    uint64 public constant CARRY_10PCT = type(uint64).max / 10;
    // 5 % of uint64.max (floor)
    uint64 public constant CARRY_5PCT = type(uint64).max / 20;
    // Equal shares
    uint64 public constant CARRY_HALF = type(uint64).max / 2;

    uint256 public constant FEE_AMOUNT = 300e6; // 300 USDC

    // ── Shared state ──────────────────────────────────────────────────────────
    FeeDistributor feeDistributor;
    MockCoinvestedPosition mockPosition;
    FakePaymentToken usdc; // 6 decimals

    // Full infrastructure for real-CoinvestedPosition integration tests
    AllowList allowList;
    IFeeSettingsV2 feeSettings;
    Token token;
    TokenProxyFactory tokenFactory;
    GlobalTokenExitRegistry tokenExitRegistry;
    CoinvestedPosition positionLogic;
    CoinvestedPositionCloneFactory positionFactory;
    CoinvestedPosition realPosition;

    // ── setUp ─────────────────────────────────────────────────────────────────

    function setUp() public {
        feeDistributor = new FeeDistributor();
        mockPosition = new MockCoinvestedPosition();

        // USDC-like token (6 decimals)
        usdc = new FakePaymentToken(0, 6);
        usdc.mint(FEE_PAYER, FEE_AMOUNT * 10);

        // Deploy full infrastructure for real-position tests
        allowList = createAllowList(TRUSTED_FORWARDER, ADMIN);
        feeSettings = createFeeSettings(TRUSTED_FORWARDER, ADMIN, buildFeeTypes(0, 0, 0, ADMIN, ADMIN, ADMIN));

        vm.prank(ADMIN);
        allowList.set(address(usdc), TRUSTED_CURRENCY);

        address tokenLogic = address(new Token(TRUSTED_FORWARDER));
        tokenFactory = new TokenProxyFactory(tokenLogic);
        token = Token(
            tokenFactory.createTokenProxy(0, TRUSTED_FORWARDER, feeSettings, ADMIN, allowList, 0, "TestToken", "TTK")
        );

        tokenExitRegistry = new GlobalTokenExitRegistry(TRUSTED_FORWARDER);

        positionLogic = new CoinvestedPosition(TRUSTED_FORWARDER);
        positionFactory = new CoinvestedPositionCloneFactory(address(positionLogic));

        LeadInvestor[] memory investors = new LeadInvestor[](2);
        investors[0] = LeadInvestor({account: LEAD_A, profitFraction: CARRY_10PCT});
        investors[1] = LeadInvestor({account: LEAD_B, profitFraction: CARRY_5PCT});

        realPosition = CoinvestedPosition(
            positionFactory.createCoinvestedPositionClone(
                bytes32(0),
                TRUSTED_FORWARDER,
                CoinvestedPositionInitializerArguments({
                    owner: OWNER,
                    leadInvestors: investors,
                    basePrice: 100e6,
                    baseCurrency: IERC20(address(usdc)),
                    token: token,
                    lockedUntil: 1,
                    tokenExitRegistry: tokenExitRegistry
                })
            )
        );
    }

    // ── Helper ────────────────────────────────────────────────────────────────

    /// Approve feeDistributor for FEE_PAYER and return the approved amount.
    function _approveFeeDistributor(uint256 amount) internal {
        vm.prank(FEE_PAYER);
        usdc.approve(address(feeDistributor), amount);
    }

    // =========================================================================
    // Section 1 – Input validation
    // =========================================================================

    function testPayFeeZeroFeePayerReverts() public {
        mockPosition.addLeadInvestor(LEAD_A, CARRY_10PCT);
        vm.expectRevert(FeeDistributor.ZeroFeePayerAddress.selector);
        feeDistributor.payFee(address(0), usdc, FEE_AMOUNT, CoinvestedPosition(address(mockPosition)));
    }

    function testPayFeeZeroCurrencyReverts() public {
        mockPosition.addLeadInvestor(LEAD_A, CARRY_10PCT);
        vm.expectRevert(ZeroCurrencyAddress.selector);
        feeDistributor.payFee(FEE_PAYER, IERC20(address(0)), FEE_AMOUNT, CoinvestedPosition(address(mockPosition)));
    }

    function testPayFeeZeroAmountReverts() public {
        mockPosition.addLeadInvestor(LEAD_A, CARRY_10PCT);
        vm.expectRevert(ZeroAmount.selector);
        feeDistributor.payFee(FEE_PAYER, usdc, 0, CoinvestedPosition(address(mockPosition)));
    }

    function testPayFeeZeroCoinvestedPositionReverts() public {
        vm.expectRevert(FeeDistributor.ZeroCoinvestedPositionAddress.selector);
        feeDistributor.payFee(FEE_PAYER, usdc, FEE_AMOUNT, CoinvestedPosition(address(0)));
    }

    function testPayFeeNoLeadInvestorsReverts() public {
        // mockPosition has zero investors (never called addLeadInvestor)
        _approveFeeDistributor(FEE_AMOUNT);
        vm.expectRevert(NoLeadInvestors.selector);
        feeDistributor.payFee(FEE_PAYER, usdc, FEE_AMOUNT, CoinvestedPosition(address(mockPosition)));
    }

    function testPayFeeInsufficientAllowanceReverts() public {
        mockPosition.addLeadInvestor(LEAD_A, CARRY_10PCT);
        // No approval → transferFrom fails
        vm.expectRevert("ERC20: insufficient allowance");
        feeDistributor.payFee(FEE_PAYER, usdc, FEE_AMOUNT, CoinvestedPosition(address(mockPosition)));
    }

    function testPayFeeInsufficientBalanceReverts() public {
        mockPosition.addLeadInvestor(LEAD_A, CARRY_10PCT);
        uint256 tooMuch = usdc.balanceOf(FEE_PAYER) + 1;
        vm.prank(FEE_PAYER);
        usdc.approve(address(feeDistributor), tooMuch);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        feeDistributor.payFee(FEE_PAYER, usdc, tooMuch, CoinvestedPosition(address(mockPosition)));
    }

    // =========================================================================
    // Section 2 – Single lead investor
    // =========================================================================

    function testSingleLeadInvestorReceivesFullFee() public {
        mockPosition.addLeadInvestor(LEAD_A, CARRY_10PCT);
        _approveFeeDistributor(FEE_AMOUNT);

        uint256 balanceBefore = usdc.balanceOf(LEAD_A);
        feeDistributor.payFee(FEE_PAYER, usdc, FEE_AMOUNT, CoinvestedPosition(address(mockPosition)));

        // Single investor is always the "last" investor and absorbs all remaining fee.
        assertEq(usdc.balanceOf(LEAD_A), balanceBefore + FEE_AMOUNT, "single investor should receive full fee");
        assertEq(usdc.balanceOf(address(feeDistributor)), 0, "feeDistributor should hold no residual balance");
    }

    function testSingleLeadInvestorFeePayerBalanceDecreases() public {
        mockPosition.addLeadInvestor(LEAD_A, CARRY_10PCT);
        _approveFeeDistributor(FEE_AMOUNT);

        uint256 payerBefore = usdc.balanceOf(FEE_PAYER);
        feeDistributor.payFee(FEE_PAYER, usdc, FEE_AMOUNT, CoinvestedPosition(address(mockPosition)));

        assertEq(usdc.balanceOf(FEE_PAYER), payerBefore - FEE_AMOUNT, "feePayer balance should decrease by feeAmount");
    }

    // =========================================================================
    // Section 3 – Multiple lead investors: proportional distribution
    // =========================================================================

    function testTwoEqualInvestorsSplitFeeEvenly() public {
        // Both have equal carry → each should get FEE_AMOUNT / 2 (last absorbs dust)
        mockPosition.addLeadInvestor(LEAD_A, CARRY_HALF);
        mockPosition.addLeadInvestor(LEAD_B, CARRY_HALF);
        _approveFeeDistributor(FEE_AMOUNT);

        feeDistributor.payFee(FEE_PAYER, usdc, FEE_AMOUNT, CoinvestedPosition(address(mockPosition)));

        uint256 shareA = usdc.balanceOf(LEAD_A);
        uint256 shareB = usdc.balanceOf(LEAD_B);

        assertEq(shareA + shareB, FEE_AMOUNT, "total distributed must equal feeAmount");
        // Equal fractions → shares differ by at most 1 (rounding dust)
        assertApproxEqAbs(shareA, shareB, 1, "equal-carry investors should receive near-equal shares");
    }

    function testTwoUnequalInvestorsSplitProportionally() public {
        // LEAD_A: 10%, LEAD_B: 5% → LEAD_A gets 2/3, LEAD_B gets 1/3 of the fee
        mockPosition.addLeadInvestor(LEAD_A, CARRY_10PCT);
        mockPosition.addLeadInvestor(LEAD_B, CARRY_5PCT);
        _approveFeeDistributor(FEE_AMOUNT);

        feeDistributor.payFee(FEE_PAYER, usdc, FEE_AMOUNT, CoinvestedPosition(address(mockPosition)));

        uint256 shareA = usdc.balanceOf(LEAD_A);
        uint256 shareB = usdc.balanceOf(LEAD_B);

        assertEq(shareA + shareB, FEE_AMOUNT, "total distributed must equal feeAmount");
        // 10 % share is twice as large as 5 % share, up to 1 bit of rounding
        assertApproxEqAbs(shareA, 2 * shareB, 1, "10pct carry should receive ~2x the 5pct carry share");
    }

    function testThreeLeadInvestorsFullDistribution() public {
        // Three investors: 10 / 5 / 5 → 50 % / 25 % / 25 %
        mockPosition.addLeadInvestor(LEAD_A, CARRY_10PCT);
        mockPosition.addLeadInvestor(LEAD_B, CARRY_5PCT);
        mockPosition.addLeadInvestor(LEAD_C, CARRY_5PCT);
        _approveFeeDistributor(FEE_AMOUNT);

        feeDistributor.payFee(FEE_PAYER, usdc, FEE_AMOUNT, CoinvestedPosition(address(mockPosition)));

        uint256 shareA = usdc.balanceOf(LEAD_A);
        uint256 shareB = usdc.balanceOf(LEAD_B);
        uint256 shareC = usdc.balanceOf(LEAD_C);

        assertEq(shareA + shareB + shareC, FEE_AMOUNT, "total distributed must equal feeAmount");
        assertApproxEqAbs(shareA, FEE_AMOUNT / 2, 1, "50pct carry should receive half the fee");
        assertApproxEqAbs(shareB, FEE_AMOUNT / 4, 1, "25pct carry should receive a quarter");
        assertApproxEqAbs(shareC, FEE_AMOUNT / 4, 1, "25pct carry should receive a quarter");
    }

    // =========================================================================
    // Section 4 – Rounding / dust handling
    // =========================================================================

    /// When feeAmount is 1 bit with two investors, the first gets 0 (integer division),
    /// the last investor absorbs the remaining 1 bit.
    function testSmallFeeRoundingDustGoesToLastInvestor() public {
        mockPosition.addLeadInvestor(LEAD_A, CARRY_HALF);
        mockPosition.addLeadInvestor(LEAD_B, CARRY_HALF);
        uint256 tinyFee = 1;
        usdc.mint(FEE_PAYER, tinyFee);
        vm.prank(FEE_PAYER);
        usdc.approve(address(feeDistributor), tinyFee);

        feeDistributor.payFee(FEE_PAYER, usdc, tinyFee, CoinvestedPosition(address(mockPosition)));

        // First investor: share = (CARRY_HALF * 1) / (CARRY_HALF + CARRY_HALF)
        //                       = CARRY_HALF / (2 * CARRY_HALF) = 0 (integer division)
        // Last investor: remainingFee = 1 - 0 = 1
        assertEq(usdc.balanceOf(LEAD_A), 0, "first investor gets 0 when share rounds down to zero");
        assertEq(usdc.balanceOf(LEAD_B), 1, "last investor absorbs the single remaining bit");
    }

    /// Full amount is always distributed regardless of how many rounding-zero shares there are.
    function testFullAmountAlwaysDistributed(uint256 feeAmount) public {
        vm.assume(feeAmount > 0 && feeAmount <= 1_000_000e6);

        mockPosition.addLeadInvestor(LEAD_A, CARRY_10PCT);
        mockPosition.addLeadInvestor(LEAD_B, CARRY_5PCT);

        usdc.mint(FEE_PAYER, feeAmount);
        vm.prank(FEE_PAYER);
        usdc.approve(address(feeDistributor), feeAmount);

        uint256 payerBefore = usdc.balanceOf(FEE_PAYER);
        feeDistributor.payFee(FEE_PAYER, usdc, feeAmount, CoinvestedPosition(address(mockPosition)));

        uint256 totalReceived = usdc.balanceOf(LEAD_A) + usdc.balanceOf(LEAD_B);
        assertEq(usdc.balanceOf(FEE_PAYER), payerBefore - feeAmount, "feePayer should lose exactly feeAmount");
        assertEq(totalReceived, feeAmount, "sum of shares must equal feeAmount");
        assertEq(usdc.balanceOf(address(feeDistributor)), 0, "feeDistributor must hold no residual balance");
    }

    // =========================================================================
    // Section 5 – Events
    // =========================================================================

    function testFeeDistributedEventEmitted() public {
        mockPosition.addLeadInvestor(LEAD_A, CARRY_10PCT);
        _approveFeeDistributor(FEE_AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit FeeDistributed(FEE_PAYER, address(usdc), FEE_AMOUNT);
        feeDistributor.payFee(FEE_PAYER, usdc, FEE_AMOUNT, CoinvestedPosition(address(mockPosition)));
    }

    // =========================================================================
    // Section 6 – Integration with real CoinvestedPosition
    // =========================================================================

    /// Verifies FeeDistributor works end-to-end against a live CoinvestedPosition clone,
    /// reading actual carry fractions and distributing accordingly.
    function testIntegrationWithRealCoinvestedPosition() public {
        _approveFeeDistributor(FEE_AMOUNT);

        uint256 leadABefore = usdc.balanceOf(LEAD_A);
        uint256 leadBBefore = usdc.balanceOf(LEAD_B);

        feeDistributor.payFee(FEE_PAYER, usdc, FEE_AMOUNT, realPosition);

        uint256 shareA = usdc.balanceOf(LEAD_A) - leadABefore;
        uint256 shareB = usdc.balanceOf(LEAD_B) - leadBBefore;

        assertEq(shareA + shareB, FEE_AMOUNT, "total distributed must equal feeAmount");

        // LEAD_A has CARRY_10PCT = uint64.max / 10, LEAD_B has CARRY_5PCT = uint64.max / 20
        // ratio 2:1, so LEAD_A receives ~2× what LEAD_B receives
        assertApproxEqAbs(shareA, 2 * shareB, 1, "LEAD_A (10pct carry) should receive ~2x LEAD_B (5pct carry)");
    }

    /// Verifies that FeeDistributor reads the live lead-investor list from the position
    /// contract and not from any cached state — calling payFee twice with the same mock
    /// (after mutating it between calls) should reflect the updated investor list.
    function testDistributionReflectsCurrentLeadInvestorList() public {
        // Round 1: only LEAD_A
        mockPosition.addLeadInvestor(LEAD_A, CARRY_10PCT);
        _approveFeeDistributor(FEE_AMOUNT);
        feeDistributor.payFee(FEE_PAYER, usdc, FEE_AMOUNT, CoinvestedPosition(address(mockPosition)));
        uint256 firstRoundLeadA = usdc.balanceOf(LEAD_A);
        uint256 firstRoundLeadB = usdc.balanceOf(LEAD_B);

        assertEq(firstRoundLeadA, FEE_AMOUNT, "round 1: LEAD_A alone should receive full fee");
        assertEq(firstRoundLeadB, 0, "round 1: LEAD_B should receive nothing");

        // Mutate the mock to add LEAD_B
        mockPosition.addLeadInvestor(LEAD_B, CARRY_10PCT);
        vm.prank(FEE_PAYER);
        usdc.approve(address(feeDistributor), FEE_AMOUNT);

        feeDistributor.payFee(FEE_PAYER, usdc, FEE_AMOUNT, CoinvestedPosition(address(mockPosition)));
        uint256 secondRoundLeadA = usdc.balanceOf(LEAD_A) - firstRoundLeadA;
        uint256 secondRoundLeadB = usdc.balanceOf(LEAD_B) - firstRoundLeadB;

        assertEq(secondRoundLeadA + secondRoundLeadB, FEE_AMOUNT, "round 2: full fee must be distributed");
        // Equal fractions → equal shares (± dust)
        assertApproxEqAbs(secondRoundLeadA, secondRoundLeadB, 1, "round 2: equal carry should split evenly");
    }
}
